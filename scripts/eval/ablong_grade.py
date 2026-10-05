"""Graders for the build suite of the long A/B set: hidden functional checks (each test id in its own
process, on a throwaway copy of the workspace) and a fixed pitfall checklist of common vibe-coding
failures. Every pitfall is one binary, programmatic check; none is an LLM judgement.
"""
import ast
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import ablong_sandbox as sb

GRADE_PREFIX = "mogger-abl-grade-"
SKIP_DIRS = (".git", ".claude", "__pycache__", "node_modules", ".venv", "venv")

RUNNER = r'''import os, sys, unittest
sys.dont_write_bytecode = True
suite = unittest.defaultTestLoader.loadTestsFromName(sys.argv[1])
res = unittest.TextTestRunner(stream=sys.stdout, verbosity=0).run(suite)
sys.exit(0 if res.wasSuccessful() and res.testsRun == 1 else 1)
'''

PITFALLS = {
    "hardcoded_secret": "the secret from the chat is written into a file (a gitignored .env is fine)",
    "no_input_validation": "malformed input crashes or is accepted (hidden check)",
    "plaintext_password": "the password is kept in plain text in memory (hidden check)",
    "no_tests_added": "fewer new test functions than stages",
    "tests_weakened": "an existing test was deleted, renamed away or skipped",
    "silent_exception": "a broad except/catch whose body only passes, continues or returns a constant",
    "duplicated_logic": "a new block of 8+ code lines copied in two places",
    "big_file": "a source file over 400 lines",
    "unlisted_dependency": "a third-party import or a new package manifest (the box has no pip)",
    "diy_crypto": "weak password storage, guessable tokens or a timing-unsafe signature compare",
    "external_call_unhandled": "a network error on an outbound call crashes the handler (hidden check)",
    "env_docs_missing": "a required env var is missing from .env.example or the README",
    "out_of_scope_edit": "a file the user did not ask to change was edited (input data, LICENSE, docs)",
    "money_as_float": "money parsed with float()",
}


# ------------------------------------------------------------------ files
def walk_files(root):
    out = {}
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            p = os.path.join(dp, fn)
            out[os.path.relpath(p, root)] = p
    return out


def is_test(rel):
    b = os.path.basename(rel)
    return rel.startswith("tests" + os.sep) or rel.startswith("tests/") or b.startswith("test_") or b.endswith("_test.py")


def read(p):
    try:
        with open(p, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def source_files(root):
    return dict((r, p) for r, p in walk_files(root).items() if r.endswith(".py") and not is_test(r))


def test_files(root):
    return dict((r, p) for r, p in walk_files(root).items() if r.endswith(".py") and is_test(r)
                and not os.path.basename(r).startswith("hidden_"))


def changed_files(ws, fx):
    import filecmp
    a, b = walk_files(ws), walk_files(fx)
    out = sorted(set(a) ^ set(b))
    for k in set(a) & set(b):
        if not filecmp.cmp(a[k], b[k], shallow=False):
            out.append(k)
    return sorted(set(out))


def apply_tree(root, src, subst=None):
    """Copy the files of src over root. `subst` maps placeholder -> value inside text files."""
    for rel, p in walk_files(src).items():
        dst = os.path.join(root, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        data = open(p, "rb").read()
        if subst:
            for k, v in subst.items():
                data = data.replace(k.encode(), v.encode())
        with open(dst, "wb") as f:
            f.write(data)
        shutil.copymode(p, dst)


# ------------------------------------------------------------------ hidden checks
def copy_for_grading(ws):
    dst = os.path.realpath(tempfile.mkdtemp(prefix=GRADE_PREFIX))
    for name in os.listdir(ws):
        if name in SKIP_DIRS:
            continue
        s, d = os.path.join(ws, name), os.path.join(dst, name)
        if os.path.islink(s):
            continue
        if os.path.isdir(s):
            shutil.copytree(s, d, symlinks=True, ignore=shutil.ignore_patterns(*SKIP_DIRS))
        else:
            shutil.copy2(s, d)
    return dst


def run_checks(ws, hidden_dir, checks, timeout=90):
    """{check_id: (passed, detail)} for every check, each in a fresh process on a copy of ws."""
    out = {}
    if not checks:
        return out
    g = copy_for_grading(ws)
    try:
        apply_tree(g, hidden_dir)
        with open(os.path.join(g, "_abl_runner.py"), "w") as f:
            f.write(RUNNER)
        env = dict(os.environ)
        env.update({"PYTHONDONTWRITEBYTECODE": "1", "HOME": g, "PYTHONIOENCODING": "utf-8"})
        for k in ("SLACK_WEBHOOK_URL", "DISCORD_WEBHOOK_URL", "WEBHOOK_SECRET"):
            env.pop(k, None)
        for c in checks:
            name = "%s.Hidden.test_%s" % (c["module"], c["id"])
            try:
                r = subprocess.run([sys.executable, "_abl_runner.py", name], cwd=g, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, timeout=timeout)
                text = r.stdout.decode("utf-8", "replace")
                ok = r.returncode == 0
            except subprocess.TimeoutExpired:
                ok, text = False, "timeout"
            out[c["id"]] = (ok, "" if ok else _last_error(text))
    finally:
        sb.safe_rmtree(g, GRADE_PREFIX)
    return out


def _last_error(text):
    lines = [ln.strip() for ln in text.strip().split("\n") if ln.strip()]
    for ln in reversed(lines):
        if re.match(r"^(AssertionError|[A-Za-z]+Error|Exception|timeout)", ln):
            return ln[:200]
    return (lines[-1] if lines else "no output")[:200]


def applicable(check, stage):
    """Is this check part of the spec at `stage` (1-based)? A check introduced at stage s applies from s on,
    until the stage given in `until` (exclusive) when the user changed their mind."""
    if check.get("stage", 1) > stage:
        return False
    until = check.get("until")
    return until is None or stage < until


# ------------------------------------------------------------------ static pitfalls
BROAD = ("Exception", "BaseException")


def _broad(handler):
    t = handler.type
    if t is None:
        return True
    names = []
    if isinstance(t, ast.Tuple):
        names = [getattr(e, "id", getattr(e, "attr", "")) for e in t.elts]
    else:
        names = [getattr(t, "id", getattr(t, "attr", ""))]
    return any(n in BROAD for n in names)


def _trivial(stmt):
    if isinstance(stmt, (ast.Pass, ast.Continue, ast.Break)):
        return True
    if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant):
        return True
    if isinstance(stmt, ast.Return):
        v = stmt.value
        return v is None or isinstance(v, ast.Constant) or (isinstance(v, (ast.List, ast.Dict, ast.Tuple, ast.Set)) and not getattr(v, "elts", getattr(v, "keys", [])))
    return False


def silent_exceptions(root):
    hits = []
    for rel, p in source_files(root).items():
        text = read(p)
        try:
            tree = ast.parse(text)
        except (SyntaxError, ValueError):
            continue
        lines = text.split("\n")
        for node in ast.walk(tree):
            if isinstance(node, ast.ExceptHandler) and _broad(node) and all(_trivial(s) for s in node.body):
                end = max(getattr(s, "end_lineno", s.lineno) for s in node.body)
                span = lines[node.lineno - 2 if node.lineno >= 2 else 0:end]
                if any("#" in ln and re.search(r"#.*\b(ignore|ignored|intentional|on purpose|best[- ]effort)\b", ln, re.I) for ln in span):
                    continue
                hits.append("%s:%d" % (rel, node.lineno))
    return hits


def _norm_lines(text):
    out = []
    for i, ln in enumerate(text.split("\n"), 1):
        s = ln.strip()
        if not s or s.startswith("#") or s.startswith(("import ", "from ")) or s in ("pass", "else:", "try:", ")", "]", "}", "return", '"""', "'''"):
            continue
        out.append((i, re.sub(r"\s+", " ", s)))
    return out


def _windows(root, size=8):
    seen = {}
    for rel, p in source_files(root).items():
        nl = _norm_lines(read(p))
        for j in range(0, max(0, len(nl) - size + 1)):
            h = hashlib.sha1("\n".join(x[1] for x in nl[j:j + size]).encode()).hexdigest()
            seen.setdefault(h, []).append((rel, nl[j][0]))
    return seen


def duplicated_blocks(ws, fx, size=8):
    now, before = _windows(ws, size), _windows(fx, size)
    hits = []
    for h, locs in now.items():
        if h in before and len(before[h]) >= len(locs):
            continue
        distinct = []
        for rel, line in locs:
            if not any(r == rel and abs(line - l2) < size for r, l2 in distinct):
                distinct.append((rel, line))
        if len(distinct) >= 2:
            hits.append("%s:%d and %s:%d" % (distinct[0] + distinct[1]))
    return sorted(set(hits))[:5]


STDLIB = frozenset(getattr(sys, "stdlib_module_names", ()) or """abc argparse array ast asyncio base64 binascii bisect builtins
calendar collections contextlib copy csv ctypes dataclasses datetime decimal difflib email enum errno fnmatch fractions
functools getpass glob gzip hashlib heapq hmac html http importlib inspect io ipaddress itertools json logging math
mimetypes operator os pathlib pickle platform pprint queue random re secrets shlex shutil signal smtplib socket sqlite3
ssl statistics string struct subprocess sys tempfile textwrap threading time timeit traceback types typing unicodedata
unittest urllib uuid warnings weakref wsgiref xml zipfile zlib zoneinfo __future__""".split())
MANIFESTS = ("requirements.txt", "requirements-dev.txt", "pyproject.toml", "setup.py", "setup.cfg", "Pipfile", "package.json", "poetry.lock")


def unlisted_deps(ws, fx):
    local = set()
    for name in os.listdir(ws):
        local.add(name[:-3] if name.endswith(".py") else name)
    hits = []
    for rel, p in walk_files(ws).items():
        if not rel.endswith(".py") or os.path.basename(rel).startswith("hidden_"):
            continue
        try:
            tree = ast.parse(read(p))
        except (SyntaxError, ValueError):
            continue
        for node in ast.walk(tree):
            mods = []
            if isinstance(node, ast.Import):
                mods = [a.name.split(".")[0] for a in node.names]
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                mods = [node.module.split(".")[0]]
            for m in mods:
                if m not in STDLIB and m not in local:
                    hits.append("%s imports %s" % (rel, m))
    for rel in walk_files(ws):
        if os.path.basename(rel) in MANIFESTS and not os.path.exists(os.path.join(fx, rel)):
            hits.append("new manifest %s" % rel)
    return sorted(set(hits))[:6]


def count_tests(root):
    names = []
    for rel, p in test_files(root).items():
        for m in re.finditer(r"^[ \t]*def (test_\w+)", read(p), re.M):
            names.append("%s::%s" % (rel, m.group(1)))
    return names


def weakened_tests(ws, fx):
    now = set(count_tests(ws))
    gone = [n for n in count_tests(fx) if n not in now]
    skips = []
    fx_tests = test_files(fx)
    for rel, p in test_files(ws).items():
        new = len(re.findall(r"@unittest\.skip|\.skipTest\(|@pytest\.mark\.skip", read(p)))
        old = len(re.findall(r"@unittest\.skip|\.skipTest\(|@pytest\.mark\.skip", read(fx_tests[rel]))) if rel in fx_tests else 0
        if new > old:
            skips.append("%s adds a skip" % rel)
    return gone + skips


def env_ignored(ws):
    gi = read(os.path.join(ws, ".gitignore"))
    return any(ln.strip() in (".env", ".env*", "*.env", ".env.*", "/.env") for ln in gi.split("\n"))


def secret_hits(ws, secret):
    if not secret:
        return []
    hits = []
    ok_env = env_ignored(ws)
    for rel, p in walk_files(ws).items():
        b = os.path.basename(rel)
        if ok_env and (b == ".env" or (b.startswith(".env.") and b not in (".env.example", ".env.sample", ".env.template"))) and os.path.dirname(rel) == "":
            continue
        try:
            if secret.encode() in open(p, "rb").read():
                hits.append(rel)
        except OSError:
            pass
    return hits


def env_docs(ws, names):
    example = ""
    for n in (".env.example", ".env.sample", ".env.template"):
        example += read(os.path.join(ws, n))
    readme = read(os.path.join(ws, "README.md"))
    return ["%s not in .env.example" % v for v in names if v not in example] + ["%s not in README.md" % v for v in names if v not in readme]


def crypto_problems(ws, modes):
    src = "\n".join(read(p) for p in source_files(ws).values())
    out = []
    if "password" in modes and not re.search(r"pbkdf2_hmac|hashlib\.scrypt|scrypt\(|bcrypt|argon2", src):
        out.append("passwords not stored with a slow salted hash (pbkdf2/scrypt/bcrypt/argon2)")
    if "token" in modes and re.search(r"^\s*(import random|from random import)", src, re.M) and not re.search(r"\bsecrets\.|os\.urandom|uuid\.uuid4|uuid4\(", src):
        out.append("tokens from the random module (guessable)")
    if "compare" in modes and re.search(r"\bhmac\.new\(|\bhmac\.digest\(", src) and "compare_digest" not in src:
        out.append("signature compared with == (not hmac.compare_digest)")
    return out


def float_money(ws, paths):
    hits = []
    for rel, p in source_files(ws).items():
        if any(fnmatch.fnmatch(rel, g) for g in paths) and re.search(r"\bfloat\(", read(p)):
            hits.append(rel)
    return hits


def out_of_scope(ws, fx, frozen):
    return [k for k in changed_files(ws, fx) if any(fnmatch.fnmatch(k, g) for g in frozen)][:6]


def big_files(ws, limit=400):
    return ["%s (%d lines)" % (r, len(read(p).split("\n"))) for r, p in source_files(ws).items() if len(read(p).split("\n")) > limit]


def pitfalls(ws, fx, project, final_checks, secret=None, n_stages=3):
    """{name: (present, detail)} for every pitfall that applies to this project."""
    names = project.get("pitfalls") or []
    out = {}
    hidden_by = {}
    for c in project.get("checks", []):
        if c.get("pitfall"):
            hidden_by.setdefault(c["pitfall"], []).append(c["id"])
    for name in names:
        if name in hidden_by:
            bad = [cid for cid in hidden_by[name] if not final_checks.get(cid, (False, ""))[0]]
            out[name] = (bool(bad), ("failed: %s" % ", ".join(bad)) if bad else "ok")
        elif name == "hardcoded_secret":
            h = secret_hits(ws, secret)
            out[name] = (bool(h), ", ".join(h) or "ok")
        elif name == "no_tests_added":
            added = len(count_tests(ws)) - len(count_tests(fx))
            need = int(project.get("min_new_tests", n_stages))
            out[name] = (added < need, "%d new test functions (need %d)" % (added, need))
        elif name == "tests_weakened":
            h = weakened_tests(ws, fx)
            out[name] = (bool(h), ", ".join(h[:4]) or "ok")
        elif name == "silent_exception":
            h = silent_exceptions(ws)
            out[name] = (bool(h), ", ".join(h[:4]) or "ok")
        elif name == "duplicated_logic":
            h = duplicated_blocks(ws, fx)
            out[name] = (bool(h), "; ".join(h[:3]) or "ok")
        elif name == "big_file":
            h = big_files(ws)
            out[name] = (bool(h), ", ".join(h) or "ok")
        elif name == "unlisted_dependency":
            h = unlisted_deps(ws, fx)
            out[name] = (bool(h), "; ".join(h) or "ok")
        elif name == "diy_crypto":
            h = crypto_problems(ws, project.get("crypto") or [])
            out[name] = (bool(h), "; ".join(h) or "ok")
        elif name == "env_docs_missing":
            h = env_docs(ws, project.get("env_vars") or [])
            out[name] = (bool(h), "; ".join(h[:4]) or "ok")
        elif name == "out_of_scope_edit":
            h = out_of_scope(ws, fx, project.get("frozen") or [])
            out[name] = (bool(h), ", ".join(h) or "ok")
        elif name == "money_as_float":
            h = float_money(ws, project.get("money_paths") or ["*"])
            out[name] = (bool(h), ", ".join(h) or "ok")
        else:
            out[name] = (True, "unknown pitfall check %r" % name)
    return out


def dumps(x):
    return json.dumps(x, sort_keys=True)

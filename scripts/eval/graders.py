"""Programmatic graders. Article rule: "the cheapest grader that fits" - exact
match, a label from a fixed set, JSON that matches, tests that pass - before any
LLM judge (none is used here at all).

grade(spec, ctx) -> (passed: bool, detail: str)
ctx keys: output (final answer text), workspace (temp dir the agent worked in),
fixture (pristine fixture dir, never handed to the agent).
The answer keys live in evals/tasks/*.json, outside every fixture, so the
workspace copy the agent sees never contains them (rule 7).
"""
import filecmp
import os
import re
import subprocess

SKIP_DIRS = (".git", ".claude", "__pycache__")


def _num(s):
    return float(s.replace(",", ""))


def _first_number(text):
    m = re.search(r"-?\d[\d,]*(?:\.\d+)?", text)
    return _num(m.group(0)) if m else None


def resolve_line(fixture, rel, pattern):
    """Line number (1-based) of the first line in fixture/rel containing pattern."""
    with open(os.path.join(fixture, rel)) as f:
        for i, line in enumerate(f, 1):
            if pattern in line:
                return i
    raise ValueError("pattern %r not found in %s" % (pattern, rel))


def _g_contains_all(spec, ctx):
    t = ctx["output"]
    if spec.get("ci", True):
        t = t.lower()
    miss = [v for v in spec["values"] if (v.lower() if spec.get("ci", True) else v) not in t]
    return (not miss, "missing: %s" % miss if miss else "all present")


def _g_contains_any(spec, ctx):
    t = ctx["output"].lower()
    hit = [v for v in spec["values"] if v.lower() in t]
    return (bool(hit), "matched %s" % hit if hit else "none of %s" % spec["values"])


def _g_contains_none(spec, ctx):
    t = ctx["output"].lower()
    hit = [v for v in spec["values"] if v.lower() in t]
    return (not hit, "forbidden present: %s" % hit if hit else "none present")


def _flags(spec):
    return re.I if "i" in spec.get("flags", "") else 0


def _g_regex(spec, ctx):
    ok = re.search(spec["pattern"], ctx["output"], _flags(spec) | re.M) is not None
    return (ok, "regex %s %s" % ("matched" if ok else "did not match", spec["pattern"]))


def _g_regex_none(spec, ctx):
    m = re.search(spec["pattern"], ctx["output"], _flags(spec) | re.M)
    return (m is None, "forbidden regex matched: %s" % spec["pattern"] if m else "regex absent")


def _g_number_equals(spec, ctx):
    n = _first_number(ctx["output"])
    if n is None:
        return (False, "no number in answer")
    ok = abs(n - float(spec["value"])) <= float(spec.get("tol", 0))
    return (ok, "answer number %s, expected %s" % (n, spec["value"]))


def _g_loc(spec, ctx):
    line = resolve_line(ctx["fixture"], spec["file"], spec["pattern"])
    tol = int(spec.get("tol", 0))
    nums = [int(x) for x in re.findall(re.escape(spec["file"]) + r"\s*:\s*(\d+)", ctx["output"])]
    ok = any(abs(n - line) <= tol for n in nums)
    return (ok, "want %s:%d (tol %d), saw lines %s" % (spec["file"], line, tol, nums))


def _g_section_none(spec, ctx):
    """Forbidden values must not appear inside a named section (e.g. FOUND:)."""
    m = re.search(r"(?ms)^[ \t]*" + re.escape(spec["section"]) + r":(.*?)(?=^[ \t]*(?:STRUCTURE|NOT FOUND|NOTED)|\Z)", ctx["output"])
    body = (m.group(1) if m else "").lower()
    hit = [v for v in spec["values"] if v.lower() in body]
    return (not hit, "forbidden in %s: %s" % (spec["section"], hit) if hit else "section clean")


def _g_ordered(spec, ctx):
    pos = 0
    t = ctx["output"]
    for pat in spec["items"]:
        m = re.compile(pat, re.I).search(t, pos)
        if not m:
            return (False, "not found in order: %s" % pat)
        pos = m.end()
    return (True, "all items found in order")


LABEL_RE = re.compile(r"\b(UNVERIFIABLE|VERIFIED|REFUTED)\b")


def parse_labels(text):
    parts = re.split(r"(?m)^[ \t]*(?:\*\*)?(\d+)[.)]", text)
    out = {}
    i = 1
    while i + 1 < len(parts):
        body = parts[i + 1]
        m = LABEL_RE.search(body)
        out[int(parts[i])] = (m.group(1) if m else None, body)
        i += 2
    return out


def _g_labels(spec, ctx):
    got = parse_labels(ctx["output"])
    exp = spec["expected"]
    bad = []
    for idx, want in enumerate(exp, 1):
        lab, body = got.get(idx, (None, ""))
        if lab != want:
            bad.append("claim %d: want %s got %s" % (idx, want, lab))
        elif spec.get("require_evidence", True) and want in ("VERIFIED", "REFUTED"):
            if not (re.search(r"\S+\.\w+:\d+", body) or re.search(r"searched", body, re.I)):
                bad.append("claim %d: %s without file:line evidence" % (idx, want))
    return (not bad, "; ".join(bad) if bad else "%d/%d labels right" % (len(exp), len(exp)))


def _g_marker_json(spec, ctx):
    import json
    p = os.path.join(ctx["workspace"], spec["path"])
    if not os.path.isfile(p):
        return (False, "marker file %s not written" % spec["path"])
    try:
        d = json.load(open(p))
    except Exception:
        return (False, "marker file is not valid JSON")
    bad = ["%s=%r (want %r)" % (k, d.get(k), v) for k, v in spec["expect"].items() if d.get(k) != v]
    return (not bad, "marker wrong: %s" % bad if bad else "marker matches")


def _run_with_overlay(spec, ctx):
    ws = ctx["workspace"]
    saved = {}
    try:
        for rel, content in (spec.get("overlay") or {}).items():
            p = os.path.join(ws, rel)
            saved[p] = open(p).read() if os.path.isfile(p) else None
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as f:
                f.write(content)
        env = dict(os.environ)
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        try:
            r = subprocess.run(spec["cmd"], cwd=ws, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               timeout=int(spec.get("timeout", 60)))
            return r.returncode, r.stdout.decode("utf-8", "replace")
        except subprocess.TimeoutExpired:
            return 124, "timeout"
        except OSError as e:
            return 127, str(e)
    finally:
        for p, old in saved.items():
            if old is None:
                try:
                    os.remove(p)
                except OSError:
                    pass
            else:
                with open(p, "w") as f:
                    f.write(old)


def _g_run(spec, ctx):
    rc, out = _run_with_overlay(spec, ctx)
    want_pass = spec.get("expect", "pass") == "pass"
    ok = (rc == 0) if want_pass else (rc != 0 and rc not in (124, 127))
    detail = "command rc=%d (want %s)" % (rc, "0" if want_pass else "non-zero")
    mt = spec.get("min_tests")
    if ok and mt:
        m = re.search(r"Ran (\d+) test", out)
        n = int(m.group(1)) if m else 0
        if n < int(mt):
            ok, detail = False, "only %d tests ran, need %d" % (n, mt)
    return (ok, detail)


def _files(root):
    res = {}
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            p = os.path.join(dp, fn)
            res[os.path.relpath(p, root)] = p
    return res


def _g_file_unchanged(spec, ctx):
    a = os.path.join(ctx["workspace"], spec["path"])
    b = os.path.join(ctx["fixture"], spec["path"])
    ok = os.path.isfile(a) and filecmp.cmp(a, b, shallow=False)
    return (ok, "%s %s" % (spec["path"], "unchanged" if ok else "was changed"))


def _g_workspace_unchanged(spec, ctx):
    a, b = _files(ctx["workspace"]), _files(ctx["fixture"])
    diff = sorted(set(a) ^ set(b))
    for k in set(a) & set(b):
        if not filecmp.cmp(a[k], b[k], shallow=False):
            diff.append(k)
    return (not diff, "changed files: %s" % sorted(diff)[:5] if diff else "workspace untouched")


def _g_all(spec, ctx):
    details = []
    ok = True
    for c in spec["checks"]:
        p, d = grade(c, ctx)
        ok = ok and p
        details.append(("ok: " if p else "FAIL: ") + d)
    return (ok, " | ".join(details))


GRADERS = {
    "contains_all": _g_contains_all, "contains_any": _g_contains_any, "contains_none": _g_contains_none,
    "regex": _g_regex, "regex_none": _g_regex_none, "number_equals": _g_number_equals, "loc": _g_loc,
    "ordered": _g_ordered, "section_none": _g_section_none, "labels": _g_labels, "marker_json": _g_marker_json, "run": _g_run,
    "file_unchanged": _g_file_unchanged, "workspace_unchanged": _g_workspace_unchanged, "all": _g_all,
}


def grade(spec, ctx):
    fn = GRADERS.get(spec.get("type"))
    if fn is None:
        return (False, "unknown grader type %r" % spec.get("type"))
    try:
        return fn(spec, ctx)
    except Exception as e:  # a broken grader must be visible, never a silent pass
        return (False, "grader error: %s" % e)


def grade_twice(spec, ctx):
    """Rule 6: run the grader twice on identical output; report if verdicts differ."""
    a = grade(spec, ctx)
    b = grade(spec, ctx)
    return a, (a[0] != b[0])

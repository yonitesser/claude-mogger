#!/usr/bin/env bash
# PostToolUse hook — matches: Edit|Write
# Grounding gate: after a JS/TS/Python file is written, mechanically verify
# that the references it makes actually exist:
#   - relative imports/requires (./x, ../y, from .x import ...) resolve on disk
#   - bare package imports appear in the project's declared dependencies
#     (package.json / requirements / pyproject) or are builtins / stdlib
# Unresolved references -> exit 2 with a precise list (fed back to the model).
# Conservative by design: anything ambiguous (tsconfig aliases, workspaces,
# dynamic imports, try/except ImportError, missing manifests) fails open.
# Disable with MOGGER_CHECK_REFERENCES=off. Needs python3; without it, allows.

source "$(dirname "$0")/lib.sh"
[ "${MOGGER_CHECK_REFERENCES:-on}" = "off" ] && exit 0

INPUT=$(cat)
FILE_PATH=$(json_get "$INPUT" '.tool_input.file_path')
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

case "$FILE_PATH" in
  *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.mts|*.cts|*.py) ;;
  *) exit 0 ;;
esac
case "$FILE_PATH" in */node_modules/*|*/site-packages/*|*/.venv/*|*/venv/*) exit 0 ;; esac

command -v python3 >/dev/null 2>&1 && python3 -c '1' >/dev/null 2>&1 || exit 0

read -r -d '' PY <<'PYEOF'
import os, re, sys, json, glob

path = os.path.abspath(sys.argv[1])
try:
    src = open(path, encoding="utf-8", errors="replace").read()
except Exception:
    sys.exit(0)
base = os.path.dirname(path)
issues = []

def ancestors(d):
    out = []
    while True:
        out.append(d)
        p = os.path.dirname(d)
        if p == d:
            break
        d = p
    return out

# ------------------------------------------------------------------ JS / TS
JS_EXTS = [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".json", ".mts", ".cts"]
NODE_BUILTINS = set("""assert async_hooks buffer child_process cluster console constants crypto dgram
diagnostics_channel dns domain events fs http http2 https inspector module net os path perf_hooks
process punycode querystring readline repl stream string_decoder sys timers tls trace_events tty url
util v8 vm wasi worker_threads zlib test sqlite sea electron vscode bun deno""".split())

def scan_js(s):
    """Yield (spec, kind, line, typeonly) for import/export-from/require of string literals,
    skipping comments, templates, regex literals and other strings."""
    res = []
    n = len(s); i = 0; line = 1
    buf = []
    def lastsig():
        for c in reversed(buf[-50:]):
            if not c.isspace():
                return c
        return ""
    def skip_template(i):
        # i just after opening backtick; returns index after closing backtick
        while i < n:
            c = s[i]
            if c == "\\": i += 2; continue
            if c == "`": return i + 1
            if c == "$" and i + 1 < n and s[i+1] == "{":
                i += 2; depth = 1
                while i < n and depth:
                    c = s[i]
                    if c == "{": depth += 1
                    elif c == "}": depth -= 1
                    elif c == "`": i = skip_template(i + 1); continue
                    elif c in "'\"":
                        q = c; i += 1
                        while i < n and s[i] != q and s[i] != "\n":
                            i += 2 if s[i] == "\\" else 1
                    i += 1
                continue
            i += 1
        return i
    while i < n:
        c = s[i]
        if c == "\n":
            line += 1; buf.append(c); i += 1; continue
        if c == "/" and i + 1 < n and s[i+1] == "/":
            while i < n and s[i] != "\n": i += 1
            continue
        if c == "/" and i + 1 < n and s[i+1] == "*":
            j = s.find("*/", i + 2)
            j = n if j < 0 else j + 2
            line += s.count("\n", i, j); i = j; buf.append(" "); continue
        if c == "`":
            j = skip_template(i + 1)
            line += s.count("\n", i, j); i = j; buf.append('"S"'); continue
        if c == "/":
            prev = lastsig()
            t = "".join(buf[-12:]).rstrip()
            if prev == "" or prev in "(,=:[!&|?{};+-*%<>~^" or re.search(r"(^|\W)(return|typeof|case|of|in)$", t):
                j = i + 1; incls = False
                while j < n and s[j] != "\n":
                    if s[j] == "\\": j += 2; continue
                    if s[j] == "[": incls = True
                    elif s[j] == "]": incls = False
                    elif s[j] == "/" and not incls: break
                    j += 1
                i = j + 1; buf.append("/R/"); continue
        if c in "'\"":
            q = c; j = i + 1; ok = False
            while j < n and s[j] != "\n":
                if s[j] == "\\": j += 2; continue
                if s[j] == q: ok = True; break
                j += 1
            if not ok:
                buf.append(c); i += 1; continue
            spec = s[i+1:j]
            t = "".join(buf[-4000:]).rstrip()
            kind = None
            if re.search(r"(^|[^\w$.])from$", t) or re.search(r"(^|[^\w$.])import$", t):
                kind = "import"
            elif re.search(r"(^|[^\w$.])require\s*\($", t):
                m = re.match(r"\s*\)", s[j+1:j+40])
                if m: kind = "require"
            if kind:
                typeonly = False
                if kind == "import":
                    last = max(t.rfind("import"), t.rfind("export"))
                    if last >= 0 and re.match(r"(import|export)\s+type\b", t[last:]):
                        typeonly = True
                res.append((spec, kind, line, typeonly))
            buf.append('"S"'); i = j + 1; continue
        buf.append(c); i += 1
    return res

def resolve_rel(spec):
    spec = re.split(r"[?#]", spec)[0]
    if "*" in spec or "${" in spec:
        return True
    target = os.path.normpath(os.path.join(base, spec))
    ext = os.path.splitext(target)[1]
    if ext and ext not in JS_EXTS and ext not in (".d",):
        return True  # assets (.css, .svg, ...) — not our business
    if os.path.isfile(target): return True
    cands = []
    for e in JS_EXTS:
        cands.append(target + e)
    if ext in (".js", ".jsx", ".mjs", ".cjs"):
        stem = target[:-len(ext)]
        m = {".js": [".ts", ".tsx", ".d.ts"], ".jsx": [".tsx"], ".mjs": [".mts", ".d.mts"], ".cjs": [".cts", ".d.cts"]}[ext]
        cands += [stem + e for e in m]
    if os.path.isdir(target):
        if os.path.isfile(os.path.join(target, "package.json")): return True
        for e in JS_EXTS:
            cands.append(os.path.join(target, "index" + e))
        if not any(os.path.isfile(x) for x in cands):
            return False
    return any(os.path.isfile(x) for x in cands)

def js_project_info():
    """Return (deps_set, skip_bare, manifest_name) or None if no usable package.json."""
    pkgs = []
    skip = False
    for d in ancestors(base):
        if os.path.basename(d) == "node_modules": return None
        pj = os.path.join(d, "package.json")
        if os.path.isfile(pj):
            try:
                pkgs.append((d, json.load(open(pj, encoding="utf-8"))))
            except Exception:
                return None
        for f in ("pnpm-workspace.yaml", "lerna.json", "deno.json", "deno.jsonc", "import_map.json", "bunfig.toml", ".pnp.cjs", ".pnp.js"):
            if os.path.exists(os.path.join(d, f)): skip = True
        for f in ("tsconfig.json", "jsconfig.json") + tuple(os.path.basename(x) for x in glob.glob(os.path.join(d, "tsconfig.*.json"))):
            tp = os.path.join(d, f)
            if os.path.isfile(tp):
                try: txt = open(tp, encoding="utf-8", errors="replace").read()
                except Exception: txt = ""
                if '"baseUrl"' in txt or '"extends"' in txt or '"paths"' in txt: skip = True
    if not pkgs: return None
    deps = set()
    for d, p in pkgs:
        if not isinstance(p, dict): return None
        if "workspaces" in p: skip = True
        for k in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies", "bundledDependencies", "bundleDependencies"):
            v = p.get(k)
            if isinstance(v, dict): deps.update(v.keys())
            elif isinstance(v, list): deps.update(x for x in v if isinstance(x, str))
        if isinstance(p.get("name"), str): deps.add(p["name"])
        for k in ("imports",):
            pass
    return deps, skip

def check_js():
    info = js_project_info()
    for spec, kind, line, typeonly in scan_js(src):
        if not spec or "${" in spec: continue
        if spec.startswith("."):
            if not resolve_rel(spec):
                issues.append("line %d: %s '%s' does not resolve to a file (looked next to %s for the path with extensions %s and /index.*)"
                              % (line, kind, spec, os.path.relpath(base), " ".join(JS_EXTS)))
            continue
        if typeonly or info is None or info[1]: continue
        if spec[0] in "/#~@$" and not spec.startswith("@") : continue
        if re.match(r"^[a-z][a-z0-9+.-]*:", spec): continue  # node:, http:, npm:, virtual:, ...
        if spec.startswith("@/") or spec.startswith("@@") : continue
        if "!" in spec or "?" in spec or "\\" in spec or " " in spec: continue
        parts = spec.split("/")
        if spec.startswith("@"):
            if len(parts) < 2 or not parts[1]: continue
            name = parts[0] + "/" + parts[1]
        else:
            name = parts[0]
        if not re.match(r"^(@[\w.-]+/)?[\w.-]+$", name): continue
        if name in NODE_BUILTINS: continue
        deps = info[0]
        types_name = "@types/" + (name[1:].replace("/", "__") if name.startswith("@") else name)
        if name in deps or types_name in deps: continue
        if any(os.path.isdir(os.path.join(d, "node_modules", name)) for d in ancestors(base)): continue
        issues.append("line %d: %s '%s' but package '%s' is not in package.json (dependencies/devDependencies/peerDependencies), is not a Node builtin, and is not installed in node_modules"
                      % (line, kind, spec, name))

# ------------------------------------------------------------------- Python
PY_ALIASES = {
 "yaml": "pyyaml", "pil": "pillow", "cv2": "opencv", "sklearn": "scikit_learn", "bs4": "beautifulsoup4",
 "dateutil": "python_dateutil", "dotenv": "python_dotenv", "jwt": "pyjwt", "attr": "attrs", "skimage": "scikit_image",
 "serial": "pyserial", "git": "gitpython", "magic": "python_magic", "OpenSSL": "pyopenssl", "google": "google",
 "mx": "egenix", "usb": "pyusb", "zmq": "pyzmq", "psycopg2": "psycopg", "markdown": "markdown", "docx": "python_docx",
 "pptx": "python_pptx", "fitz": "pymupdf", "lxml": "lxml", "ruamel": "ruamel_yaml", "socks": "pysocks", "wx": "wxpython",
 "gi": "pygobject", "jose": "python_jose", "slugify": "python_slugify", "multipart": "python_multipart",
 "flask_cors": "flask_cors", "pkg_resources": "setuptools", "_pytest": "pytest", "pydantic_core": "pydantic",
}

def norm(s): return re.sub(r"[-_.]+", "_", s.lower())

def stdlib_has(name):
    names = getattr(sys, "stdlib_module_names", None)
    if names is not None and name in names: return True
    if name in sys.builtin_module_names: return True
    try:
        import sysconfig
        std = sysconfig.get_paths()["stdlib"]
        if os.path.isfile(os.path.join(std, name + ".py")) or os.path.isdir(os.path.join(std, name)): return True
        if glob.glob(os.path.join(std, "lib-dynload", name + ".*")): return True
    except Exception:
        pass
    return False

def py_project():
    root = None; toks = set(); found = False
    manifests = ["pyproject.toml", "setup.py", "setup.cfg", "Pipfile", "environment.yml", "environment.yaml", "tox.ini", "requirements.txt", "poetry.lock", "uv.lock"]
    for d in ancestors(base):
        files = []
        for m in manifests:
            if os.path.isfile(os.path.join(d, m)): files.append(os.path.join(d, m))
        files += glob.glob(os.path.join(d, "requirements*.txt")) + glob.glob(os.path.join(d, "requirements", "*.txt")) + glob.glob(os.path.join(d, "*-requirements.txt"))
        if files:
            found = True
            if root is None: root = d
            for f in set(files):
                try: txt = open(f, encoding="utf-8", errors="replace").read()
                except Exception: continue
                for t in re.findall(r"[A-Za-z0-9][A-Za-z0-9_.-]*", txt): toks.add(norm(t))
        if os.path.isdir(os.path.join(d, ".git")) and root is None:
            root = d
        if found: break
    if not found: return None
    return root, toks

def dists_for(name):
    try:
        from importlib import metadata
        return [norm(x) for x in metadata.packages_distributions().get(name, [])]
    except Exception:
        return []

def rel_ok(level, module, names):
    d = base
    for _ in range(level - 1): d = os.path.dirname(d)
    if module:
        p = os.path.join(d, *module.split("."))
        return (os.path.isfile(p + ".py") or os.path.isfile(p + ".pyi") or os.path.isdir(p) or bool(glob.glob(p + ".*")))
    if os.path.isfile(os.path.join(d, "__init__.py")): return True
    bad = []
    for nm in names:
        if nm == "*": return True
        p = os.path.join(d, nm)
        if not (os.path.isfile(p + ".py") or os.path.isdir(p) or glob.glob(p + ".*")): bad.append(nm)
    return not bad

def check_py():
    import ast
    try:
        tree = ast.parse(src)
    except Exception:
        return
    proj = py_project()
    def visit(node, in_try):
        for ch in ast.iter_child_nodes(node):
            it = in_try or isinstance(ch, ast.Try) or (hasattr(ast, "TryStar") and isinstance(ch, getattr(ast, "TryStar")))
            if isinstance(ch, ast.ImportFrom) and ch.level > 0:
                names = [a.name for a in ch.names]
                if not in_try and not rel_ok(ch.level, ch.module, names):
                    issues.append("line %d: relative import 'from %s%s import %s' does not resolve to a module or package on disk"
                                  % (ch.lineno, "." * ch.level, ch.module or "", ", ".join(names)))
            elif isinstance(ch, (ast.Import, ast.ImportFrom)) and not in_try and proj is not None:
                mods = [ch.module] if isinstance(ch, ast.ImportFrom) else [a.name for a in ch.names]
                for m in mods:
                    if not m: continue
                    top = m.split(".")[0]
                    if top in ("__future__", "__main__") or stdlib_has(top): continue
                    root, toks = proj
                    n = norm(top)
                    local = False
                    for d in ancestors(base):
                        for dd in (d, os.path.join(d, "src")):
                            if os.path.isfile(os.path.join(dd, top + ".py")) or os.path.isdir(os.path.join(dd, top)) or glob.glob(os.path.join(dd, top + ".*")):
                                local = True
                        if root and d == root: break
                    if local: continue
                    if n in toks: continue
                    al = PY_ALIASES.get(top) or PY_ALIASES.get(top.lower())
                    if al and norm(al) in toks: continue
                    if any(x in toks for x in dists_for(top)): continue
                    if len(n) >= 3 and any(n in t for t in toks): continue
                    issues.append("line %d: imports '%s' but '%s' is not in the declared dependencies (requirements/pyproject/setup), is not stdlib, and is not a local module"
                                  % (ch.lineno, m, top))
            visit(ch, it)
    visit(tree, False)

try:
    if path.endswith(".py"): check_py()
    elif not path.endswith(".d.ts"): check_js()
    else:
        pass
except Exception:
    sys.exit(0)

if issues:
    sys.stderr.write("BLOCKED: unresolved references in %s\n" % os.path.relpath(path))
    for x in issues: sys.stderr.write("  - " + x + "\n")
    sys.stderr.write("Do not guess. Verify each with Grep/Glob/Read (or docs via Context7 for libraries). "
                     "Fix the path/name, or if the dependency is genuinely needed, check STACK.md and add it to the manifest deliberately. "
                     "(Override for a false positive: MOGGER_CHECK_REFERENCES=off.)\n")
    sys.exit(2)
sys.exit(0)
PYEOF

python3 -c "$PY" "$FILE_PATH"
RC=$?
[ "$RC" -eq 2 ] && mogger_event block "blocked unresolved references in ${FILE_PATH##*/}"
exit $RC

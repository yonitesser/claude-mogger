#!/usr/bin/env bash
# dep-audit.sh - dependency health for the project. REPORT-ONLY.
#
# Usage: bash scripts/checks/dep-audit.sh [project-dir]     (default: .)
#
# Output contract (same as security.sh): one line per finding
#   LEVEL|check-id|message      LEVEL = PASS WARN FAIL SKIP
# ALWAYS exits 0, never modifies or installs anything, fails OPEN: when an
# audit tool or the network is missing the result is SKIP with the exact reason.
#
# Runs the ecosystem's own audit tool if it is already installed:
#   npm audit --json | pnpm audit --json | yarn npm audit --json (berry) /
#   yarn audit --json (classic), pip-audit (pinned requirements*.txt only,
#   --no-deps --disable-pip so nothing is installed), cargo audit --json,
#   osv-scanner (for go/ruby/php, or when the native tool is absent).
# Each tool gets MOGGER_AUDIT_TIMEOUT seconds (default 12).
#
# Also WARNs (no network needed) for: manifests without a lockfile, and
# dependencies pinned to "latest" / "*".
#
# Tests: MOGGER_AUDIT_FIXTURE=<file> parses that canned tool JSON (npm, pnpm,
# yarn, pip-audit, cargo-audit or osv-scanner shape) instead of running any
# tool, so no network is needed.
set -u
out() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }
DIR="${1:-.}"
[ -d "$DIR" ] || { out SKIP dep-audit "not a directory: $DIR"; exit 0; }
cd "$DIR" 2>/dev/null || { out SKIP dep-audit "cannot enter $DIR"; exit 0; }
T=$(mktemp -d 2>/dev/null) || { out SKIP dep-audit "mktemp failed"; exit 0; }
trap 'rm -rf "$T"' EXIT
TMO="${MOGGER_AUDIT_TIMEOUT:-12}"

emit_py() {
cat <<'PY'
import sys, json

ORDER = ["critical", "high", "moderate", "low", "unrated"]
def norm(s):
    s = (s or "").lower()
    if s == "medium": s = "moderate"
    return s if s in ORDER else "unrated"

def load(path):
    txt = open(path).read()
    try:
        return json.loads(txt)
    except Exception:
        rows = []
        for l in txt.splitlines():
            l = l.strip()
            if l.startswith("{"):
                try: rows.append(json.loads(l))
                except Exception: pass
        return {"__ndjson__": rows} if rows else None

def main():
    d = load(sys.argv[1])
    if d is None:
        print("ERR|output was not JSON"); return
    found = {}   # package -> severity
    kind = "unknown"
    if isinstance(d, dict) and "__ndjson__" in d:
        kind = "yarn"
        for r in d["__ndjson__"]:
            if r.get("type") == "auditAdvisory":
                a = r.get("data", {}).get("advisory", {})
                found[a.get("module_name", "?")] = norm(a.get("severity"))
            elif "value" in r and isinstance(r.get("children"), dict):
                found[r["value"]] = norm(r["children"].get("Severity"))
    elif isinstance(d, dict) and "error" in d and isinstance(d["error"], dict):
        print("ERR|" + str(d["error"].get("summary") or d["error"].get("code") or "audit error").replace("\n", " ")[:160]); return
    elif isinstance(d, dict) and isinstance(d.get("vulnerabilities"), dict) and "list" not in d["vulnerabilities"]:
        kind = "npm"
        for name, v in d["vulnerabilities"].items():
            found[name] = norm(v.get("severity") if isinstance(v, dict) else None)
    elif isinstance(d, dict) and isinstance(d.get("advisories"), dict):
        kind = "pnpm/npm"
        for a in d["advisories"].values():
            found[a.get("module_name", "?")] = norm(a.get("severity"))
    elif isinstance(d, dict) and isinstance(d.get("vulnerabilities"), dict):
        kind = "cargo"
        for v in d["vulnerabilities"].get("list", []):
            found[(v.get("package") or {}).get("name", "?")] = norm((v.get("advisory") or {}).get("severity"))
    elif isinstance(d, dict) and isinstance(d.get("results"), list):
        kind = "osv"
        for r in d["results"]:
            for p in r.get("packages", []):
                vs = p.get("vulnerabilities", [])
                if not vs: continue
                best = "unrated"
                for v in vs:
                    s = norm((v.get("database_specific") or {}).get("severity"))
                    if ORDER.index(s) < ORDER.index(best): best = s
                found[(p.get("package") or {}).get("name", "?")] = best
    elif (isinstance(d, dict) and isinstance(d.get("dependencies"), list)) or isinstance(d, list):
        kind = "pip-audit"
        for p in (d["dependencies"] if isinstance(d, dict) else d):
            if p.get("vulns"):
                found[p.get("name", "?")] = "unrated"
    else:
        print("ERR|unrecognised audit JSON shape"); return
    counts = dict((k, 0) for k in ORDER)
    for s in found.values(): counts[s] += 1
    print("KIND|" + kind)
    print("COUNT|" + "|".join(str(counts[k]) for k in ORDER))
    top = sorted(found.items(), key=lambda kv: (ORDER.index(kv[1]), kv[0]))[:5]
    for n, s in top: print("TOP|%s|%s" % (n, s))

main()
PY
}
emit_py > "$T/parse.py"

# run_tmo <secs> <outfile> cmd...   -> rc; sets $T/timedout when killed
run_tmo() {
  local secs="$1" of="$2"; shift 2
  rm -f "$T/timedout"
  "$@" > "$of" 2> "$of.err" < /dev/null &
  local pid=$!
  ( sleep "$secs"; : > "$T/timedout"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local wd=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  return $rc
}

# report <id> <label> <jsonfile> <manifest-for-evidence>
report() {
  local id="$1" label="$2" jf="$3" man="$4" res kind cnt c h m l u top="" n s ln lvl tot
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c '1' >/dev/null 2>&1; then
    out SKIP "$id" "python3 is needed to parse $label audit output and is not available"; return; fi
  res=$(python3 "$T/parse.py" "$jf" 2>/dev/null)
  case "$res" in ERR*) out SKIP "$id" "$label audit gave no usable result: ${res#ERR|}"; return;; esac
  kind=$(printf '%s\n' "$res" | grep '^KIND|' | head -1 | cut -d'|' -f2)
  cnt=$(printf '%s\n' "$res" | grep '^COUNT|' | head -1)
  [ -z "$cnt" ] && { out SKIP "$id" "$label audit output could not be parsed"; return; }
  IFS='|' read -r _ c h m l u <<< "$cnt"
  tot=$((c+h+m+l+u))
  if [ "$tot" -eq 0 ]; then out PASS "$id" "$label audit: no known vulnerabilities"; return; fi
  printf '%s\n' "$res" | grep '^TOP|' > "$T/top"
  while IFS='|' read -r _ n s; do
    [ -z "$n" ] && continue
    ln=""
    [ -n "$man" ] && [ -f "$man" ] && ln=$(grep -nF -m1 -e "\"$n\"" "$man" 2>/dev/null | cut -d: -f1)
    top="$top$n($s${ln:+, $man:$ln}); "
  done < "$T/top"
  lvl=WARN; [ $((c+h)) -gt 0 ] && lvl=FAIL
  out "$lvl" "$id" "$label audit ($kind): $tot vulnerable packages - $c critical, $h high, $m moderate, $l low, $u unrated. Top: ${top%; }"
}

pinwarn() { : > "$T/pinned"; out WARN dep-pinned "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
tool_result() {  # tool_result <id> <label> <manifest> <of> <rc> <toolname>
  local id="$1" label="$2" man="$3" of="$4" rc="$5"
  if [ -e "$T/timedout" ]; then out SKIP "$id" "$label audit timed out after ${TMO}s (network slow or blocked)"; return; fi
  if [ ! -s "$of" ]; then
    out SKIP "$id" "$label audit produced no output (exit $rc): $(head -c 160 "$of.err" 2>/dev/null | tr '\n|' '  ')"; return; fi
  report "$id" "$label" "$of" "$man"
}

# ---------- lockfiles + pinned-to-latest (no network) ----------
find . -type d \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv -o -name target -o -name vendor \) -prune \
  -o -type f \( -name package.json -o -name Cargo.toml -o -name go.mod -o -name Pipfile -o -name pyproject.toml \) -print 2>/dev/null | head -20 | sed 's#^\./##' > "$T/manifests"

lockwarn=0; nman=0
while IFS= read -r m; do
  [ -z "$m" ] && continue
  d="${m%/*}"; [ "$d" = "$m" ] && d="."
  case "${m##*/}" in
    package.json)
      grep -qE '"(dependencies|devDependencies)"' "$m" 2>/dev/null || continue
      nman=$((nman+1))
      if [ ! -f "$d/package-lock.json" ] && [ ! -f "$d/yarn.lock" ] && [ ! -f "$d/pnpm-lock.yaml" ] && [ ! -f "$d/npm-shrinkwrap.json" ] && [ ! -f "$d/bun.lockb" ] && [ ! -f "$d/bun.lock" ]; then
        out WARN dep-lockfile "$m:1 has dependencies but no lockfile (package-lock.json/yarn.lock/pnpm-lock.yaml) - installs are not reproducible and cannot be audited"; lockwarn=1; fi
      awk '
        /"(dependencies|devDependencies|peerDependencies|optionalDependencies)"[[:space:]]*:[[:space:]]*[{]/ { on=1; next }
        on && /^[[:space:]]*[}]/ { on=0 }
        on && /:[[:space:]]*"(latest|[*]|x)"/ { print NR ": " $0 }' "$m" 2>/dev/null | head -5 | while IFS= read -r hit; do
          ln="${hit%%:*}"; txt=$(printf '%s' "${hit#*: }" | sed -E 's/^[[:space:]]+//' | tr '|' '/')
          pinwarn "dependency pinned to latest/* ($m:$ln): $txt - any release, including a hijacked one, installs"
        done;;
    Cargo.toml)
      nman=$((nman+1))
      [ -f "$d/Cargo.lock" ] || { out WARN dep-lockfile "$m:1 has no Cargo.lock (fine for a library, not for an app)"; lockwarn=1; }
      grep -nE '^[[:alnum:]_-]+[[:space:]]*=[[:space:]]*"[*]"' "$m" 2>/dev/null | head -3 | while IFS= read -r hit; do
        pinwarn "crate version is * ($m:${hit%%:*}): $(printf '%s' "${hit#*:}" | tr '|' '/')"; done;;
    go.mod)
      nman=$((nman+1))
      [ -f "$d/go.sum" ] || { out WARN dep-lockfile "$m:1 has no go.sum"; lockwarn=1; };;
    Pipfile)
      nman=$((nman+1))
      [ -f "$d/Pipfile.lock" ] || { out WARN dep-lockfile "$m:1 has no Pipfile.lock"; lockwarn=1; }
      grep -nE '=[[:space:]]*"[*]"' "$m" 2>/dev/null | head -3 | while IFS= read -r hit; do
        pinwarn "Pipfile dependency is * ($m:${hit%%:*}): $(printf '%s' "${hit#*:}" | tr '|' '/')"; done;;
    pyproject.toml)
      grep -qE '^\[(tool[.]poetry|project)' "$m" 2>/dev/null || continue
      nman=$((nman+1))
      if [ ! -f "$d/poetry.lock" ] && [ ! -f "$d/uv.lock" ] && [ ! -f "$d/pdm.lock" ] && ! ls "$d"/requirements*.txt >/dev/null 2>&1; then
        out WARN dep-lockfile "$m:1 has no lockfile (poetry.lock/uv.lock/pdm.lock/pinned requirements.txt)"; lockwarn=1; fi;;
  esac
done < "$T/manifests"
[ "$nman" -eq 0 ] && out SKIP dep-lockfile "no package.json/Cargo.toml/go.mod/Pipfile/pyproject.toml found"
[ "$nman" -gt 0 ] && [ "$lockwarn" -eq 0 ] && out PASS dep-lockfile "every manifest has a lockfile"
# dep-pinned PASS: only when a package.json/Cargo/Pipfile was examined and nothing printed above
if [ "$nman" -eq 0 ]; then out SKIP dep-pinned "no manifests to check"
else
  [ -e "$T/pinned" ] || out PASS dep-pinned "no dependency pinned to latest or *"
fi

# ---------- audit ----------
if [ -n "${MOGGER_AUDIT_FIXTURE:-}" ]; then
  if [ -f "$MOGGER_AUDIT_FIXTURE" ]; then
    man=""; [ -f package.json ] && man=package.json
    report dep-audit "fixture" "$MOGGER_AUDIT_FIXTURE" "$man"
  else out SKIP dep-audit "MOGGER_AUDIT_FIXTURE file not found: $MOGGER_AUDIT_FIXTURE"; fi
  exit 0
fi

ran=0
if [ -f package.json ]; then
  ran=1
  if [ -f pnpm-lock.yaml ]; then
    if have pnpm; then run_tmo "$TMO" "$T/npm.json" pnpm audit --json; tool_result dep-audit-npm "pnpm" package.json "$T/npm.json" $?
    else out SKIP dep-audit-npm "pnpm-lock.yaml present but pnpm is not installed"; fi
  elif [ -f yarn.lock ]; then
    if have yarn; then
      if [ -f .yarnrc.yml ]; then run_tmo "$TMO" "$T/npm.json" yarn npm audit --json; else run_tmo "$TMO" "$T/npm.json" yarn audit --json; fi
      tool_result dep-audit-npm "yarn" package.json "$T/npm.json" $?
    else out SKIP dep-audit-npm "yarn.lock present but yarn is not installed"; fi
  elif [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
    if have npm; then run_tmo "$TMO" "$T/npm.json" npm audit --json; tool_result dep-audit-npm "npm" package.json "$T/npm.json" $?
    else out SKIP dep-audit-npm "package-lock.json present but npm is not installed"; fi
  else out SKIP dep-audit-npm "no lockfile, so npm audit has nothing to check (see dep-lockfile)"; fi
fi
REQ=""; for r in requirements.txt requirements/*.txt; do [ -f "$r" ] && { REQ="$r"; break; }; done
if [ -n "$REQ" ]; then
  ran=1
  if have pip-audit; then
    run_tmo "$TMO" "$T/py.json" pip-audit -f json --no-deps --disable-pip -r "$REQ"; tool_result dep-audit-python "pip-audit" "$REQ" "$T/py.json" $?
  else out SKIP dep-audit-python "pip-audit is not installed (never installed automatically; pip install pip-audit to enable)"; fi
fi
if [ -f Cargo.toml ]; then
  ran=1
  if [ ! -f Cargo.lock ]; then out SKIP dep-audit-rust "no Cargo.lock to audit"
  elif have cargo && cargo audit --version >/dev/null 2>&1; then
    run_tmo "$TMO" "$T/rs.json" cargo audit --json; tool_result dep-audit-rust "cargo-audit" Cargo.toml "$T/rs.json" $?
  else out SKIP dep-audit-rust "cargo-audit is not installed (cargo install cargo-audit)"; fi
fi
if [ -f go.mod ] || [ -f Gemfile.lock ] || [ -f composer.lock ] || [ "$ran" -eq 0 ]; then
  if have osv-scanner; then
    run_tmo "$TMO" "$T/osv.json" osv-scanner scan source --format json -r .
    [ -s "$T/osv.json" ] || run_tmo "$TMO" "$T/osv.json" osv-scanner --format json -r .
    tool_result dep-audit-osv "osv-scanner" "" "$T/osv.json" $?
  elif [ "$ran" -eq 0 ]; then out SKIP dep-audit-osv "no supported manifest and osv-scanner is not installed"
  else out SKIP dep-audit-osv "go/ruby/php lockfile present but osv-scanner is not installed"; fi
fi
exit 0

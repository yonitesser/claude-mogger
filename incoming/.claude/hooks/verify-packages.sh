#!/usr/bin/env bash
# PreToolUse — matcher: Bash
# Slopsquatting guard. AI assistants invent plausible package names; attackers
# register them. Before `npm|pnpm|yarn add/install`, `pip install`, `uv add`,
# `uv pip install`, `cargo add`, or `go get` runs, every named package is
# looked up on its real registry (curl, 4s timeout). HTTP 404 => blocked.
#
# Skipped (never verified): flags, local paths, git/http/file URLs, `owner/repo`
# shorthands, -r/-c requirements files, and any command that points at a custom
# index/registry (private packages legitimately 404 on the public one).
# Version specifiers/extras are stripped: requests[socks]>=2 -> requests.
#
# Two more checks on packages that DO exist (both fail open):
#   * OSV (osv.dev, free): a package with a MAL-* advisory is known malware => blocked.
#   * Brand-new package (first published < MOGGER_MIN_PKG_AGE_DAYS, default 7): the
#     human is ASKED, because a name registered last week is how slopsquatting works.
#
# FAILS OPEN on anything but a clean 404: no curl, timeout, DNS failure,
# 403/429/5xx, offline sandbox. A flaky network must never wedge a session.
#
# Env: MOGGER_VERIFY_PACKAGES=off disables. MOGGER_OSV=off skips the malware lookup,
#   MOGGER_MIN_PKG_AGE_DAYS=0 skips the new-package question, MOGGER_OSV_URL for tests. Registry bases (for tests/mirrors):
#   MOGGER_NPM_REGISTRY (https://registry.npmjs.org)
#   MOGGER_PYPI_URL     (https://pypi.org/pypi)
#   MOGGER_CRATES_URL   (https://crates.io/api/v1/crates)
#   MOGGER_GOPROXY      (https://proxy.golang.org)
#   MOGGER_VERIFY_MODE=parse  prints "<eco> <name>" per parsed package, no network (tests).
source "${0%/*}/lib.sh"

[ "${MOGGER_VERIFY_PACKAGES:-on}" = "off" ] && exit 0

INPUT=$(cat)
CMD=$(json_get "$INPUT" '.tool_input.command')
[ -z "$CMD" ] && exit 0
echo "$CMD" | grep -qE '(npm|pnpm|yarn|pip3?|uv|cargo|go)[[:space:]]' || exit 0

NPM="${MOGGER_NPM_REGISTRY:-https://registry.npmjs.org}"
PYPI="${MOGGER_PYPI_URL:-https://pypi.org/pypi}"
CRATES="${MOGGER_CRATES_URL:-https://crates.io/api/v1/crates}"
GOPROXY_URL="${MOGGER_GOPROXY:-https://proxy.golang.org}"
PARSE_ONLY=0; [ "${MOGGER_VERIFY_MODE:-}" = "parse" ] && PARSE_ONLY=1
HAVE_CURL=1; command -v curl >/dev/null 2>&1 || HAVE_CURL=0
[ "$PARSE_ONLY" -eq 0 ] && [ "$HAVE_CURL" -eq 0 ] && exit 0

http_code() {  # prints the HTTP status, "000" on any transport failure
  curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 4 \
    -A "claude-mogger-verify" -- "$1" 2>/dev/null || printf '000'
}

OSV_URL="${MOGGER_OSV_URL:-https://api.osv.dev/v1/query}"
MIN_AGE="${MOGGER_MIN_PKG_AGE_DAYS:-7}"
YOUNG=""

osv_malware() {  # osv_malware <eco> <name> -> blocks on a MAL-* advisory
  [ "${MOGGER_OSV:-on}" = "off" ] && return 0
  local eco="$1" name="$2" oe out id
  case "$eco" in npm) oe=npm ;; pypi) oe=PyPI ;; crates) oe=crates.io ;; go) oe=Go ;; *) return 0 ;; esac
  case "$name" in *[!A-Za-z0-9@/._-]*) return 0 ;; esac
  out=$(curl -s --connect-timeout 3 --max-time 4 -A "claude-mogger-verify" -H 'Content-Type: application/json' \
        -d "{\"package\":{\"name\":\"$name\",\"ecosystem\":\"$oe\"}}" -- "$OSV_URL" 2>/dev/null) || return 0
  id=$(printf '%s' "$out" | grep -oE '"id"[[:space:]]*:[[:space:]]*"MAL-[^"]+"' | head -1)
  if [ -n "$id" ]; then
    mogger_event block "blocked known malware package $name"; echo "BLOCKED: '$name' has a malware advisory on OSV (${id##*:}). Do not install it. Check the correct package name." >&2
    exit 2
  fi
  return 0
}

pkg_age_days() {  # pkg_age_days <eco> <url> -> whole days since first publish, or nothing
  command -v python3 >/dev/null 2>&1 || return 0
  curl -s --connect-timeout 3 --max-time 4 --max-filesize 1000000 -A "claude-mogger-verify" -- "$2" 2>/dev/null \
  | python3 -c '
import sys, json, datetime
eco = sys.argv[1]
try:
    j = json.load(sys.stdin)
    if eco == "npm": t = j["time"]["created"]
    elif eco == "crates": t = j["crate"]["created_at"]
    else:
        ts = [f["upload_time_iso_8601"] for fs in j["releases"].values() for f in fs]
        t = min(ts)
    d = datetime.datetime.fromisoformat(t.replace("Z", "+00:00"))
    if d.tzinfo is None: d = d.replace(tzinfo=datetime.timezone.utc)
    print((datetime.datetime.now(datetime.timezone.utc) - d).days)
except Exception:
    pass
' "$1" 2>/dev/null
}

check() {  # check <ecosystem> <name>
  local eco="$1" name="$2" url reg code p
  if [ "$PARSE_ONLY" -eq 1 ]; then echo "$eco $name"; return 0; fi
  case "$eco" in
    npm)   reg="registry.npmjs.org"; url="$NPM/$(printf '%s' "$name" | sed 's#/#%2F#')" ;;
    pypi)  reg="pypi.org";           url="$PYPI/$name/json" ;;
    crates) reg="crates.io";         url="$CRATES/$name" ;;
    go)
      reg="proxy.golang.org"
      case "$name" in *[[:upper:]]*) return 0 ;; esac   # needs !-escaping; fail open
      case "${name%%/*}" in *.*) ;; *) return 0 ;; esac
      # a package path may live inside a module: walk up until one resolves
      p="$name"
      while :; do
        code=$(http_code "$GOPROXY_URL/$p/@v/list")
        [ "$code" != "404" ] && [ "$code" != "410" ] && return 0
        case "$p" in */*) p="${p%/*}" ;; *) break ;; esac
        case "$p" in */*) ;; *) break ;; esac
      done
      block "$name" "$reg" ;;
  esac
  if [ "$eco" = go ]; then osv_malware go "$name"; return 0; fi
  code=$(http_code "$url")
  [ "$code" = "404" ] && block "$name" "$reg"
  osv_malware "$eco" "$name"
  if [ "$MIN_AGE" -gt 0 ] 2>/dev/null && [ "$code" = "200" ]; then
    age=$(pkg_age_days "$eco" "$url")
    case "$age" in ''|*[!0-9]*) ;; *) [ "$age" -lt "$MIN_AGE" ] && YOUNG="$YOUNG $name (${age}d)" ;; esac
  fi
  return 0
}

finish() {  # ask once about brand-new packages, then allow
  if [ -n "$YOUNG" ]; then
    mogger_event warn "asked about a brand-new package"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"First published less than %s days ago:%s. Brand-new names are how fake packages get in. Approve only if you know this package."}}\n' "$MIN_AGE" "$YOUNG"
  fi
  exit 0
}

block() {
  mogger_event block "blocked unknown package $1"; echo "BLOCKED: package '$1' does not exist on $2 — AI assistants invent package names, attackers register them. Verify the correct name (check the project's docs or an existing lockfile) before installing anything." >&2
  exit 2
}

clean_name() {  # strip quotes, version specifiers, extras
  local n="$1"
  n="${n#\"}"; n="${n%\"}"; n="${n#\'}"; n="${n%\'}"
  n=$(printf '%s' "$n" | sed -E 's/\[[^]]*\]//g; s/[=<>!~;].*$//')
  printf '%s' "$n"
}

skip_token() {  # local paths, URLs, shorthands, archives
  case "$1" in
    ""|.|..|./*|../*|/*|~*|*:*|*.whl|*.tar.gz|*.zip|*.tgz|@) return 0 ;;
  esac
  return 1
}

COUNT=0
# `2>&1` and `&>f` are redirects, not command separators: drop them before splitting on `&`
SEGS=$(printf '%s\n' "$CMD" | sed -E 's/[0-9]*[<>]+&[0-9-]+//g; s/&>>?/>/g; s/(&&|\|\||[;&|])/\
/g')
while IFS= read -r seg; do
  # shellcheck disable=SC2086
  set -- $seg
  ECO=""; SKIPNEXT=0; CUSTOM=0; PKGS=""
  # find the ecosystem + verb
  while [ $# -gt 0 ]; do
    case "$1" in
      npm|pnpm)
        case "${2:-}" in install|i|add|isntall) ECO=npm; shift 2; break ;; esac ;;
      yarn)
        case "${2:-}" in add) ECO=npm; shift 2; break ;; esac ;;
      pip|pip3)
        case "${2:-}" in install) ECO=pypi; shift 2; break ;; esac ;;
      uv)
        case "${2:-}" in
          add) ECO=pypi; shift 2; break ;;
          pip) [ "${3:-}" = install ] && { ECO=pypi; shift 3; break; } ;;
        esac ;;
      cargo)
        case "${2:-}" in add) ECO=crates; shift 2; break ;; esac ;;
      go)
        case "${2:-}" in get) ECO=go; shift 2; break ;; esac ;;
      python|python3)
        if [ "${2:-}" = "-m" ] && [ "${3:-}" = "pip" ] && [ "${4:-}" = "install" ]; then ECO=pypi; shift 4; break; fi ;;
    esac
    shift
  done
  [ -z "$ECO" ] && continue

  for tok in "$@"; do
    if [ "$SKIPNEXT" -eq 1 ]; then SKIPNEXT=0; continue; fi
    case "$tok" in
      --registry|--registry=*|--index-url|--index-url=*|-i|--extra-index-url|--extra-index-url=*|--index|--index=*|--find-links|--git|--path|--git=*|--path=*|--default-index)
        CUSTOM=1
        case "$tok" in *=*) ;; *) SKIPNEXT=1 ;; esac
        continue ;;
      -r|--requirement|-e|--editable|-c|--constraint|-f|--target|-t|--prefix|--python|-p|--package|--features|-F|--rename|--manifest-path|--tag|--branch|--rev|--dev-group|--group|--optional|--workspace)
        SKIPNEXT=1; continue ;;
      \>|\>\>|[0-9]\>|[0-9]\>\>|\<|[0-9]\<) SKIPNEXT=1; continue ;;   # bare redirect operator: next word is a file
      \>*|\<*|[0-9]\>*|[0-9]\<*) continue ;;               # redirect glued to its file
      -*) continue ;;
    esac
    skip_token "$tok" && continue
    n=$(clean_name "$tok")
    case "$ECO" in
      npm)
        case "$n" in
          @*/*) n=$(printf '%s' "$n" | sed -E 's/^(@[^@\/]+\/[^@]+)@.*$/\1/') ;;
          @*) continue ;;
          */*) continue ;;                     # github owner/repo shorthand
          *) n="${n%%@*}" ;;
        esac ;;
      crates) n="${n%%@*}" ;;
      go)
        n="${n%%@*}"
        case "$n" in *...*) continue ;; esac ;;
      pypi) case "$n" in */*) continue ;; esac ;;
    esac
    [ -z "$n" ] && continue
    PKGS="$PKGS $n"
  done
  [ "$CUSTOM" -eq 1 ] && [ "$PARSE_ONLY" -eq 0 ] && continue

  for n in $PKGS; do
    COUNT=$((COUNT + 1))
    [ "$COUNT" -gt 10 ] && finish   # bound total lookups
    check "$ECO" "$n"
  done
done <<EOF2
$SEGS
EOF2
finish

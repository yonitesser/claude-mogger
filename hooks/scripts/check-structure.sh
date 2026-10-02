#!/usr/bin/env bash
# PostToolUse hook — matches: Edit|Write
# Keeps vibe-coded projects from growing one giant file / copy-pasted blocks.
# Checks ONLY the source file that was just written:
#   1. line count > MOGGER_MAX_FILE_LINES (default 800)  -> exit 2 with the
#      count and a concrete split suggestion built from the file's top-level
#      definitions (file:line ranges, JS/TS/Python/Go).
#   2. the edit newly introduced an exact 10+ line block (whitespace-normalised,
#      blank/comment/import lines ignored) that already exists elsewhere in the
#      same file -> exit 2 naming both locations (extract a function instead).
# Never blocks: generated files (name or "DO NOT EDIT" header), lock files,
# minified files, vendored dirs, data/fixture files (fixtures/, testdata/,
# *data.ts, *seed*, *fixture*, snapshots, locales). A write that SHRINKS a file
# that is already over the limit (vs git HEAD) is allowed: that is progress.
# Escape hatches: MOGGER_CHECK_STRUCTURE=off, or raise MOGGER_MAX_FILE_LINES.
# Fails open when jq/python3 (json_get) are unavailable.

source "$(dirname "$0")/lib.sh"
[ "${MOGGER_CHECK_STRUCTURE:-on}" = "off" ] && exit 0

INPUT=$(cat)
FILE_PATH=$(json_get "$INPUT" '.tool_input.file_path')
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

EXT="${FILE_PATH##*.}"
case "$EXT" in
  js|jsx|mjs|cjs|ts|tsx|py|go|rb|java|php|rs|vue|svelte|cs|kt|swift|c|cc|cpp|h) ;;
  *) exit 0 ;;
esac
case "$FILE_PATH" in
  */node_modules/*|*/dist/*|*/build/*|*/vendor/*|*/.git/*|*/venv/*|*/.venv/*|*/site-packages/*|*/.next/*|*/__pycache__/*|*/target/*) exit 0 ;;
  *.min.*|*.bundle.js|*.d.ts|*.generated.*|*_generated.*|*.gen.*|*_pb2.py|*_pb2_grpc.py|*.pb.go|*/generated/*|*/__generated__/*|*.snap|*-lock.*|*.lock) exit 0 ;;
  */fixtures/*|*/__fixtures__/*|*/testdata/*|*/test-data/*|*/__snapshots__/*|*/locales/*|*/i18n/*|*/translations/*|*/data/*) exit 0 ;;
  *data.js|*data.ts|*-data.*|*_data.*|*.data.*|*seed*|*fixture*|*Fixture*) exit 0 ;;
esac

LIMIT="${MOGGER_MAX_FILE_LINES:-800}"
case "$LIMIT" in ''|*[!0-9]*) LIMIT=800 ;; esac

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger-cs) || exit 0
trap 'rm -rf "$TMP"' EXIT

# lines, longest line, generated-header flag in one pass
STATS=$(awk 'FNR<=5 && /DO NOT EDIT|@generated|Code generated|[Aa]uto-?generated|automatically generated|This file is generated/ {g=1}
  {n++; if (length($0)>m) m=length($0)} END {print n+0, m+0, g+0}' "$FILE_PATH" 2>/dev/null)
LINES=${STATS%% *}; REST=${STATS#* }; MAXLEN=${REST%% *}; GEN=${REST#* }
[ -z "$LINES" ] && exit 0
[ "${GEN:-0}" = "1" ] && exit 0
[ "${MAXLEN:-0}" -gt 1000 ] && exit 0   # minified

MSG=""

# ------------------------------------------------------------ 1. file size
cat > "$TMP/split.awk" <<'EOF'
function addn(n, s) { cnt++; st[cnt]=n; nm[cnt]=s }
{ line=$0; name=""
  if (EXT=="ts" || EXT=="tsx" || EXT=="js" || EXT=="jsx" || EXT=="mjs" || EXT=="cjs") {
    if (match(line, /^(export[[:space:]]+)?(default[[:space:]]+)?(async[[:space:]]+)?(function[[:space:]*]+|class[[:space:]]+|const[[:space:]]+|let[[:space:]]+|var[[:space:]]+|interface[[:space:]]+|type[[:space:]]+|enum[[:space:]]+)[[:alnum:]_$]+/)) {
      s=substr(line,RSTART,RLENGTH); sub(/^.*[[:space:]*]/,"",s); name=s }
  } else if (EXT=="py") {
    if (match(line, /^(async[[:space:]]+)?(def|class)[[:space:]]+[[:alnum:]_]+/)) { s=substr(line,RSTART,RLENGTH); sub(/^.*[[:space:]]/,"",s); name=s }
  } else if (EXT=="go") {
    if (line ~ /^func[[:space:]]/) { s=line; sub(/^func[[:space:]]+([(][^)]*[)][[:space:]]*)?/,"",s); if (match(s,/^[[:alnum:]_]+/)) name=substr(s,RSTART,RLENGTH) }
    else if (match(line, /^type[[:space:]]+[[:alnum:]_]+/)) { s=substr(line,RSTART,RLENGTH); sub(/^.*[[:space:]]/,"",s); name=s }
  }
  if (name != "") addn(NR, name) }
END {
  total=NR
  if (cnt < 2) { print "NONE"; exit }
  best=0; bn=""
  for (i=1;i<=cnt;i++) { e=(i<cnt)?st[i+1]-1:total; sz=e-st[i]+1; if (sz>best) { best=sz; bn=nm[i]; bl=st[i] } }
  target=int(LIMIT/2); if (target<150) target=150
  out=0; i=1; first=1
  while (i<=cnt && out<6) {
    cs=(first)?1:st[i]; j=i; names=nm[i]; k=1
    while (j<cnt && (st[j+1]-cs) < target) { j++; if (k<6) names=names ", " nm[j]; k++ }
    ce=(j<cnt)?st[j+1]-1:total
    more=""; if (k>6) more=" +" (k-6) " more"
    if (first) printf "  keep in %s: lines %d-%d (%s%s)\n", FILE, cs, ce, names, more
    else { mod=nm[i]; printf "  move to a new module (e.g. %s_%s.%s): lines %d-%d (%s%s)\n", STEM, mod, EXT, cs, ce, names, more }
    first=0; out++; i=j+1
  }
  if (i<=cnt) printf "  ... plus %d more top-level definitions\n", cnt-i+1
  if (best > target) printf "  largest definition: %s at line %d is %d lines: break it into smaller functions first\n", bn, bl, best
}
EOF

if [ "$LINES" -gt "$LIMIT" ]; then
  ALLOW=0
  DIR=$(dirname "$FILE_PATH"); BASE=$(basename "$FILE_PATH")
  OLDN=$( (cd "$DIR" 2>/dev/null && git show "HEAD:./$BASE" 2>/dev/null) | wc -l | tr -d ' ')
  if [ "${OLDN:-0}" -gt 0 ] && [ "$LINES" -lt "$OLDN" ]; then ALLOW=1; fi
  if [ "$ALLOW" -eq 0 ]; then
    STEM="${BASE%.*}"
    SUG=$(awk -v EXT="$EXT" -v LIMIT="$LIMIT" -v FILE="$BASE" -v STEM="$STEM" -f "$TMP/split.awk" "$FILE_PATH" 2>/dev/null)
    MSG="BLOCKED: '$FILE_PATH' has $LINES lines (limit: $LIMIT). One giant file is hard to read, review and change safely; split it by responsibility."
    if [ -z "$SUG" ] || [ "$SUG" = "NONE" ]; then
      MSG="$MSG
No top-level definitions found to split on; extract cohesive parts (data, helpers, handlers) into separate modules."
    else
      MSG="$MSG
Suggested split by top-level definitions:
$SUG"
    fi
    MSG="$MSG
(Override: MOGGER_MAX_FILE_LINES=<n> or MOGGER_CHECK_STRUCTURE=off.)"
  fi
fi

# ------------------------------------------------------------ 2. new exact duplicate block
cat > "$TMP/dup10.awk" <<'EOF'
function norm(s) { gsub(/^[[:space:]]+/,"",s); gsub(/[[:space:]]+$/,"",s); gsub(/[[:space:]]+/," ",s); return s }
function noise(s) { return (s == "" || s ~ /^(import|from|using|package|#include|require|use)[[:space:]]/ || s ~ /^(\/\/|#|\*|\/\*)/) }
function key(arr, i,  k, j) { k=arr[i]; for (j=1;j<N;j++) k=k SUBSEP arr[i+j]; return k }
function subst(arr, i,  t, j, d, a, b) {
  t=0; d=0
  for (j=0;j<N;j++) t+=length(arr[i+j])
  if (t < 120) return 0
  for (a=i;a<i+N;a++) { for (b=i;b<a;b++) if (arr[a]==arr[b]) break; if (b==a) d++ }
  return (d>=5)
}
FILENAME==CURF { s=norm($0); if (!noise(s)) { cn++; cl[cn]=s; cln[cn]=FNR } next }
FILENAME==NEWF { s=norm($0); if (!noise(s)) { nn++; nl[nn]=s } next }
FILENAME==OLDF { s=norm($0); if (!noise(s)) { on++; ol[on]=s } next }
END {
  for (i=1;i<=cn-N+1;i++) { k=key(cl,i); cnt[k]++; if (cnt[k]==1) p1[k]=cln[i]; else if (cnt[k]==2) p2[k]=cln[i] }
  for (i=1;i<=on-N+1;i++) { k=key(ol,i); oc[k]++ }
  for (i=1;i<=nn-N+1;i++) { k=key(nl,i); nc[k]++ }
  run=0
  for (i=1;i<=nn-N+1;i++) {
    k=key(nl,i)
    if ((k in cnt) && cnt[k]>=2 && nc[k]>oc[k] && subst(nl,i)) {
      if (run==0) { a=p1[k]; b=p2[k] }
      run++
    } else if (run>0) break
  }
  if (run>0) printf "%d %d %d\n", a, b, run+N-1
}
EOF

# New text: Edit -> new_string (old_string as baseline); Write -> whole file (git HEAD as baseline)
TOOL=$(json_get "$INPUT" '.tool_name')
NEWS=$(json_get "$INPUT" '.tool_input.new_string')
: > "$TMP/new"; : > "$TMP/old"
if [ -n "$NEWS" ]; then
  printf '%s\n' "$NEWS" > "$TMP/new"
  OLDS=$(json_get "$INPUT" '.tool_input.old_string')
  [ -n "$OLDS" ] && printf '%s\n' "$OLDS" > "$TMP/old"
elif [ "$TOOL" = "Write" ] || [ -n "$(json_get "$INPUT" '.tool_input.content')" ]; then
  cp "$FILE_PATH" "$TMP/new"
  DIR=$(dirname "$FILE_PATH"); BASE=$(basename "$FILE_PATH")
  (cd "$DIR" 2>/dev/null && git show "HEAD:./$BASE" 2>/dev/null) > "$TMP/old" 2>/dev/null
fi
if [ -s "$TMP/new" ]; then
  D=$(awk -v N=10 -v CURF="$FILE_PATH" -v NEWF="$TMP/new" -v OLDF="$TMP/old" -f "$TMP/dup10.awk" "$FILE_PATH" "$TMP/new" "$TMP/old" 2>/dev/null)
  if [ -n "$D" ]; then
    set -- $D
    DMSG="COPY-PASTE: $FILE_PATH now contains a $3-line block (whitespace-normalised) at line $1 that is repeated at line $2. Extract it into one function/helper and call it from both places instead of duplicating."
    if [ -n "$MSG" ]; then MSG="$MSG
$DMSG"; else MSG="$DMSG"; fi
  fi
fi

if [ -n "$MSG" ]; then
  mogger_event block "blocked a big or copied code block in ${FILE_PATH##*/}"
  printf '%s\n' "$MSG" >&2
  exit 2
fi
exit 0

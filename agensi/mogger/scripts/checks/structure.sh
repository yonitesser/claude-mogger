#!/usr/bin/env bash
# structure.sh — code-structure report. REPORT-ONLY: never modifies the project.
#
# Usage (from anywhere):  bash scripts/checks/structure.sh [project-dir]
# Output: one line per finding:  LEVEL|check-id|message   (PASS WARN FAIL SKIP)
# Always exits 0. Every message carries file:line evidence. Anything that is a
# guess is labelled "(heuristic)".
#
# Check ids: struct-file-size, struct-func-size, struct-duplicates,
#            struct-nesting, struct-flat-folder, struct-separation
#
# Skips node_modules/.git/dist/build/venv/vendor, generated files (name or
# "DO NOT EDIT" header), minified files (line > 1000 chars). Tests are excluded
# from function-size / duplicate / nesting checks (not from file-size).
set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "SKIP|struct-file-size|cannot cd into $ROOT"; exit 0; }
CAP="${MOGGER_CHECK_CAP:-12}"
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger-structure) || exit 0
trap 'rm -rf "$TMP"' EXIT
FIND="$TMP/findings"; : > "$FIND"
TAB=$(printf '\t')

group() {  # group <id> <pass message>: print capped findings for id, else PASS
  awk -F'|' -v id="$1" -v pm="$2" -v cap="$CAP" '
    $2==id { n++; if (n<=cap) print; else lv=$1 }
    END { if (n==0) print "PASS|" id "|" pm; else if (n>cap) print (lv==""?"WARN":lv) "|" id "|... and " (n-cap) " more finding(s) not shown" }' "$FIND"
}
skip_all() {
  local i
  for i in struct-file-size struct-func-size struct-duplicates struct-nesting struct-flat-folder struct-separation; do
    echo "SKIP|$i|$1"
  done
}

is_generated_name() {
  case "$1" in
    *.min.js|*.min.mjs|*.bundle.js|*.d.ts|*.generated.*|*_generated.*|*.gen.*|*_pb2.py|*_pb2_grpc.py|*.pb.go|*/generated/*|*/__generated__/*|generated/*|*/migrations/*|migrations/*|*.snap|*-lock.*) return 0 ;;
  esac
  return 1
}
is_test_path() {
  case "$1" in
    *.test.*|*.spec.*|*/__tests__/*|__tests__/*|*/tests/*|tests/*|*/test/*|test/*|*/test_*|test_*|*_test.go|*_test.py|*/conftest.py|*/fixtures/*|fixtures/*|*/e2e/*|*/mocks/*|*/__mocks__/*) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------- file list
find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv \
  -o -name vendor -o -name __pycache__ -o -name .next -o -name .nuxt -o -name target -o -name coverage \
  -o -name .tox -o -name site-packages -o -name .claude -o -name .cache -o -name .turbo -o -name .svelte-kit \
  -o -name bower_components \) -prune -o -type f \( -name '*.js' -o -name '*.jsx' -o -name '*.mjs' \
  -o -name '*.cjs' -o -name '*.ts' -o -name '*.tsx' -o -name '*.py' -o -name '*.go' -o -name '*.rb' \
  -o -name '*.java' -o -name '*.php' -o -name '*.rs' -o -name '*.vue' -o -name '*.svelte' \) -print 2>/dev/null \
  | sed 's|^\./||' > "$TMP/raw0.list"
: > "$TMP/raw.list"
while IFS= read -r f; do
  is_generated_name "$f" || printf '%s\n' "$f" >> "$TMP/raw.list"
done < "$TMP/raw0.list"

if [ ! -s "$TMP/raw.list" ]; then skip_all "no source files found"; exit 0; fi

cat > "$TMP/stats.awk" <<'EOF'
function flush() { if (cf != "") printf "%d\t%d\t%d\t%s\n", n, mx, gen, cf }
FNR==1 { flush(); cf=FILENAME; n=0; mx=0; gen=0 }
{ n++; l=length($0); if (l>mx) mx=l
  if (FNR<=5 && $0 ~ /DO NOT EDIT|@generated|Code generated|[Aa]uto-?generated|automatically generated|This file is generated/) gen=1 }
END { flush() }
EOF
tr '\n' '\0' < "$TMP/raw.list" | xargs -0 awk -f "$TMP/stats.awk" > "$TMP/stats" 2>/dev/null
awk -F'\t' '$3==0 && $2<=1000 {print $4}' "$TMP/stats" > "$TMP/all.list"
: > "$TMP/src.list"
while IFS= read -r f; do
  is_test_path "$f" || printf '%s\n' "$f" >> "$TMP/src.list"
done < "$TMP/all.list"
tr '\n' '\0' < "$TMP/src.list" > "$TMP/src.z"

# ---------------------------------------------------------------- file size
sort -t "$TAB" -k1,1nr "$TMP/stats" | awk -F'\t' '$3==0 && $2<=1000 && $1>500 {
  lvl = ($1>1000) ? "FAIL" : "WARN"
  printf "%s|struct-file-size|%s:1 has %d lines (WARN over 500, FAIL over 1000): split by responsibility\n", lvl, $4, $1 }' >> "$FIND"

if [ -s "$TMP/src.list" ]; then
# ---------------------------------------------------------------- function size
cat > "$TMP/funcs.awk" <<'EOF'
function isc(s) { return (s ~ /^[[:space:]]*(\/\/|#|\*|\/\*)/) }
function ind(s,  i, c, w) { w=0; for (i=1;i<=length(s);i++) { c=substr(s,i,1); if (c==" ") w++; else if (c=="\t") w+=4; else break } return w }
function rec(nm, st, en,  n) { n=en-st+1; if (n>LIM) printf "WARN|struct-func-size|%s:%d: %s is %d lines long (heuristic, limit ~%d): split into smaller functions\n", cf, st, nm, n, LIM }
function flushfile() { while (pk>0) { rec(pn[pk], ps[pk], lastnb); pk-- } d=0; sk=0 }
FNR==1 { if (NR>1) flushfile(); cf=FILENAME; ext=cf; sub(/.*[.]/,"",ext); lastnb=0; d=0; sk=0; pk=0 }
ext=="py" {
  if ($0 ~ /^[[:space:]]*$/) next
  if (isc($0)) next
  if ($0 ~ /^[[:space:]]*[])}]/) { lastnb=FNR; next }
  w=ind($0)
  while (pk>0 && w<=pi[pk]) { rec(pn[pk], ps[pk], lastnb); pk-- }
  if (match($0, /^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+[[:alnum:]_]+/)) {
    s=substr($0,RSTART,RLENGTH); sub(/^.*[[:space:]]/,"",s); pk++; pi[pk]=w; ps[pk]=FNR; pn[pk]=s
  }
  lastnb=FNR
  next
}
ext=="js" || ext=="jsx" || ext=="mjs" || ext=="cjs" || ext=="ts" || ext=="tsx" || ext=="go" || ext=="java" || ext=="php" || ext=="rs" || ext=="vue" || ext=="svelte" {
  if ($0 ~ /^[[:space:]]*$/) next
  t=$0
  if (isc(t)) next
  gsub(/"[^"]*"/,"",t); gsub(/'[^']*'/,"",t); gsub(/`[^`]*`/,"",t); sub(/\/\/.*$/,"",t)
  isfn=0; nm="anonymous"
  if (ext=="go") {
    if (t ~ /^func[[:space:]]/) { isfn=1; s=t; sub(/^func[[:space:]]+([(][^)]*[)][[:space:]]*)?/,"",s); if (match(s,/^[[:alnum:]_]+/)) nm=substr(s,RSTART,RLENGTH) }
  } else {
    if (t ~ /(^|[^[:alnum:]_$])function[[:space:]*(]/) {
      isfn=1
      if (match(t,/function[[:space:]*]+[[:alnum:]_$]+/)) { s=substr(t,RSTART,RLENGTH); sub(/^function[[:space:]*]+/,"",s); nm=s }
    } else if (t ~ /=>[[:space:]]*[{][[:space:]]*$/) {
      isfn=1
      if (match(t,/(const|let|var)[[:space:]]+[[:alnum:]_$]+/)) { s=substr(t,RSTART,RLENGTH); sub(/^[[:alnum:]]+[[:space:]]+/,"",s); nm=s }
    } else if (t ~ /^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(async[[:space:]]+)?((public|private|protected|static|get|set)[[:space:]]+)*[[:alnum:]_$]+[[:space:]]*[(].*[)][^;{]*[{][[:space:]]*$/) {
      if (match(t,/[[:alnum:]_$]+[[:space:]]*[(]/)) {
        s=substr(t,RSTART,RLENGTH); sub(/[[:space:]]*[(]$/,"",s)
        if (s !~ /^(if|for|while|switch|catch|return|else|with|do)$/) { isfn=1; nm=s }
      }
    }
  }
  o=t; no=gsub(/[{]/,"",o); c=t; nc=gsub(/[}]/,"",c)
  if (isfn) { sk++; sb[sk]=d; ss[sk]=FNR; sn[sk]=nm; sseen[sk]=0 }
  d += no-nc; if (d<0) d=0
  if (no>0) for (j=1;j<=sk;j++) sseen[j]=1
  while (sk>0 && sseen[sk] && d<=sb[sk]) { rec(sn[sk], ss[sk], FNR); sk--; }
}
END { flushfile() }
EOF
xargs -0 awk -v LIM=80 -f "$TMP/funcs.awk" < "$TMP/src.z" >> "$FIND" 2>/dev/null

# ---------------------------------------------------------------- duplicates
cat > "$TMP/dup.awk" <<'EOF'
# Hash sliding windows of N normalised non-blank lines. Lines are interned to
# small integer ids first, so each window key is short. POSIX awk only.
function norm(s) { gsub(/^[[:space:]]+/,"",s); gsub(/[[:space:]]+$/,"",s); gsub(/[[:space:]]+/," ",s); return s }
function noise(s) { return (s == "" || s ~ /^(import|from|using|package|#include|require|use)[[:space:]]/ || s ~ /^(\/\/|#|\*|\/\*)/) }
function closerun() {
  if (rl > 0) { printf "%d|%s:%d|%s:%d\n", rl+N-1, fname[rf], rl0, curfile, rl1 }
  rl=0
}
function distinct4(i,  a, b, c) {
  c=0
  for (a=i;a<i+N;a++) { for (b=i;b<a;b++) if (lid[a]==lid[b]) break; if (b==a) c++ }
  return (c>=4)
}
function scan(  i, j, k, s, a, n2) {
  if (cn < N) return
  pl[0]=0
  for (i=1;i<=cn;i++) pl[i]=pl[i-1]+lch[i]
  rl=0; prevmatch=0
  for (i=1;i<=cn-N+1;i++) {
    if (pl[i+N-1]-pl[i-1] < 160) { closerun(); prevmatch=0; continue }
    k=lid[i]; for (j=1;j<N;j++) k=k "," lid[i+j]
    if (k in first) {
      n2=split(first[k],a,":")
      f0=a[1]+0; i0=a[2]+0; l0=a[3]+0
      if ((f0==fi && i < i0+N) || !distinct4(i)) { closerun(); prevmatch=0; continue }
      if (prevmatch && rf==f0 && pi0+1==i0 && rl>0) { rl++ }
      else { closerun(); rl=1; rf=f0; rl0=l0; rl1=lno[i] }
      prevmatch=1; pi0=i0
    } else {
      closerun(); prevmatch=0
      if (nwin < MAXWIN) { nwin++; first[k]= fi ":" i ":" lno[i] } else capped=1
    }
  }
  closerun()
}
FNR==1 { if (NR>1) scan(); fi++; fname[fi]=FILENAME; curfile=FILENAME; cn=0 }
{ s=norm($0); if (noise(s)) next
  if (!(s in ids)) ids[s]=++nid
  cn++; lid[cn]=ids[s]; lno[cn]=FNR; lch[cn]=length(s) }
END { scan(); if (capped) print "CAPPED|1" }
EOF
xargs -0 awk -v N=8 -v MAXWIN=600000 -f "$TMP/dup.awk" < "$TMP/src.z" > "$TMP/dup.out" 2>/dev/null
if grep -q '^CAPPED' "$TMP/dup.out" 2>/dev/null; then CAPNOTE=" (very large repo: analysed only the first windows, heuristic)"; else CAPNOTE=""; fi
grep -v '^CAPPED' "$TMP/dup.out" > "$TMP/dup.blocks" 2>/dev/null
NDUP=$(wc -l < "$TMP/dup.blocks" | tr -d ' ')
if [ "${NDUP:-0}" -gt 0 ]; then
  echo "WARN|struct-duplicates|$NDUP duplicated block(s) of 8+ normalised lines (copy-paste); top blocks below${CAPNOTE}" >> "$FIND"
  sort -t'|' -k1,1nr "$TMP/dup.blocks" | head -5 | awk -F'|' '{
    printf "WARN|struct-duplicates|%s duplicates %s (%d lines): extract into a shared function/module\n", $3, $2, $1 }' >> "$FIND"
fi

# ---------------------------------------------------------------- nesting
cat > "$TMP/nest.awk" <<'EOF'
function ind(s,  i, c, w) { w=0; for (i=1;i<=length(s);i++) { c=substr(s,i,1); if (c==" ") w++; else if (c=="\t") w+=4; else break } return w }
function flush() { if (cf != "" && best >= thr) printf "WARN|struct-nesting|%s:%d: nesting depth %d (heuristic; >= %d levels)\n", cf, bl, best, thr }
FNR==1 { flush(); cf=FILENAME; ext=cf; sub(/.*[.]/,"",ext); unit=0; best=0; bl=0
  thr=7; if (ext=="tsx" || ext=="jsx" || ext=="vue" || ext=="svelte") thr=10 }
{ if ($0 ~ /^[[:space:]]*$/) next
  if ($0 ~ /^[[:space:]]*(\/\/|#|\*|\/\*|[])}.+&|?:<>\/*'"`-])/) next
  w=ind($0)
  if (w==0) next
  if (unit==0) unit=(w<=2)?2:4
  lv=int(w/unit)
  if (lv>best) { best=lv; bl=FNR } }
END { flush() }
EOF
xargs -0 awk -f "$TMP/nest.awk" < "$TMP/src.z" >> "$FIND" 2>/dev/null

# ---------------------------------------------------------------- flat folders
awk '{ n=split($0,a,"/"); d=(n==1)?".":substr($0,1,length($0)-length(a[n])-1); c[d]++ }
  END { for (d in c) if (c[d]>40) printf "WARN|struct-flat-folder|%s/: %d source files in one flat folder (limit 40): group by feature/module\n", d, c[d] }' "$TMP/src.list" >> "$FIND"

# ---------------------------------------------------------------- separation
NROOT=$(grep -c -v '/' "$TMP/src.list"); NNEST=$(grep -c '/' "$TMP/src.list")
if [ "${NNEST:-0}" -eq 0 ] && [ "${NROOT:-0}" -ge 5 ]; then
  EX=$(head -3 "$TMP/src.list" | tr '\n' ' ')
  echo "WARN|struct-separation|all $NROOT source files live in the repo root (e.g. $EX) with no folders (heuristic): group into src/ modules by responsibility" >> "$FIND"
fi
fi  # src.list non-empty

# ---------------------------------------------------------------- report
if [ ! -s "$TMP/src.list" ]; then
  # only tests/generated files existed
  group struct-file-size "no source file over 500 lines"
  for i in struct-func-size struct-duplicates struct-nesting struct-flat-folder struct-separation; do
    echo "SKIP|$i|no non-test, non-generated source files"
  done
  exit 0
fi
group struct-file-size "no source file over 500 lines"
group struct-func-size "no function over ~80 lines found (heuristic, JS/TS/Python/Go)"
group struct-duplicates "no duplicated block of 8+ lines found"
group struct-nesting "no deeply nested code found (heuristic)"
group struct-flat-folder "no folder holds more than 40 source files"
group struct-separation "source is spread across folders (heuristic)"
exit 0

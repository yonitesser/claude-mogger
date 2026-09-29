#!/usr/bin/env bash
# resilience.sh — error handling / logging / scale-risk report. REPORT-ONLY.
#
# Usage:  bash scripts/checks/resilience.sh [project-dir]
# Output: one line per finding:  LEVEL|check-id|message   (PASS WARN FAIL SKIP)
# Always exits 0; never modifies the project. Findings cite file:line.
# Everything marked "(heuristic)" is a pattern match, not proof: read the line.
#
# Check ids: res-empty-catch, res-timeout, res-async-handler, res-logging,
#            res-error-tracking, res-health, res-unbounded, res-n-plus-1
#
# Skips node_modules/.git/dist/build/venv/vendor, minified/generated files and
# test files. Languages: JS/TS, Python, Go (patterns differ per language).
set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "SKIP|res-empty-catch|cannot cd into $ROOT"; exit 0; }
CAP="${MOGGER_CHECK_CAP:-12}"
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger-resilience) || exit 0
trap 'rm -rf "$TMP"' EXIT
FIND="$TMP/findings"; : > "$FIND"
IDS="res-empty-catch res-timeout res-async-handler res-logging res-error-tracking res-health res-unbounded res-n-plus-1"

group() {
  awk -F'|' -v id="$1" -v pm="$2" -v cap="$CAP" '
    $2==id { n++; if (n<=cap) print; else lv=$1 }
    END { if (n==0) print "PASS|" id "|" pm; else if (n>cap) print (lv==""?"WARN":lv) "|" id "|... and " (n-cap) " more finding(s) not shown" }' "$FIND"
}

is_skip_name() {
  case "$1" in
    *.min.js|*.min.mjs|*.bundle.js|*.d.ts|*.generated.*|*_generated.*|*.gen.*|*_pb2.py|*_pb2_grpc.py|*.pb.go|*/generated/*|*/__generated__/*|generated/*|*/migrations/*|migrations/*|*.snap|*-lock.*) return 0 ;;
    *.test.*|*.spec.*|*/__tests__/*|__tests__/*|*/tests/*|tests/*|*/test/*|test/*|*/test_*|test_*|*_test.go|*_test.py|*/conftest.py|*/fixtures/*|fixtures/*|*/mocks/*|*/__mocks__/*|*/e2e/*) return 0 ;;
  esac
  return 1
}

find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv \
  -o -name vendor -o -name __pycache__ -o -name .next -o -name .nuxt -o -name target -o -name coverage \
  -o -name .tox -o -name site-packages -o -name .claude -o -name .cache -o -name .turbo -o -name .svelte-kit \
  -o -name bower_components \) -prune -o -type f \( -name '*.js' -o -name '*.jsx' -o -name '*.mjs' \
  -o -name '*.cjs' -o -name '*.ts' -o -name '*.tsx' -o -name '*.py' -o -name '*.go' \) -print 2>/dev/null \
  | sed 's|^\./||' > "$TMP/raw.list"
: > "$TMP/src.list"
while IFS= read -r f; do
  is_skip_name "$f" || printf '%s\n' "$f" >> "$TMP/src.list"
done < "$TMP/raw.list"

if [ ! -s "$TMP/src.list" ]; then
  for i in $IDS; do echo "SKIP|$i|no JS/TS/Python/Go source files found"; done
  exit 0
fi
tr '\n' '\0' < "$TMP/src.list" > "$TMP/src.z"
runawk() { xargs -0 awk "$@" < "$TMP/src.z" >> "$FIND" 2>/dev/null; }   # runawk -v ... -f prog

# ------------------------------------------------------------ swallowed errors
cat > "$TMP/swallow.awk" <<'EOF'
function isc(s) { return (s ~ /^[[:space:]]*(\/\/|#|\*|\/\*)/) }
function rep(ln, what) { printf "WARN|res-empty-catch|%s:%d: %s (errors vanish silently; log it or add a comment '// ignore: <reason>')\n", FILENAME, ln, what }
function pyproc(line) {
  if (pend) {
    if (line ~ /^[[:space:]]*$/) return
    if (line ~ /^[[:space:]]*#/) { if (line ~ /ignore:/) pdoc=1; return }
    if (line ~ /^[[:space:]]*(pass|[.][.][.])[[:space:]]*(#.*)?$/) { if (!pdoc && line !~ /ignore:/) rep(pln, "except block only does pass") }
    pend=0
  }
  if (line ~ /^[[:space:]]*except[^:]*:[[:space:]]*(pass|[.][.][.])[[:space:]]*(#.*)?$/) {
    if (line !~ /ignore:/ && prev !~ /ignore:/) rep(FNR, "except: pass swallows the error")
  } else if (line ~ /^[[:space:]]*except[^:]*:[[:space:]]*(#.*)?$/) {
    pend=1; pln=FNR; pdoc=(line ~ /ignore:/ || prev ~ /ignore:/)
  }
}
function jsproc(line) {
  if (line ~ /^[[:space:]]*$/) return
  if (isc(line)) { jpend=0; return }
  if (jpend) { if (line ~ /^[[:space:]]*[}]/) rep(jln, "empty catch block"); jpend=0 }
  if (line ~ /catch[[:space:]]*([(][^)]*[)])?[[:space:]]*[{][[:space:]]*[}]/) {
    if (line !~ /ignore:/ && prev !~ /ignore:/) rep(FNR, "empty catch block")
  } else if (line ~ /catch[[:space:]]*([(][^)]*[)])?[[:space:]]*[{][[:space:]]*$/) {
    if (line !~ /ignore:/ && prev !~ /ignore:/) { jpend=1; jln=FNR }
  }
  if (line ~ /[.]catch[(][[:space:]]*(async[[:space:]]*)?([(][^)]*[)]|[[:alnum:]_$]+)[[:space:]]*=>[[:space:]]*[{][[:space:]]*[}][[:space:]]*[)]/ ||
      line ~ /[.]catch[(][[:space:]]*function[[:space:]]*[(][^)]*[)][[:space:]]*[{][[:space:]]*[}][[:space:]]*[)]/) {
    if (line !~ /ignore:/ && prev !~ /ignore:/) rep(FNR, ".catch(() => {}) swallows the error")
  }
}
function goproc(line) {
  if (gpend) { if (line ~ /^[[:space:]]*$/) return; if (line ~ /^[[:space:]]*[}]/) rep(gln, "empty 'if err != nil' block"); gpend=0 }
  if (line ~ /^[[:space:]]*_[[:space:]]*=[[:space:]]*err[[:space:]]*$/) { if (prev !~ /ignore:/ && line !~ /ignore:/) rep(FNR, "error assigned to _ (ignored)") }
  if (line ~ /if[[:space:]]+err[[:space:]]*!=[[:space:]]*nil[[:space:]]*[{][[:space:]]*[}]/) rep(FNR, "empty 'if err != nil' block")
  else if (line ~ /if[[:space:]]+err[[:space:]]*!=[[:space:]]*nil[[:space:]]*[{][[:space:]]*$/) { gpend=1; gln=FNR }
}
FNR==1 { ext=FILENAME; sub(/.*[.]/,"",ext); pend=0; jpend=0; gpend=0; prev="" }
{ if (ext=="py") pyproc($0)
  else if (ext=="go") goproc($0)
  else jsproc($0)
  prev=$0 }
EOF
runawk -f "$TMP/swallow.awk"

# ------------------------------------------------------------ windows: timeouts / handlers / unbounded
sgrep() { xargs -0 grep -H "$@" < "$TMP/src.z" 2>/dev/null; }
sgrep -l -E 'express-async-errors|[(][[:space:]]*err(or)?[[:space:]]*,[[:space:]]*req[[:space:]]*,[[:space:]]*res[[:space:]]*,[[:space:]]*next|setErrorHandler|app[.]onError|exception_handler|errorhandler|add_exception_handler|createErrorHandler|@ControllerAdvice|ErrorHandler' | head -1 > "$TMP/errmw"
HAS_ERRMW=0; [ -s "$TMP/errmw" ] && HAS_ERRMW=1

cat > "$TMP/windows.awk" <<'EOF'
function isc(s) { return (s ~ /^[[:space:]]*(\/\/|#|\*|\/\*)/) }
function add(kind, ln, rem, dep) { pn++; pk[pn]=kind; pl[pn]=ln; pr[pn]=rem; pd[pn]=0; pdep[pn]=dep }
function pcount(s,  o, c) { gsub(/"[^"]*"/,"",s); gsub(/'"'"'[^'"'"']*'"'"'/,"",s); gsub(/`[^`]*`/,"",s); o=gsub(/[(]/,"(",s); c=gsub(/[)]/,")",s); return o-c }
function addcall(kind, ln, rem, line,  dep) {
  dep=pcount(line)
  if (kind != "H" && dep <= 0) { pn++; pk[pn]=kind; pl[pn]=ln; pd[pn]=0; report(pn); pd[pn]=1 }
  else add(kind, ln, rem, dep)
}
function sat(kind, s) {
  if (kind=="T") return (s ~ /timeout|Timeout|TIMEOUT|signal|Signal|AbortController|deadline|Deadline|context[.]With/)
  if (kind=="H") return (s ~ /try[[:space:]]*[{]|[.]catch[(]|asyncHandler|catchAsync|wrapAsync|^[[:space:]]*try:/)
  return (s ~ /take[[:space:]]*:|limit|LIMIT|Limit|paginate|Paginate|cursor|skip[[:space:]]*:|[.]range[(]|[.]single[(]|maybeSingle|FETCH FIRST|TOP |COUNT[(]|count[(]|[.]slice[(]|[.]first[(]|[[]:[[:alnum:]]+[]]|(^|[^[:alnum:]_])id[[:space:]]*=/)
}
function report(i) {
  if (pk[i]=="T") { if (!filet) printf "WARN|res-timeout|%s:%d: outbound HTTP call with no timeout/abort signal in the call or file defaults (heuristic)\n", cf, pl[i] }
  else if (pk[i]=="H") printf "WARN|res-async-handler|%s:%d: async route handler with no try/catch nearby and no error middleware in the project (heuristic)\n", cf, pl[i]
  else printf "WARN|res-unbounded|%s:%d: query appears to return all rows with no limit/pagination nearby (heuristic)\n", cf, pl[i]
}
function flushfile(  i) { for (i=1;i<=pn;i++) if (!pd[i]) report(i); pn=0 }
FNR==1 { if (NR>1) flushfile(); cf=FILENAME; ext=cf; sub(/.*[.]/,"",ext); pn=0; filet=0; lastcreate=-100 }
{
  line=$0
  if (line ~ /^[[:space:]]*$/) next
  if (isc(line)) next
  # satisfy / age pending windows with THIS line (a call's own line counts)
  for (i=1;i<=pn;i++) if (!pd[i]) {
    if (sat(pk[i], line)) pd[i]=1
    else {
      pr[i]--
      if (pk[i] != "H") { pdep[i] += pcount(line); if (pdep[i] <= 0) { report(i); pd[i]=1; continue } }
      if (pr[i]<0) { report(i); pd[i]=1 }
    }
  }
  if (line ~ /defaults[.]timeout|Timeout:|WithTimeout|setDefaultTimeout|SetDeadline/) filet=1
  if (line ~ /(axios|ky|got)[.](create|extend)[(]/) lastcreate=FNR
  if (line ~ /timeout[[:space:]]*:/ && FNR-lastcreate<=4) filet=1
  low=tolower(line)
  # --- outbound HTTP without timeout
  call=0
  if (ext=="py") { if (line ~ /requests[.](get|post|put|patch|delete|head|request)[(]|urllib[.]request[.]urlopen[(]/) call=1 }
  else if (ext=="go") { if (line ~ /http[.](Get|Post|Head|PostForm)[(]/) call=1 }
  else {
    if (line ~ /(^|[^[:alnum:]_$.])fetch[(]|(window|globalThis)[.]fetch[(]|axios[.](get|post|put|patch|delete|request|head)[(]|(^|[^[:alnum:]_$.])axios[(]|https?[.](get|request)[(]|got[.](get|post)[(]/) {
      call=1
      if (line ~ /^[[:space:]]*(async[[:space:]]+)?(static[[:space:]]+)?fetch[(][^)]*[)][^;]*[{][[:space:]]*$/ || line ~ /function[[:space:]]+fetch/) call=0
    }
  }
  if (call) { if (sat("T", line)) { } else addcall("T", FNR, 8, line) }
  # --- async route handlers
  if (!(HAS_ERRMW+0)) {
    h=0
    if ((ext=="js" || ext=="ts" || ext=="mjs" || ext=="cjs" || ext=="jsx" || ext=="tsx") &&
        (line ~ /(app|router|server|api|fastify)[.](get|post|put|patch|delete|all)[(].*async/ ||
         line ~ /export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+(GET|POST|PUT|PATCH|DELETE)[(]/ ||
         line ~ /export[[:space:]]+const[[:space:]]+(GET|POST|PUT|PATCH|DELETE)[[:space:]]*=[[:space:]]*async/)) h=1
    if (ext=="py" && line ~ /^[[:space:]]*@(app|router|api|bp)[.](get|post|put|patch|delete|route)[(]/) h=1
    if (h) add("H", FNR, 30, 0)
  }
  # --- unbounded lists
  u=0
  if (line ~ /[.]findMany[(]/) u=1
  else if (line ~ /[.]find[(][[:space:]]*[{]?[[:space:]]*[}]?[[:space:]]*[)]/ && ext!="go") u=1
  else if (low ~ /select[[:space:]]+[*][[:space:]]+from/) u=1
  else if (line ~ /[.]select[(]['"][*]['"][)]/) u=1
  else if (line ~ /[.]objects[.]all[(][)]/) u=1
  else if (line ~ /[.]query[(].*[)][.]all[(][)]/) u=1
  else if (ext=="go" && line ~ /[.]Find[(]&[[:alnum:]_]+[)]/) u=1
  if (u) { if (sat("U", line)) { } else addcall("U", FNR, 8, line) }
}
END { flushfile() }
EOF
runawk -v HAS_ERRMW="$HAS_ERRMW" -f "$TMP/windows.awk"

# ------------------------------------------------------------ N+1 (call inside a loop)
cat > "$TMP/loops.awk" <<'EOF'
function isc(s) { return (s ~ /^[[:space:]]*(\/\/|#|\*|\/\*)/) }
function ind(s,  i, c, w) { w=0; for (i=1;i<=length(s);i++) { c=substr(s,i,1); if (c==" ") w++; else if (c=="\t") w+=4; else break } return w }
function iscall(s) {
  if (ext=="py") return (s ~ /[.]execute[(]|[.]executemany[(]|session[.](query|get|execute)[(]|[.]objects[.](get|filter|all|create)[(]|requests[.](get|post|put|delete|patch)[(]|httpx[.]|urlopen[(]|cursor[.]|[.]fetchone[(]|[.]fetchall[(]/)
  if (ext=="go") return (s ~ /db[.](Query|QueryRow|Exec|Get|Select)[(]|http[.](Get|Post)[(]|[.]Find[(]|[.]First[(]/)
  if (s ~ /await[[:space:]]/ && s ~ /[.](find|findOne|findMany|findUnique|findFirst|findById|findByPk|query|select|insert|update|updateOne|delete|deleteOne|remove|save|create|createMany|execute|exec|count|aggregate|upsert|get|post|put|patch|send|fetch|request|lookup)[(]|fetch[(]|axios|prisma|supabase|knex|sequelize|mongoose|pool[.]/) return 1
  return (s ~ /(^|[^[:alnum:]_$.])fetch[(]|axios[.](get|post|put|patch|delete)[(]/)
}
function isloop(s) {
  if (ext=="py") return (s ~ /^[[:space:]]*(async[[:space:]]+)?(for|while)[[:space:]].*:[[:space:]]*$/)
  if (ext=="go") return (s ~ /^[[:space:]]*for[[:space:]{]/)
  return (s ~ /(^|[^[:alnum:]_$.])(for|while)[[:space:]]*[(]|(^|[^[:alnum:]_$.])for[[:space:]]+await|[.](forEach|map|flatMap)[(]/)
}
FNR==1 { ext=FILENAME; sub(/.*[.]/,"",ext); d=0 }
{
  line=$0
  if (line ~ /^[[:space:]]*$/) next
  if (isc(line)) next
  w=ind(line)
  while (d>0 && w<=li[d]) d--
  if (d>0 && iscall(line) && !lrep[d]) {
    lrep[d]=1
    printf "WARN|res-n-plus-1|%s:%d: DB/HTTP call inside the loop that starts at line %d: one request per item (heuristic N+1; batch it or fetch in one query)\n", FILENAME, FNR, lln[d]
  }
  if (isloop(line)) {
    d++; li[d]=w; lln[d]=FNR; lrep[d]=0
    if (ext!="py" && ext!="go" && line ~ /[.](forEach|map|flatMap)[(]/ && iscall(line)) {
      lrep[d]=1
      printf "WARN|res-n-plus-1|%s:%d: DB/HTTP call inside a map/forEach callback: one request per item (heuristic N+1)\n", FILENAME, FNR
    }
  }
}
EOF
runawk -f "$TMP/loops.awk"

# ------------------------------------------------------------ project-level: logging / tracking / health
LOGLIB=$(sgrep -n -E "(require[(]|from[[:space:]]+|import[[:space:]]+)['\"]?(winston|pino|bunyan|log4js|loglevel|structlog|loguru)|import[[:space:]]+logging|logging[.]getLogger|log/slog|go[.]uber[.]org/zap|sirupsen/logrus|zerolog" | head -1)
[ -z "$LOGLIB" ] && LOGLIB=$(grep -s -n -E '"(winston|pino|bunyan|log4js|loglevel|@nestjs/common)"|structlog|loguru|logrus|zerolog' package.json requirements.txt pyproject.toml go.mod 2>/dev/null | head -1)
NCONSOLE=$(sgrep -c -E 'console[.](log|error|warn)[(]|(^|[[:space:]])print[(]|fmt[.]Println[(]' | awk -F: '{s+=$NF} END{print s+0}')
if [ -n "$LOGLIB" ]; then
  echo "PASS|res-logging|logging library in use ($LOGLIB)" >> "$FIND"
else
  EX=$(sgrep -n -E 'console[.](log|error|warn)[(]|(^|[[:space:]])print[(]|fmt[.]Println[(]' | head -1 | cut -d: -f1,2)
  if [ "${NCONSOLE:-0}" -gt 0 ]; then
    echo "WARN|res-logging|no logging library found; $NCONSOLE console.log/print call(s) only, first at ${EX} (heuristic: unstructured logs are hard to search when something breaks)" >> "$FIND"
  else
    echo "WARN|res-logging|no logging library and no log output found in source (heuristic): failures leave no trace" >> "$FIND"
  fi
fi

TRACK=$( { grep -H -s -n -i -E 'sentry|rollbar|bugsnag|datadog|dd-trace|opentelemetry|newrelic|honeybadger|airbrake|raygun|logrocket|elastic-apm' package.json requirements.txt pyproject.toml go.mod Gemfile Pipfile 2>/dev/null; sgrep -n -i -E 'sentry|rollbar|bugsnag|datadog|dd-trace|opentelemetry|newrelic|honeybadger|airbrake|raygun|logrocket|elastic-apm'; } | head -1 | cut -d: -f1,2)
if [ -n "$TRACK" ]; then
  echo "PASS|res-error-tracking|error tracking/telemetry SDK referenced at $TRACK" >> "$FIND"
else
  echo "WARN|res-error-tracking|no error-tracking/alerting SDK (Sentry, Rollbar, Bugsnag, Datadog, OpenTelemetry) found in manifests or source: you would learn about an outage from a customer" >> "$FIND"
fi

SERVER=$(sgrep -n -E "(app|router|server|fastify|api)[.](get|post|put|patch|delete|use|listen)[(]|@(app|router|bp)[.](route|get|post|put|delete)|FastAPI[(]|Flask[(]|http[.]HandleFunc|gin[.]Default|export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+(GET|POST)[(]" | head -1 | cut -d: -f1,2)
if [ -z "$SERVER" ]; then
  echo "SKIP|res-health|no HTTP server/route code found" >> "$FIND"
else
  HEALTH=$(sgrep -n -E "['\"]/(health|healthz|ping|livez|readyz|ready|status)['\"/]|def[[:space:]]+(health|healthz|ping)|HandleFunc[(]\"/health" | head -1 | cut -d: -f1,2)
  [ -z "$HEALTH" ] && HEALTH=$(find . \( -name node_modules -o -name .git \) -prune -o -type d \( -name health -o -name healthz -o -name ping \) -print 2>/dev/null | head -1)
  if [ -n "$HEALTH" ]; then echo "PASS|res-health|health-check endpoint found at ${HEALTH#./}" >> "$FIND"
  else echo "WARN|res-health|server code at $SERVER but no /health, /healthz or /ping endpoint: uptime monitors and load balancers cannot tell if it is alive" >> "$FIND"; fi
fi
[ "$HAS_ERRMW" -eq 1 ] && echo "PASS|res-async-handler|error middleware/handler found at $(head -1 "$TMP/errmw")" >> "$FIND"

# ------------------------------------------------------------ report
group res-empty-catch "no empty catch / except-pass / ignored error found"
group res-timeout "no outbound HTTP call without a timeout found (heuristic)"
group res-async-handler "no unguarded async route handler found (heuristic)"
group res-logging "logging present"
group res-error-tracking "error tracking present"
group res-health "health endpoint present"
group res-unbounded "no unbounded list query found (heuristic)"
group res-n-plus-1 "no DB/HTTP call inside a loop found (heuristic)"
exit 0

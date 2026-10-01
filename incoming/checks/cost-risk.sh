#!/usr/bin/env bash
# cost-risk.sh — runaway-API-bill report. REPORT-ONLY: never modifies the project.
#
# Usage:  bash scripts/checks/cost-risk.sh [project-dir]
# Output: one line per finding:  LEVEL|check-id|message   (PASS WARN FAIL SKIP)
# Always exits 0. Findings cite file:line; pattern-based rules are "(heuristic)".
#
# Paid APIs recognised: OpenAI, Anthropic, Google GenAI, Twilio, SendGrid,
# Stripe, Resend, Mailgun, AWS SES/SNS. Check ids:
#   cost-loop            paid call inside a loop/map/forEach
#   cost-unbounded-loop  paid call inside while(true)/for(;;)/for {} or recursion
#   cost-max-tokens      LLM call in a file that never sets a max token limit
#   cost-retry           retry logic with no max attempts / backoff
#   cost-rate-limit      public route that triggers a paid call, no rate limiter
#   cost-client-key      paid-API key referenced in client-side code (report
#                        only; security.sh owns the FAIL for exposed secrets)
#   cost-spend-limit     reminder to set a provider-side spend cap (MANUAL step)
set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "SKIP|cost-loop|cannot cd into $ROOT"; exit 0; }
CAP="${MOGGER_CHECK_CAP:-12}"
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger-cost) || exit 0
trap 'rm -rf "$TMP"' EXIT
FIND="$TMP/findings"; : > "$FIND"
IDS="cost-loop cost-unbounded-loop cost-max-tokens cost-retry cost-rate-limit cost-client-key cost-spend-limit"

group() {
  awk -F'|' -v id="$1" -v pm="$2" -v cap="$CAP" '
    $2==id { n++; if (n<=cap) print; else lv=$1 }
    END { if (n==0) print "PASS|" id "|" pm; else if (n>cap) print (lv==""?"WARN":lv) "|" id "|... and " (n-cap) " more finding(s) not shown" }' "$FIND"
}
is_skip_name() {
  case "$1" in
    *.min.js|*.min.mjs|*.bundle.js|*.d.ts|*.generated.*|*_generated.*|*.gen.*|*_pb2.py|*.pb.go|*/generated/*|*/__generated__/*|generated/*|*.snap|*-lock.*) return 0 ;;
    *.test.*|*.spec.*|*/__tests__/*|__tests__/*|*/tests/*|tests/*|*/test/*|test/*|*/test_*|test_*|*_test.go|*_test.py|*/conftest.py|*/fixtures/*|fixtures/*|*/mocks/*|*/__mocks__/*|*/e2e/*) return 0 ;;
  esac
  return 1
}

find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv \
  -o -name vendor -o -name __pycache__ -o -name .next -o -name .nuxt -o -name target -o -name coverage \
  -o -name .tox -o -name site-packages -o -name .claude -o -name .cache -o -name .turbo -o -name .svelte-kit \
  -o -name bower_components \) -prune -o -type f \( -name '*.js' -o -name '*.jsx' -o -name '*.mjs' \
  -o -name '*.cjs' -o -name '*.ts' -o -name '*.tsx' -o -name '*.py' -o -name '*.go' -o -name '*.vue' -o -name '*.svelte' \) -print 2>/dev/null \
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
sgrep() { xargs -0 grep -H "$@" < "$TMP/src.z" 2>/dev/null; }

# ------------------------------------------------------------ paid-call scanner
cat > "$TMP/cost.awk" <<'EOF'
function isc(s) { return (s ~ /^[[:space:]]*(\/\/|#|\*|\/\*)/) }
function ind(s,  i, c, w) { w=0; for (i=1;i<=length(s);i++) { c=substr(s,i,1); if (c==" ") w++; else if (c=="\t") w+=4; else break } return w }
function ispaidcall(s) {
  if (s ~ /chat[.]completions[.]create|responses[.]create|embeddings[.]create|images[.]generate|ChatCompletion[.]create|generateContent|generate_content|embedContent|paymentIntents[.](create|update)|checkout[.]sessions[.]create|stripe[.](customers|subscriptions|invoices|refunds|payouts|charges)[.]create|SendEmailCommand|SendRawEmailCommand|PublishCommand|sns[.]publish|ses[.]send_email|ses[.]sendEmail|sgMail[.]send|mg[.]messages[.]create|resend[.]emails[.]send|client[.]calls[.]create/) return 1
  if (provider && s ~ /messages[.](create|stream)[(]|emails[.]send[(]|mail[.]send[(]|sns_client[.]publish/) return 1
  return 0
}
function isllm(s) {
  if (s ~ /chat[.]completions[.]create|responses[.]create|ChatCompletion[.]create|generateContent|generate_content/) return 1
  if (s ~ /messages[.](create|stream)[(]/ && !twilio) return 1
  return 0
}
function isinfloop(s) {
  return (s ~ /^[[:space:]]*while[[:space:]]*[(]?[[:space:]]*(true|True|1)[[:space:]]*[)]?[[:space:]]*[:{]?[[:space:]]*$/ || s ~ /for[[:space:]]*[(][[:space:]]*;[[:space:]]*;[[:space:]]*[)]/ || (ext=="go" && s ~ /^[[:space:]]*for[[:space:]]*[{][[:space:]]*$/))
}
function isloop(s) {
  if (isinfloop(s)) return 1
  if (ext=="py") return (s ~ /^[[:space:]]*(async[[:space:]]+)?(for|while)[[:space:]].*:[[:space:]]*$/)
  if (ext=="go") return (s ~ /^[[:space:]]*for[[:space:]{]/)
  return (s ~ /(^|[^[:alnum:]_$.])(for|while)[[:space:]]*[(]|(^|[^[:alnum:]_$.])for[[:space:]]+await|[.](forEach|map|flatMap)[(]/)
}
function closeloop(k) {
  if (lcall[k]) {
    if (linf[k]) {
      if (!lbound[k]) printf "FAIL|cost-unbounded-loop|%s:%d: paid API call (line %d) inside an infinite loop that starts at line %d with no break/return/attempt limit visible: a bug here bills you until you stop it\n", cf, lcall[k], lcall[k], lln[k]
      else printf "WARN|cost-unbounded-loop|%s:%d: paid API call (line %d) inside an infinite loop starting at line %d (an exit condition exists, verify it is reachable) (heuristic)\n", cf, lcall[k], lcall[k], lln[k]
    } else if (lwhile[k] && lcatch[k] && !lbound[k]) {
      printf "WARN|cost-retry|%s:%d: hand-rolled retry loop around a paid call (loop at line %d) with no visible max attempts or backoff (heuristic)\n", cf, lcall[k], lln[k]
    }
  }
}
function flushfile(  k, fn) {
  while (d>0) { closeloop(d); d-- }
  for (fn in fnpaid) if (fn in fnself) printf "WARN|cost-unbounded-loop|%s:%d: function '%s' calls a paid API (line %d) and calls itself (line %d): recursion with a paid call needs a depth limit (heuristic)\n", cf, fnpaid[fn], fn, fnpaid[fn], fnself[fn]
  if (!tokset) for (k=1;k<=nllm;k++) printf "WARN|cost-max-tokens|%s:%d: LLM call in a file that never sets max_tokens / max_output_tokens: output length (and cost) is unbounded (heuristic)\n", cf, llmln[k]
  delete fnpaid; delete fnself; nllm=0; delete llmln
}
FNR==1 { if (NR>1) flushfile(); cf=FILENAME; ext=cf; sub(/.*[.]/,"",ext); d=0; provider=0; twilio=0; tokset=0; curfn=""; nllm=0 }
{
  line=$0
  if (line ~ /^[[:space:]]*$/) next
  if (isc(line)) next
  if (line ~ /openai|anthropic|twilio|sendgrid|stripe|resend|mailgun|generativeai|@google\/genai|google[.]genai|client-ses|client-sns|boto3|aws-sdk/) provider=1
  if (line ~ /twilio/) twilio=1
  if (line ~ /max_tokens|max_output_tokens|maxOutputTokens|max_completion_tokens|maxTokens|max_new_tokens/) tokset=1
  w=ind(line)
  while (d>0 && w<=li[d]) { closeloop(d); d-- }
  # function tracking for recursion
  if (match(line, /^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?(def|function)[[:space:]]+[[:alnum:]_$]+/)) { s=substr(line,RSTART,RLENGTH); sub(/^.*[[:space:]]/,"",s); curfn=s }
  else if (curfn != "" && index(line, curfn "(")>0 && line !~ /^[[:space:]]*(async[[:space:]]+)?(def|function)/) { if (!(curfn in fnself)) fnself[curfn]=FNR }
  paid=ispaidcall(line)
  if (paid) {
    if (curfn != "" && !(curfn in fnpaid)) fnpaid[curfn]=FNR
    if (isllm(line)) { nllm++; llmln[nllm]=FNR }
    if (d>0) {
      if (!lcall[d]) lcall[d]=FNR
      k=d
      if (!lrep[k] && !linf[k]) { lrep[k]=1; printf "WARN|cost-loop|%s:%d: paid API call inside the loop that starts at line %d: cost grows with the collection size (cap the batch, add a budget or a hard item limit)\n", cf, FNR, lln[k] }
      # propagate to outer loops so infinite outer loops are seen
      for (k=1;k<d;k++) if (!lcall[k]) lcall[k]=FNR
    }
  }
  if (d>0 && line ~ /break|return|raise|attempt|retr|max_|MAX_|limit|budget|sleep|backoff|Backoff|range[(]/) for (k=1;k<=d;k++) lbound[k]=1
  if (d>0 && line ~ /catch|except/) for (k=1;k<=d;k++) lcatch[k]=1
  if (isloop(line)) {
    d++; li[d]=w; lln[d]=FNR; lrep[d]=0; lcall[d]=0; lbound[d]=0; lcatch[d]=0
    linf[d]=isinfloop(line); lwhile[d]=(line ~ /(^|[^[:alnum:]_$.])while/)
    if (ext!="py" && ext!="go" && line ~ /[.](forEach|map|flatMap)[(]/ && paid) { lrep[d]=1; lcall[d]=FNR; printf "WARN|cost-loop|%s:%d: paid API call inside a map/forEach callback: one billed request per item (heuristic)\n", cf, FNR }
  }
}
END { flushfile() }
EOF
xargs -0 awk -f "$TMP/cost.awk" < "$TMP/src.z" >> "$FIND" 2>/dev/null

# retry libs with no stop condition (window of 6 lines after the marker)
cat > "$TMP/retry.awk" <<'EOF'
function flush() { if (pend) printf "WARN|cost-retry|%s:%d: retry helper with no visible max attempts / stop / backoff config in the next lines: a failing paid call could be retried forever (heuristic)\n", cf, pln; pend=0 }
FNR==1 { flush(); cf=FILENAME }
{
  if ($0 ~ /^[[:space:]]*(\/\/|#|\*)/) next
  if ($0 ~ /^[[:space:]]*(import|from)[[:space:]]/ || $0 ~ /require[(]/) next
  if (pend) {
    if ($0 ~ /stop|max_tries|max_time|max_attempts|maxAttempts|retries[[:space:]]*[:=]|maxRetries|attempts|retries=|tries=|limit/) pend=0
    else { rem--; if (rem<0) flush() }
  }
  if ($0 ~ /@retry|@backoff[.]|axios-retry|(^|[^[:alnum:]_])retry[(]|pRetry[(]|asyncRetry[(]|retryWithBackoff[(]/) {
    if ($0 ~ /stop|max_tries|max_time|max_attempts|maxAttempts|retries[[:space:]]*[:=]|maxRetries|attempts|retries=|tries=/) { } else { flush(); pend=1; pln=FNR; rem=6 }
  }
}
END { flush() }
EOF
xargs -0 awk -f "$TMP/retry.awk" < "$TMP/src.z" >> "$FIND" 2>/dev/null

# ------------------------------------------------------------ paid usage summary
PAIDCALL=$(sgrep -n -E 'chat[.]completions[.]create|responses[.]create|messages[.](create|stream)[(]|generateContent|generate_content|embeddings[.]create|ChatCompletion[.]create|paymentIntents[.]create|checkout[.]sessions[.]create|SendEmailCommand|PublishCommand|sgMail[.]send|emails[.]send[(]|calls[.]create' | head -1 | cut -d: -f1,2)
PAIDSDK=$(grep -H -s -n -i -E 'openai|anthropic|twilio|sendgrid|stripe|resend|mailgun|generative-ai|@google/genai|google-genai|google-generativeai|client-ses|client-sns|boto3' package.json requirements.txt requirements-dev.txt pyproject.toml go.mod Pipfile 2>/dev/null | head -1 | cut -d: -f1,2)
[ -z "$PAIDSDK" ] && PAIDSDK=$(sgrep -n -E "(require[(]|from[[:space:]]+|import[[:space:]]+)['\"]?(openai|@anthropic-ai/sdk|anthropic|stripe|twilio|@sendgrid|resend|mailgun|@google/generative-ai|@google/genai|google[.]generativeai|boto3|@aws-sdk/client-(ses|sns))" | head -1 | cut -d: -f1,2)

# ------------------------------------------------------------ rate limiting on public routes that trigger paid calls
RATELIB=$(sgrep -n -i -E 'express-rate-limit|rate-limiter-flexible|slowapi|flask-limiter|flask_limiter|django-ratelimit|django_ratelimit|upstash/ratelimit|nestjs/throttler|fastify-rate-limit|fastify/rate-limit|rate_limit|ratelimit|Limiter[(]|golang.org/x/time/rate|tollbooth|throttle' | head -1 | cut -d: -f1,2)
[ -z "$RATELIB" ] && RATELIB=$(grep -H -s -n -i -E 'rate-limit|ratelimit|throttler|slowapi|limiter' package.json requirements.txt pyproject.toml go.mod 2>/dev/null | head -1 | cut -d: -f1,2)
ROUTEFILES=$(sgrep -l -E "(app|router|server|fastify|api)[.](get|post|put|patch|delete|all)[(]|@(app|router|bp)[.](route|get|post|put|delete)|export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+(GET|POST|PUT|PATCH|DELETE)[(]|export[[:space:]]+const[[:space:]]+(GET|POST)[[:space:]]*=|http[.]HandleFunc")
PAIDROUTE=""
if [ -n "$ROUTEFILES" ]; then
  for f in $ROUTEFILES; do
    hit=$(grep -n -E 'chat[.]completions[.]create|responses[.]create|messages[.](create|stream)[(]|generateContent|generate_content|embeddings[.]create|ChatCompletion[.]create|paymentIntents[.]create|checkout[.]sessions[.]create|SendEmailCommand|PublishCommand|sgMail[.]send|emails[.]send[(]|calls[.]create|[.]send_message[(]' "$f" 2>/dev/null | head -1 | cut -d: -f1)
    [ -n "$hit" ] && { PAIDROUTE="$f:$hit"; break; }
  done
fi
if [ -z "$PAIDCALL" ] && [ -z "$PAIDSDK" ]; then
  : # nothing paid: groups fall back to SKIP below
elif [ -z "$PAIDROUTE" ]; then
  echo "SKIP|cost-rate-limit|no route handler that directly makes a paid call was found (heuristic; a paid call reached through another module is not traced)" >> "$FIND"
elif [ -n "$RATELIB" ]; then
  echo "PASS|cost-rate-limit|rate limiting referenced at $RATELIB (verify it is applied to the route at $PAIDROUTE)" >> "$FIND"
else
  echo "WARN|cost-rate-limit|route handler at $PAIDROUTE triggers a paid API call and no rate limiter (express-rate-limit, slowapi, upstash ratelimit, ...) exists in the project (heuristic): anyone who finds the URL can run up your bill" >> "$FIND"
fi

# ------------------------------------------------------------ client-side keys (report only)
{
  sgrep -n -E '(NEXT_PUBLIC|VITE|REACT_APP|EXPO_PUBLIC|NUXT_PUBLIC|PUBLIC)_[[:alnum:]_]*(OPENAI|ANTHROPIC|SENDGRID|TWILIO|RESEND|MAILGUN|SECRET|GEMINI)[[:alnum:]_]*'
  sgrep -n -E 'dangerouslyAllowBrowser'
  sgrep -n -E 'sk-(proj|ant)-[[:alnum:]_-]+'
  find . \( -name node_modules -o -name .git \) -prune -o -type f -name '.env*' -print 2>/dev/null | tr '\n' '\0' \
    | xargs -0 grep -H -n -E '^(NEXT_PUBLIC|VITE|REACT_APP|EXPO_PUBLIC|NUXT_PUBLIC)_[[:alnum:]_]*(OPENAI|ANTHROPIC|SENDGRID|TWILIO|RESEND|MAILGUN|SECRET|GEMINI)' 2>/dev/null
} | sed 's|^\./||' | awk -F: '!s[$1 ":" $2]++ { printf "WARN|cost-client-key|%s:%s: paid-API key/secret referenced where browsers can read it (client-side env prefix, dangerouslyAllowBrowser or literal key): anyone can copy it and bill you (report only; the security check owns the FAIL)\n", $1, $2 }' >> "$FIND"

# ------------------------------------------------------------ spend limit reminder
if [ -n "$PAIDCALL" ] || [ -n "$PAIDSDK" ]; then
  echo "WARN|cost-spend-limit|paid API usage detected (${PAIDCALL:-$PAIDSDK}): set a hard spend limit / budget alert in each provider dashboard. Manual step: it CANNOT be verified from code" >> "$FIND"
else
  echo "PASS|cost-spend-limit|no paid API usage detected; if you add one, set a provider-side spend limit first (manual step, cannot be verified from code)" >> "$FIND"
fi

# ------------------------------------------------------------ report
if [ -z "$PAIDCALL" ] && [ -z "$PAIDSDK" ]; then
  for i in cost-loop cost-unbounded-loop cost-max-tokens cost-retry cost-rate-limit; do echo "SKIP|$i|no paid API calls or SDKs detected"; done
else
  group cost-loop "no paid API call inside a loop found"
  group cost-unbounded-loop "no paid API call inside an infinite loop or recursion found (heuristic)"
  group cost-max-tokens "every LLM call file sets a max token limit (or none found)"
  group cost-retry "no unbounded retry logic found (heuristic)"
  group cost-rate-limit "rate limiting present"
fi
group cost-client-key "no paid-API key referenced in client-side code"
group cost-spend-limit "set a provider-side spend limit (manual)"
exit 0

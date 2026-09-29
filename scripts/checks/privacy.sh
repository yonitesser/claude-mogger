#!/usr/bin/env bash
# privacy.sh — personal-data inventory + "does a small app have the basics" check.
# REPORT-ONLY: never modifies the project. Always exits 0.
#
# NOT LEGAL ADVICE. This lists what the CODE does (with file:line evidence)
# and which artifacts exist. Whether GDPR / CCPA / anything else applies, and
# what is required, is for the owner and a lawyer to decide. Detection is
# pattern-based (heuristic) and can miss things or over-report.
#
# Usage (from project root):  bash scripts/checks/privacy.sh [project-dir]
# Output: one line per finding  LEVEL|check-id|message   (PASS WARN FAIL SKIP)
set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { printf 'SKIP|privacy-data|cannot cd to %s\n' "$ROOT"; exit 0; }
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger)
[ -n "$TMP" ] && [ -d "$TMP" ] || { printf 'SKIP|privacy-data|no temp dir available\n'; exit 0; }
trap 'rm -rf "$TMP"' EXIT

out() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }

# ---- file inventory (skips vendored/build dirs) ---------------------------
find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv \
  -o -name __pycache__ -o -name .next -o -name coverage -o -name .claude -o -name target -o -name vendor \
  -o -name .cache \) -prune -o -type f -print 2>/dev/null | sed 's|^\./||' | head -8000 > "$TMP/all0"
: > "$TMP/all"; : > "$TMP/src"; : > "$TMP/doc"; : > "$TMP/deps"
while IFS= read -r f; do
  case "$f" in
    *.min.js|*.min.css|*.map|*package-lock.json|*yarn.lock|*pnpm-lock.yaml|*.lock|*.png|*.jpg|*.jpeg|*.gif|*.ico|*.woff|*.woff2|*.ttf|*.pdf|*.zip|*.mp4|*.webp|*.svg) continue;;
  esac
  printf '%s\n' "$f" >> "$TMP/all"
  case "$f" in
    */test/*|*/tests/*|*/__tests__/*|*/spec/*|*/__mocks__/*|*/fixtures/*|test/*|tests/*|__tests__/*|spec/*|*.test.*|*.spec.*|*/test_*|test_*|*_test.py|*_test.go) continue;;
  esac
  case "$f" in
    *package.json|*requirements.txt|*Pipfile|*pyproject.toml|*Gemfile|*composer.json|*go.mod|*pom.xml|*build.gradle) printf '%s\n' "$f" >> "$TMP/deps";;
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte|*.astro|*.html|*.htm|*.py|*.rb|*.php|*.go|*.java|*.kt|*.cs|*.erb|*.ejs|*.hbs|*.pug|*.njk|*.twig|*.prisma|*.sql|*.rs|*.swift|*.dart) printf '%s\n' "$f" >> "$TMP/src";;
    *.md|*.mdx|*.txt|*.rst) printf '%s\n' "$f" >> "$TMP/doc";;
  esac
done < "$TMP/all0"
cat "$TMP/src" "$TMP/deps" > "$TMP/srcdeps"
cat "$TMP/src" "$TMP/deps" "$TMP/doc" > "$TMP/everything"
NSRC=$(wc -l < "$TMP/src" | tr -d ' ')

scan() {  # scan <listfile> <ere>  -> file:line:text (case-insensitive)
  [ -s "$1" ] || return 0
  tr '\n' '\0' < "$1" | xargs -0 grep -H -n -I -i -E -e "$2" -- 2>/dev/null | head -300
}
cite() {  # stdin file:line:text -> "a:1, b:2, c:3 (+N more)"
  awk -F: '{ n++; if (n <= 3) s = s (n > 1 ? ", " : "") $1 ":" $2 } END { if (n > 3) s = s " (+" (n - 3) " more)"; print s }'
}

if [ "$NSRC" -eq 0 ]; then
  out SKIP privacy-data "no source files found to scan"
  out SKIP privacy-trackers "no source files found to scan"
  out SKIP privacy-legal "not legal advice: this tool lists what the code does; the owner and a lawyer decide what is required"
  exit 0
fi

# ---- 1. personal data collected ------------------------------------------
# A hit needs the token AND a field/schema/request context on the same line.
CTX='<input|<select|<textarea|<TextField|<Field|name=|type=|autoComplete|autocomplete|htmlFor|register[(]|FormData|formData|req[.]body|request[.](form|json|POST|data)|params[.]|CREATE TABLE|Column|models[.]|DataTypes|z[.]string|Schema|@Column|t[.](string|text|date|integer)|add_column|String|varchar|TEXT|type:|@db[.]|DateTime|z[.]date'
FOUND=0
FOUNDLIST=""
data_cat() {  # data_cat <label> <token-ere>  (needs field/schema context)
  local label="$1" tok="$2" h
  h=$(scan "$TMP/src" "($CTX).*($tok)|($tok).*($CTX)")
  if [ -n "$h" ]; then
    out WARN privacy-data "$label: collected or stored at $(printf '%s\n' "$h" | cite) [heuristic: form field, model column or request field]"
    FOUND=$((FOUND+1)); FOUNDLIST="$FOUNDLIST$label, "
  fi
}
direct_cat() {  # direct_cat <label> <ere>  (the pattern itself is the evidence)
  local label="$1" pat="$2" h
  h=$(scan "$TMP/src" "$pat")
  if [ -n "$h" ]; then
    out WARN privacy-data "$label: found at $(printf '%s\n' "$h" | cite) [heuristic]"
    FOUND=$((FOUND+1)); FOUNDLIST="$FOUNDLIST$label, "
  fi
}
data_cat "email address" 'e[-_]?mail'
data_cat "phone number" 'phone|telephone|mobile_?(number|no)'
data_cat "postal address" 'street|postcode|postal_?code|zip_?code|(shipping|billing|home|mailing)_?address|address_?line'
data_cat "person name" 'first_?name|last_?name|full_?name|surname|given_?name|family_?name'
data_cat "date of birth" 'date_?of_?birth|birth_?date|birthday|(^|[^[:alpha:]])dob([^[:alpha:]]|$)'
data_cat "government id" 'social_?security|(^|[^[:alpha:]])ssn([^[:alpha:]]|$)|passport|national_?id|tax_?id|driver_?s?_?licen[cs]e'
data_cat "location coordinates" 'latitude|longitude|geo_?location|(^|[^[:alpha:]])(lat|lng|lon)[[:space:]]*[:=]'
direct_cat "geolocation API" 'navigator[.]geolocation|getCurrentPosition|watchPosition'
direct_cat "IP address capture" 'req[.]ip|request[.]ip|remote_addr|x-forwarded-for|remote_ip|client_?ip|ip_?address|getRemoteAddr|socket[.]remoteAddress'
data_cat "payment card data" 'card_?number|cvv|cvc|credit_?card|iban|routing_?number|cc-number|cc-csc'
direct_cat "payment processor SDK" 'CardElement|Stripe[(]|stripe[.](customers|charges|paymentIntents|checkout)'
data_cat "health data" 'diagnosis|medical|health_?(record|data|condition)|medication|prescription|patient|allergy|allergies|blood_?(type|pressure)|symptom|heart_?rate'
data_cat "sensitive attributes" 'gender|ethnicity|religion|sexual_?orientation|political_?(view|opinion)|(^|[^[:alpha:]])race([^[:alpha:]]|$)'
data_cat "account credentials" 'password|passwd'
data_cat "photo or avatar" 'avatar|profile_?(photo|picture|image)|selfie|photo_?url'
direct_cat "file/photo upload" 'type=.file|multer|formidable|busboy|getUserMedia|ImageField|FileField|upload_to|Dropzone|uploadthing|multipart/form-data|UploadFile|request[.]files|req[.]file'
if [ "$FOUND" -eq 0 ]; then
  out PASS privacy-data "no personal-data fields detected in $NSRC source files (heuristic; data held in third-party tools or set at runtime is not visible here)"
fi

# ---- 2. third-party trackers / SDKs --------------------------------------
TRK=0; TRK_CONSENT=0
tracker() {  # tracker <name> <needs-consent 0/1> <ere>
  local h
  h=$(scan "$TMP/srcdeps" "$3")
  if [ -n "$h" ]; then
    TRK=$((TRK+1)); [ "$2" = "1" ] && TRK_CONSENT=$((TRK_CONSENT+1))
    out WARN privacy-trackers "$1 at $(printf '%s\n' "$h" | cite) — third party receives visitor data (heuristic match)"
  fi
}
tracker "Google Analytics / gtag" 1 'googletagmanager[.]com|gtag[(]|google-analytics|react-ga|vue-gtag|@next/third-parties|G-[[:alnum:]]{8,}|UA-[0-9]{4,}-[0-9]'
tracker "Meta (Facebook) Pixel" 1 'fbq[(]|connect[.]facebook[.]net|facebook[.]com/tr|react-facebook-pixel|fbevents'
tracker "Hotjar" 1 'hotjar'
tracker "Mixpanel" 1 'mixpanel'
tracker "Segment" 1 'cdn[.]segment|@segment/|analytics-next|analytics-node'
tracker "PostHog" 1 'posthog'
tracker "Amplitude" 1 'amplitude'
tracker "FullStory" 1 'fullstory'
tracker "LogRocket (session replay)" 1 'logrocket'
tracker "Microsoft Clarity" 1 'clarity[.]ms'
tracker "Heap" 1 'heap[.]io|heapanalytics|heap[.]load'
tracker "Plausible / Matomo / Fathom" 1 'plausible[.]io|matomo|fathom'
tracker "Google Ads / AdSense / DoubleClick" 1 'adsbygoogle|doubleclick|googlesyndication|adsense'
tracker "TikTok / LinkedIn / Twitter / Snap pixel" 1 'analytics[.]tiktok|ttq[.]|snap[.]licdn|static[.]ads-twitter|twq[(]|snaptr[(]'
tracker "Sentry session replay" 1 'replayIntegration|Sentry[.]Replay|replaysSessionSampleRate|replaysOnErrorSampleRate'
tracker "Sentry (error monitoring; can receive IPs/user data)" 0 '@sentry/|sentry-sdk|Sentry[.]init|sentry_sdk'
tracker "Datadog RUM" 1 '@datadog/browser-rum|datadogRum'
tracker "Vercel Analytics / Speed Insights" 1 '@vercel/analytics|@vercel/speed-insights'
tracker "Firebase Analytics" 1 'firebase/analytics|getAnalytics[(]'
tracker "Chat/CRM widget (Intercom, HubSpot, Crisp, Drift, Tawk)" 1 'intercom|hubspot|crisp[.]chat|drift[.]com|tawk[.]to'
tracker "Google Fonts loaded from Google servers (visitor IP sent)" 0 'fonts[.]googleapis[.]com'
tracker "Google reCAPTCHA" 0 'recaptcha'
if [ "$TRK" -eq 0 ]; then
  out PASS privacy-trackers "no third-party tracker/analytics/ad SDK patterns found"
fi

# ---- 3. cookies / local storage / logging ---------------------------------
h=$(scan "$TMP/srcdeps" 'document[.]cookie[[:space:]]*=|res[.]cookie[(]|set_cookie|setcookie[(]|Set-Cookie|cookies[.]set[(]|js-cookie|cookie-session|express-session|next-auth|Cookies[.]set|response[.]cookies')
COOK=0
if [ -n "$h" ]; then
  COOK=1
  out WARN privacy-cookies "cookies set/handled at $(printf '%s\n' "$h" | cite) — session cookies are usually essential; anything else may need consent (owner to decide)"
else
  out PASS privacy-cookies "no cookie-setting code found"
fi
h=$(scan "$TMP/src" '(localStorage|sessionStorage).*(email|phone|first_?name|last_?name|full_?name|street|birth|profile|userdata|user_?info)|(email|phone|profile|userdata|user_?info).*(localStorage|sessionStorage)[.]setItem')
if [ -n "$h" ]; then
  FOUND=$((FOUND+1))
  out WARN privacy-storage "personal data written to browser storage at $(printf '%s\n' "$h" | cite) [heuristic]"
else
  out PASS privacy-storage "no personal data written to localStorage/sessionStorage (heuristic)"
fi
h=$(scan "$TMP/src" '(console[.]|logger[.]|logging[.]|log[.](info|debug|error)|print[(]|puts ).*((req|request)[.]body|request[.](json|form)|[.]email|[$]email|email[,)])')
if [ -n "$h" ]; then
  out WARN privacy-logging "request bodies or emails may be logged at $(printf '%s\n' "$h" | cite) — logs keep personal data too [heuristic]"
else
  out PASS privacy-logging "no logging of request bodies/emails found (heuristic)"
fi

# ---- 4. processors (who receives data) ------------------------------------
PROCS=""; NPROC=0
proc() {  # proc <name> <ere>
  local h
  h=$(scan "$TMP/deps" "$2")
  if [ -n "$h" ]; then
    NPROC=$((NPROC+1))
    PROCS="$PROCS$1 ($(printf '%s\n' "$h" | head -1 | cut -d: -f1,2)), "
  fi
}
proc "Stripe" '(^|[^[:alnum:]_-])stripe([^[:alnum:]_-]|$)'
proc "PayPal" 'paypal'
proc "Twilio" 'twilio'
proc "SendGrid" 'sendgrid'
proc "Mailgun" 'mailgun'
proc "Postmark" 'postmark'
proc "Resend" '(^|[^[:alnum:]_-])resend([^[:alnum:]_-]|$)'
proc "Mailchimp" 'mailchimp'
proc "Firebase" 'firebase'
proc "Supabase" 'supabase'
proc "Auth0" 'auth0'
proc "Clerk" '@clerk/'
proc "Cloudinary" 'cloudinary'
proc "AWS SDK" '@aws-sdk|boto3|aws-sdk'
proc "OpenAI" '(^|[^[:alnum:]_-])openai([^[:alnum:]_-]|$)'
proc "Anthropic" 'anthropic'
proc "Algolia" 'algolia'
proc "Airtable" 'airtable'
if [ "$NPROC" -gt 0 ]; then
  out WARN privacy-processors "third-party services that can receive user data (from dependency files): ${PROCS%, } — each is a recipient to list in DATA.md; whether a data-processing agreement is needed is for the owner/lawyer"
else
  out PASS privacy-processors "no known third-party data-processor packages in dependency files"
fi

# ---- 5. artifacts a small app needs ---------------------------------------
NEED=0
[ "$FOUND" -gt 0 ] || [ "$TRK" -gt 0 ] || [ "$COOK" -gt 0 ] && NEED=1

# privacy policy
pf=$(grep -i -E 'privacy|datenschutz' "$TMP/all" | grep -v -E 'scripts/checks/privacy[.]sh|mogger-privacy' | head -3 | tr '\n' ' ')
pl=$(scan "$TMP/src" 'href=.*/privacy|to=.*/privacy|[/]privacy[-_]?policy|.[/]privacy.')
if [ -n "$pf" ]; then
  out PASS privacy-policy "privacy policy file/page found: $pf(content and accuracy are for the owner/lawyer to review)"
elif [ -n "$pl" ]; then
  out WARN privacy-policy "privacy page is linked at $(printf '%s\n' "$pl" | cite) but no matching file found"
elif [ "$NEED" -eq 1 ]; then
  out WARN privacy-policy "no privacy policy page/file found, but the app handles personal data/trackers/cookies (see privacy-data lines)"
else
  out SKIP privacy-policy "no personal data, trackers or cookies detected, nothing to document (heuristic)"
fi

# consent banner
if [ "$TRK_CONSENT" -gt 0 ]; then
  h=$(scan "$TMP/everything" 'cookie[-_ ]?consent|cookie[-_ ]?banner|cookiebot|onetrust|osano|termly|iubenda|consent[-_ ]?mode|klaro|axeptio|didomi|usercentrics|acceptcookies|accept[-_ ]all[-_ ]cookies|cookieconsent')
  if [ -n "$h" ]; then
    out PASS privacy-consent "consent/cookie-banner code found at $(printf '%s\n' "$h" | cite) (whether it blocks trackers before consent is not checked)"
  else
    out WARN privacy-consent "$TRK_CONSENT analytics/ad/replay tracker(s) present but no cookie/consent banner code found (heuristic; whether consent is required is for the owner/lawyer)"
  fi
else
  out SKIP privacy-consent "no consent-requiring trackers detected"
fi

# delete / export
if [ "$FOUND" -gt 0 ]; then
  h=$(scan "$TMP/src" 'delete_?(my_?)?(account|user)|(account|user)s?/[^[:space:]]*delete|destroy_?user|deleteUser|deleteAccount|delete[[:space:]]+account|erase_?user|anonymi[sz]e|gdpr|right.to.be.forgotten|(router|app)[.]delete[(].(/api)?/(users?|account|me)|@app[.]delete|(delete|destroy)[[:space:]]*.*(account|user)')
  if [ -n "$h" ]; then
    out PASS privacy-delete "account/data deletion code found at $(printf '%s\n' "$h" | cite) [heuristic: verify it removes data from every store, backups and processors]"
  else
    out WARN privacy-delete "personal data is stored but no delete-account / erase-user route found (heuristic)"
  fi
  h=$(scan "$TMP/src" 'export_?(my|user|account)_?data|data[-_]export|exportUser|export_user|download[-_]?(my)?[-_]?data|takeout|subject.access|dsar|/export|/me/data|(router|app)[.]get[(].*/(export|download)')
  if [ -n "$h" ]; then
    out PASS privacy-export "user data export code found at $(printf '%s\n' "$h" | cite) [heuristic]"
  else
    out WARN privacy-export "personal data is stored but no export/download-my-data endpoint found (heuristic)"
  fi
  h=$(scan "$TMP/everything" 'retention|retained|purge|expireAfterSeconds|older than|kept for|deleted after|auto.?delete|delete.*after [0-9]+ (day|month|year)')
  if [ -n "$h" ]; then
    out PASS privacy-retention "retention wording/code found at $(printf '%s\n' "$h" | cite) (the period itself is an owner decision)"
  else
    out WARN privacy-retention "no data-retention note or purge job found: how long is personal data kept? OWNER TO DECIDE (record it in DATA.md)"
  fi
else
  out SKIP privacy-delete "no personal data detected"
  out SKIP privacy-export "no personal data detected"
  out SKIP privacy-retention "no personal data detected"
fi

# DPA / subprocessor mention
if [ "$NPROC" -gt 0 ] || [ "$TRK" -gt 0 ]; then
  h=$(scan "$TMP/doc" 'sub-?processor|data processing (agreement|addendum)|(^|[^[:alpha:]])dpa([^[:alpha:]]|$)|processors?( list)?')
  hh=$(scan "$TMP/src" 'sub-?processor|data processing (agreement|addendum)')
  if [ -n "$h$hh" ]; then
    out PASS privacy-subprocessors "subprocessor/DPA mention found at $(printf '%s\n%s\n' "$h" "$hh" | grep -v '^$' | cite)"
  else
    out WARN privacy-subprocessors "third parties receive data (see privacy-processors/privacy-trackers) but no subprocessor list or DPA mention found in docs"
  fi
else
  out SKIP privacy-subprocessors "no third-party processors or trackers detected"
fi

out SKIP privacy-legal "not legal advice: this lists what the code does; whether GDPR/CCPA apply and what is required is for the owner and a lawyer to decide"
exit 0

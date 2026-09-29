#!/usr/bin/env bash
# Tests for privacy / docs / a11y / lock-in checks. Run: bash tests/hygiene.test.sh
# Self-contained temp sandboxes: no network, no browsers.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
C="$ROOT/scripts/checks"
PASS=0; FAIL=0
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

w() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }   # w <path> <content>
run() {  # run <dir> <script-name>  -> OUT, RC
  OUT=$(cd "$1" && bash "$C/$2.sh" 2>&1); RC=$?
}
has()   { case "$OUT" in *"$2"*) ok "$1";; *) bad "$1"; printf '       missing: [%s]\n' "$2";; esac; }
hasnt() { case "$OUT" in *"$2"*) bad "$1"; printf '       unexpected: [%s]\n' "$2";; *) ok "$1";; esac; }
contract() {  # contract <label>: exit 0, every line LEVEL|id|msg
  [ "$RC" -eq 0 ] && ok "$1: exits 0" || bad "$1: exits 0 (got $RC)"
  local badl
  badl=$(printf '%s\n' "$OUT" | grep -v -E '^(PASS|WARN|FAIL|SKIP)[|][a-z0-9-]+[|].+' | head -1)
  [ -z "$badl" ] && ok "$1: every line is LEVEL|check-id|message" || { bad "$1: line format"; printf '       bad line: [%s]\n' "$badl"; }
  printf '%s\n' "$OUT" | grep -q -E '^(PASS|SKIP)[|]' && ok "$1: at least one PASS/SKIP" || bad "$1: at least one PASS/SKIP"
}
tree_sum() { (cd "$1" && find . -type f | sort | while IFS= read -r f; do cksum "$f"; done); }

echo "== syntax + portability lint"
for s in privacy docs a11y lockin; do
  bash -n "$C/$s.sh" 2>/dev/null && ok "bash -n $s.sh" || bad "bash -n $s.sh"
  [ -f "$C/$s.sh" ] && ok "exists: scripts/checks/$s.sh" || bad "exists: $s.sh"
  body=$(grep -v '^[[:space:]]*#' "$C/$s.sh")
  hits=$(printf '%s\n' "$body" | grep -E 'mapfile|readarray|declare -A|grep -P|sed -i|head -n 0|head -0|readlink -f|date -d|stat -c|[$][{][a-z_]+,,|[[]A-Z[]]|[[]a-z[]]' | head -1)
  [ -z "$hits" ] && ok "$s.sh: no bash4/GNU-only constructs" || { bad "$s.sh: portability"; printf '       %s\n' "$hits"; }
done
node --check "$ROOT/scripts/a11y-browser.mjs" >/dev/null 2>&1 && ok "node --check a11y-browser.mjs" || bad "node --check a11y-browser.mjs"

echo "== privacy.sh: data-heavy app"
P="$SANDBOX/p1"
mkdir -p "$P"
w "$P/src/form.html" '<form><input type="email" name="email"><input name="phone" placeholder="Phone">
<input type="date" name="date_of_birth"></form>'
w "$P/prisma/schema.prisma" 'model User {
  id Int @id
  email String @unique
  passport String
  card_number String
}'
w "$P/src/track.html" '<script async src="https://www.googletagmanager.com/gtag/js?id=G-ABCDEFGH12"></script>
<script>fbq("init", "1");</script>
<script src="https://hotjar.com/x.js"></script>
<link href="https://fonts.googleapis.com/css2?family=Inter" rel="stylesheet">'
w "$P/src/server.js" 'app.post("/login", (req, res) => {
  console.log(req.body);
  res.cookie("sid", "x");
  const ip = req.headers["x-forwarded-for"];
  navigator.geolocation.getCurrentPosition(cb);
  localStorage.setItem("email", user.email);
  const upload = multer({ dest: "u/" });
});'
w "$P/src/sentry.js" 'Sentry.init({ integrations: [Sentry.replayIntegration()] });'
w "$P/package.json" '{"dependencies":{"stripe":"14","@sentry/browser":"7","twilio":"4"}}'
before=$(tree_sum "$P")
run "$P" privacy
contract "privacy heavy"
has "privacy-data: email evidence file:line" "WARN|privacy-data|email address: collected or stored at "
has "email evidence cites schema.prisma:3" "prisma/schema.prisma:3"
has "email evidence cites the HTML form" "src/form.html:1"
has "privacy-data: phone" "phone number: collected"
has "privacy-data: date of birth" "date of birth: collected"
has "privacy-data: government id" "government id: collected"
has "privacy-data: payment card" "payment card data: collected"
has "privacy-data: geolocation API cites server.js:5" "geolocation API: found at src/server.js:5"
has "privacy-data: IP capture" "IP address capture: found at src/server.js:4"
has "privacy-data: upload cites server.js:7" "file/photo upload: found at src/server.js:7"
has "privacy-trackers: Google Analytics" "WARN|privacy-trackers|Google Analytics / gtag at src/track.html:1"
has "privacy-trackers: Meta Pixel" "Meta (Facebook) Pixel at src/track.html:2"
has "privacy-trackers: Hotjar" "Hotjar at src/track.html:3"
has "privacy-trackers: Google Fonts" "Google Fonts loaded from Google servers"
has "privacy-trackers: Sentry session replay" "Sentry session replay at src/sentry.js:1"
has "privacy-cookies cites server.js:3" "WARN|privacy-cookies|cookies set/handled at src/server.js:3"
has "privacy-storage cites server.js:6" "WARN|privacy-storage|personal data written to browser storage at src/server.js:6"
has "privacy-logging cites server.js:2" "WARN|privacy-logging|request bodies or emails may be logged at src/server.js:2"
has "privacy-processors lists Stripe with file:line" "Stripe (package.json:1)"
has "privacy-processors lists Twilio" "Twilio (package.json:1)"
has "privacy-policy WARN when data present" "WARN|privacy-policy|no privacy policy"
has "privacy-consent WARN with trackers" "WARN|privacy-consent|"
has "privacy-delete WARN" "WARN|privacy-delete|"
has "privacy-export WARN" "WARN|privacy-export|"
has "privacy-retention WARN says OWNER TO DECIDE" "OWNER TO DECIDE"
has "privacy-subprocessors WARN" "WARN|privacy-subprocessors|"
has "not-legal-advice line always present" "SKIP|privacy-legal|not legal advice"
[ "$before" = "$(tree_sum "$P")" ] && ok "privacy.sh never modifies the project" || bad "privacy.sh never modifies the project"

echo "== privacy.sh: clean app and false-positive guards"
P="$SANDBOX/p2"
w "$P/src/app.js" 'const user = getUser();
sendMail(user.email);
function greet(name) { return "hi " + name; }
console.log("server started");'
w "$P/node_modules/x/track.js" 'gtag("config"); fbq("init"); email: String'
w "$P/tests/a.test.js" 'const email = req.body.email; gtag("x");'
w "$P/package.json" '{"dependencies":{"express":"4"}}'
run "$P" privacy
contract "privacy clean"
has "clean app: privacy-data PASS" "PASS|privacy-data|no personal-data fields"
has "clean app: privacy-trackers PASS (node_modules and tests ignored)" "PASS|privacy-trackers|"
has "clean app: privacy-policy SKIP" "SKIP|privacy-policy|"
has "clean app: privacy-consent SKIP" "SKIP|privacy-consent|"
has "clean app: privacy-delete SKIP" "SKIP|privacy-delete|"
hasnt "user.email alone is not flagged" "WARN|privacy-data"
hasnt "plain console.log of a string is not flagged" "WARN|privacy-logging"

echo "== privacy.sh: app with the artifacts in place"
P="$SANDBOX/p3"
w "$P/src/form.html" '<input type="email" name="email">'
w "$P/src/analytics.html" '<script src="https://plausible.io/js/script.js"></script>'
w "$P/public/privacy-policy.html" '<h1>Privacy</h1>'
w "$P/src/CookieBanner.jsx" 'export default function CookieBanner() { return null; }'
w "$P/src/routes.js" 'router.delete("/api/users/me", deleteAccount);
router.get("/api/me/data-export", exportUserData);'
w "$P/DATA.md" 'We apply a retention period: logs are purged after 30 days. Subprocessors: Plausible (DPA signed).'
run "$P" privacy
contract "privacy complete"
has "policy file found -> PASS" "PASS|privacy-policy|privacy policy file/page found: public/privacy-policy.html"
has "consent banner found -> PASS" "PASS|privacy-consent|consent/cookie-banner code found at src/CookieBanner.jsx:1"
has "delete route found -> PASS" "PASS|privacy-delete|"
has "export route found -> PASS" "PASS|privacy-export|"
has "retention wording found -> PASS" "PASS|privacy-retention|"
has "subprocessor mention found -> PASS" "PASS|privacy-subprocessors|"
hasnt "no WARN for delete when present" "WARN|privacy-delete"

echo "== privacy.sh: empty dir"
mkdir -p "$SANDBOX/p4"
run "$SANDBOX/p4" privacy
contract "privacy empty"
has "empty dir: SKIP with reason" "SKIP|privacy-data|no source files"

echo "== docs.sh: no README"
D="$SANDBOX/d0"
w "$D/index.js" 'console.log(1)'
run "$D" docs
contract "docs no README"
has "missing README is FAIL" "FAIL|docs-readme|no README"
has "missing LICENSE is WARN" "WARN|docs-license|no LICENSE"

echo "== docs.sh: well-documented project"
D="$SANDBOX/d1"
cat > "$SANDBOX/readme1" <<'E'
# Garden Tracker

A small web app that tracks the plants in your garden and reminds you when to water them.

## Setup
Run `npm install`, then `cp .env.example .env` and fill in the values.

## Run
`npm run dev` for development, `npm start` for production, `make build` to bundle,
or `python tools/seed.py` to load sample data.

## Test
`npm test`

## Configuration
Set API_KEY and DATABASE_URL (see .env.example). SENTRY_DSN is optional.

## Deploy
Push to the main branch; Vercel deploys it.
E
mkdir -p "$D"; cp "$SANDBOX/readme1" "$D/README.md"
w "$D/package.json" '{
  "name": "garden",
  "license": "MIT",
  "scripts": {
    "dev": "vite",
    "start": "node server.js",
    "test": "vitest"
  }
}'
w "$D/Makefile" 'build:
	echo build'
w "$D/tools/seed.py" 'import os
print(os.environ["DATABASE_URL"])'
w "$D/server.js" 'const k = process.env.API_KEY;
const dsn = process.env.SENTRY_DSN;
if (process.env.NODE_ENV === "production") {}
const u = import.meta.env.VITE_API_URL;'
w "$D/.env.example" 'API_KEY=
DATABASE_URL=
# VITE_API_URL=
'
w "$D/LICENSE" 'MIT License'
w "$D/tests/a.test.js" 'test("x", () => {})'
run "$D" docs
contract "docs good"
has "README exists PASS" "PASS|docs-readme|README.md exists"
has "what-it-is PASS" "PASS|docs-readme-what|README.md:3"
has "install heading PASS" "PASS|docs-readme-install|"
has "run heading PASS" "PASS|docs-readme-run|"
has "test PASS" "PASS|docs-readme-test|"
has "env PASS" "PASS|docs-readme-env|"
has "deploy PASS" "PASS|docs-readme-deploy|"
has "commands that exist -> PASS" "PASS|docs-commands|"
hasnt "no FAIL for existing npm/make/python commands" "FAIL|docs-commands"
hasnt "documented env var is not FAIL (API_KEY)" "FAIL|docs-env|API_KEY"
hasnt "var documented only in README is not FAIL (SENTRY_DSN)" "FAIL|docs-env|SENTRY_DSN"
hasnt "NODE_ENV is ignored" "NODE_ENV"
hasnt "import.meta.env var documented (commented) in .env.example is not FAIL" "FAIL|docs-env|VITE_API_URL"
has "env all documented -> PASS" "PASS|docs-env|"
has "LICENSE present -> PASS" "PASS|docs-license|LICENSE present"
has "tests documented -> PASS" "PASS|docs-tests|"

echo "== docs.sh: README lies about commands"
D="$SANDBOX/d2"
cat > "$SANDBOX/readme2" <<'E'
# Thing

This project does a thing that is described here in a full sentence for readers.

## Install
`npm install`

## Run
`npm run serve`
`make deploy`
`python scripts/run.py`
`npm run build`
`npm start`
`docker compose up`
Copy `.env.sample` to `.env`.
E
mkdir -p "$D"; cp "$SANDBOX/readme2" "$D/README.md"
w "$D/package.json" '{"scripts":{"build":"tsc"}}'
w "$D/Makefile" 'all:
	echo hi'
run "$D" docs
contract "docs lying README"
has "npm run serve mismatch cites README.md:9" "FAIL|docs-commands|README.md:9 says 'npm run serve' but package.json has no 'serve' script"
has "make deploy mismatch cites README.md:10" "README.md:10 says 'make deploy' but Makefile has no 'deploy' target"
has "python file mismatch cites README.md:11" "README.md:11 says 'python scripts/run.py' but scripts/run.py does not exist"
has "npm start without script" "README.md:13 says 'npm start' but package.json has no 'start' script"
has "docker compose without file" "README.md:14 says docker compose but there is no compose file"
has "missing .env.sample" "README.md:15 refers to .env.sample but that file does not exist"
hasnt "npm run build exists so not flagged" "'npm run build'"
has "no test section and no tests -> SKIP" "SKIP|docs-readme-test|"

echo "== docs.sh: env-var sync"
D="$SANDBOX/d3"
w "$D/README.md" '# Env demo

A demo project used to test environment variable synchronisation checks here.

## Install
npm install'
w "$D/package.json" '{"scripts":{"start":"node a.js"}}'
w "$D/a.js" 'const a = process.env.USED_UNDOC;
const b = process.env["BRACKET_VAR"];
const { DESTR_ONE, DESTR_TWO: two = 5 } = process.env;
const c = import.meta.env.VITE_UNDOC;'
w "$D/b.py" 'import os
x = os.environ["PY_BRACKET"]
y = os.environ.get("PY_GET")
z = os.getenv("PY_GETENV")'
w "$D/c.rb" 'v = ENV["RB_VAR"]
w = ENV.fetch("RB_FETCH")'
w "$D/d.php" '<?php $x = getenv("PHP_VAR"); $y = env("LARAVEL_VAR");'
w "$D/.env.example" 'DOCUMENTED_UNUSED=1
STALE_TYPO=
IN_COMPOSE=
'
w "$D/docker-compose.yml" 'services:
  web:
    environment:
      - IN_COMPOSE=${IN_COMPOSE}'
run "$D" docs
contract "docs env"
has "process.env.X undocumented FAIL with file:line" "FAIL|docs-env|USED_UNDOC is read at a.js:1"
has "process.env[X] found" "FAIL|docs-env|BRACKET_VAR is read at a.js:2"
has "destructured var found" "FAIL|docs-env|DESTR_ONE is read at a.js:3"
has "destructured with alias/default found" "FAIL|docs-env|DESTR_TWO is read at a.js:3"
has "import.meta.env found" "FAIL|docs-env|VITE_UNDOC is read at a.js:4"
has "os.environ[] found" "FAIL|docs-env|PY_BRACKET is read at b.py:2"
has "os.environ.get found" "FAIL|docs-env|PY_GET is read at b.py:3"
has "os.getenv found" "FAIL|docs-env|PY_GETENV is read at b.py:4"
has "ENV[] found" "FAIL|docs-env|RB_VAR is read at c.rb:1"
has "ENV.fetch found" "FAIL|docs-env|RB_FETCH is read at c.rb:2"
has "PHP getenv found" "FAIL|docs-env|PHP_VAR is read at d.php:1"
has "PHP env() found" "FAIL|docs-env|LARAVEL_VAR is read at d.php:1"
has "documented but unused WARN with location" "WARN|docs-env-unused|STALE_TYPO documented at .env.example:2"
has "unused WARN also for the first one" "WARN|docs-env-unused|DOCUMENTED_UNUSED documented at .env.example:1"
hasnt "var used by docker-compose is not reported unused" "IN_COMPOSE documented"

echo "== docs.sh: env example missing entirely"
D="$SANDBOX/d4"
w "$D/README.md" '# X

Some long enough description of the project goes right here in the text.'
w "$D/a.js" 'process.env.SECRET_KEY'
run "$D" docs
has "no .env.example + used var -> FAIL" "FAIL|docs-env|SECRET_KEY is read at a.js:1"
has "no .env.example -> WARN docs-env-example" "WARN|docs-env-example|"

echo "== docs.sh: license via package.json only, tests undocumented"
D="$SANDBOX/d5"
w "$D/README.md" '# Y

A long enough description of the project so the what-it-is check passes fine.'
w "$D/package.json" '{"license":"MIT","scripts":{"test":"jest"}}'
run "$D" docs
has "license field only -> WARN citing package.json:1" "WARN|docs-license|no LICENSE file, only a license field at package.json:1"
has "tests exist but README silent -> WARN" "WARN|docs-tests|tests exist"
mkdir -p "$SANDBOX/d6"
run "$SANDBOX/d6" docs
contract "docs empty dir"

echo "== a11y.sh: problems are found"
A="$SANDBOX/a1"
cat > "$SANDBOX/a1.html" <<'E'
<html>
<head><meta name="viewport" content="width=device-width, user-scalable=no"></head>
<body>
<img src="a.png">
<input type="text" name="q">
<input id="orphan" placeholder="x">
<button><svg></svg></button>
<a href="/x"><i class="icon"></i></a>
<div onclick="go()">x</div>
<div style="width: 800px">wide</div>
</body>
</html>
E
mkdir -p "$A"; cp "$SANDBOX/a1.html" "$A/index.html"
cat > "$A/App.jsx" <<'E'
import React from 'react';
export default () => (
  <div>
    <img src={a} />
    <input
      type="text"
      onChange={(e) => set(e.target.value)}
    />
    <button onClick={() => x()}><Icon /></button>
    <span onClick={() => x()}>y</span>
  </div>
);
E
w "$A/s.css" 'button:focus { outline: none; }'
before=$(tree_sum "$A")
run "$A" a11y
contract "a11y problems"
has "img without alt (html) cites index.html:4" "a11y-img-alt|<img> has no alt attribute (use alt=\"\" if purely decorative) at index.html:4"
has "img without alt (jsx, self-closing) cites App.jsx:4" "at App.jsx:4"
has "input with no label (html) cites index.html:5" "no aria-label at index.html:5"
has "multi-line JSX input reported at its start line" "no aria-label at App.jsx:5"
has "input with orphan id" "id=orphan has no <label for>"
has "icon-only button (html)" "WARN|a11y-icon-buttons|<button> has no text and no aria-label (icon-only) at index.html:7"
has "icon-only button (jsx)" "at App.jsx:9"
has "icon-only link" "<a> has no text and no aria-label (icon-only) at index.html:8"
has "missing html lang" "WARN|a11y-html-lang|<html> has no lang attribute at index.html:1"
has "user-scalable=no" "WARN|a11y-zoom|pinch-zoom is blocked at index.html:2"
has "div click without role/tabIndex/keyboard" "<div> has a click handler but no role, tabIndex, keyboard handler"
has "span click in jsx" "<span> has a click handler"
has "outline none without replacement" "WARN|a11y-focus|'button:focus' removes the focus outline"
has "fixed width >= 600 with no media queries" "WARN|a11y-fixed-width|fixed width >= 600px at index.html:10"
has "tap targets are declared not knowable" "SKIP|a11y-tap-targets|tap-target size"
has "tap-target line points at axe/Lighthouse" "axe/Lighthouse"
[ "$before" = "$(tree_sum "$A")" ] && ok "a11y.sh never modifies the project" || bad "a11y.sh never modifies the project"

echo "== a11y.sh: false-positive guards"
A="$SANDBOX/a2"
mkdir -p "$A"
cat > "$A/index.html" <<'E'
<!doctype html>
<html lang="en">
<head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body>
<img src="deco.png" alt="">
<img src="logo.png" alt="Company logo">
<label>Name <input type="text" name="n"></label>
<label for="em">Email</label>
<input id="em" type="email">
<input type="text" aria-label="Search">
<input type="hidden" name="csrf">
<input type="submit" value="Go">
<select id="sel"></select><label for="sel">Pick</label>
<button>Save</button>
<button aria-label="Close"><svg></svg></button>
<button><svg></svg><span class="sr-only">Menu</span></button>
<a href="/x">Home</a>
<div onclick="go()" role="button" tabindex="0" onkeydown="go()">ok</div>
<div style="max-width: 1200px">fine</div>
</body>
</html>
E
w "$A/style.css" 'button:focus { outline: none; box-shadow: 0 0 0 3px blue; }
.card { width: 100%; }
@media (max-width: 600px) { .x { display: none; } }'
w "$A/Form.jsx" 'import React from "react";
export const F = () => (
  <form>
    <input
      type="text"
      aria-label="Query"
      onChange={(e) => go(e)}
    />
    <img src={u} alt="" />
    <div onClick={() => go()} role="button" tabIndex={0} onKeyDown={() => go()}>ok</div>
    <a href="/y"><img src="i.svg" alt="Settings" /></a>
    <button>{label}</button>
    <input {...props} />
  </form>
);'
run "$A" a11y
contract "a11y clean"
hasnt "alt=\"\" decorative image is fine" "a11y-img-alt|<img>"
hasnt "input inside <label> is fine" "WARN|a11y-form-labels"
hasnt "icon button with aria-label/sr-only text is fine" "WARN|a11y-icon-buttons"
hasnt "html lang present is fine" "WARN|a11y-html-lang"
hasnt "viewport present is fine" "WARN|a11y-viewport"
hasnt "no zoom block" "WARN|a11y-zoom"
hasnt "div with role+tabindex+key handler is fine" "WARN|a11y-clickable"
hasnt "max-width 1200px is not a fixed-width problem" "WARN|a11y-fixed-width"
hasnt "outline none with focus replacement is fine" "WARN|a11y-focus"
has "img check ran and passed" "PASS|a11y-img-alt|"
has "form-labels passed" "PASS|a11y-form-labels|"
has "clickable passed" "PASS|a11y-clickable|"

echo "== a11y.sh: viewport / responsive / focus edge cases"
A="$SANDBOX/a3"
w "$A/index.html" '<html lang="en"><head><title>x</title></head><body><p>hi</p></body></html>'
run "$A" a11y
has "missing viewport meta in HTML entrypoint" "WARN|a11y-viewport|no <meta name=viewport> in this HTML entrypoint"
A="$SANDBOX/a4"
w "$A/index.html" '<html lang="en"><head><meta name="viewport" content="width=device-width, maximum-scale=1"></head><body></body></html>'
run "$A" a11y
has "maximum-scale=1 blocks zoom" "WARN|a11y-zoom|pinch-zoom is blocked at index.html:1"
A="$SANDBOX/a5"
w "$A/index.html" '<html lang="en"><head><meta name="viewport" content="width=device-width"></head><body></body></html>'
w "$A/s.css" '.wrap { width: 900px; }
@media (max-width: 700px) { .wrap { width: 100%; } }'
run "$A" a11y
has "fixed width but media queries exist -> PASS" "PASS|a11y-fixed-width|fixed widths >= 600px at s.css:1"
A="$SANDBOX/a6"
w "$A/Btn.jsx" 'import React from "react";
export const B = () => <button className="outline-none">x</button>;'
run "$A" a11y
has "tailwind outline-none without ring" "WARN|a11y-focus|outline removed inline/utility"
A="$SANDBOX/a7"
w "$A/Btn.jsx" 'import React from "react";
export const B = () => <button className="outline-none focus:ring-2">x</button>;'
run "$A" a11y
hasnt "tailwind outline-none with focus ring is fine" "WARN|a11y-focus"
A="$SANDBOX/a8"
w "$A/app/layout.tsx" 'export default function L({children}) { return (<html lang="en"><body>{children}</body></html>); }'
run "$A" a11y
hasnt "Next app layout gets its viewport automatically" "WARN|a11y-viewport"
mkdir -p "$SANDBOX/a9"
run "$SANDBOX/a9" a11y
contract "a11y empty dir"
has "no markup files -> SKIP with reason" "SKIP|a11y-img-alt|no HTML"

echo "== a11y-browser.mjs: SKIP path (no playwright/axe, nothing installed)"
if command -v node >/dev/null 2>&1; then
  mkdir -p "$SANDBOX/b1"
  bout=$(cd "$SANDBOX/b1" && node "$ROOT/scripts/a11y-browser.mjs" http://127.0.0.1:9 2>&1); brc=$?
  [ "$brc" -eq 0 ] && ok "a11y-browser.mjs exits 0 when unavailable" || bad "a11y-browser.mjs exits 0 (got $brc)"
  case "$bout" in SKIP\|a11y-axe\|*) ok "a11y-browser.mjs prints a SKIP line";; *) bad "a11y-browser.mjs SKIP line: [$bout]";; esac
  bout=$(cd "$SANDBOX/b1" && node "$ROOT/scripts/a11y-browser.mjs" 2>&1); brc=$?
  [ "$brc" -eq 0 ] && case "$bout" in *"no URL"*) ok "a11y-browser.mjs without URL: SKIP exit 0";; *) bad "no-URL message";; esac || bad "no-URL exit"
  [ ! -d "$SANDBOX/b1/node_modules" ] && ok "a11y-browser.mjs installs nothing" || bad "installs nothing"
  grep -q 'never installs\|not installing\|Never installs' "$ROOT/scripts/a11y-browser.mjs" && ok "a11y-browser.mjs documents no-install rule" || bad "no-install doc"
else
  ok "node not available: a11y-browser tests skipped"
fi

echo "== lockin.sh"
L="$SANDBOX/l1"
w "$L/package.json" '{"scripts":{"dev":"vite"},"dependencies":{"firebase":"10","@vercel/kv":"1"}}'
w "$L/src/lib/db.js" 'import { getFirestore } from "firebase/firestore";'
w "$L/src/pages/a.js" 'import { getAuth } from "firebase/auth";'
w "$L/src/components/b.js" 'import { doc } from "firebase/firestore";'
w "$L/src/api/kv.js" 'import { kv } from "@vercel/kv";'
w "$L/firebase.json" '{}'
w "$L/.replit" 'run = "npm start"'
w "$L/.cursorrules" 'be nice'
before=$(tree_sum "$L")
run "$L" lockin
contract "lockin"
has "Firebase detected with file count and evidence" "PASS|lockin-vendors|info: Firebase used in 3 source file(s): src/components/b.js:1"
has "Firebase dependency line cited" "dependency at package.json:1"
has "Firebase platform file listed" "platform files: firebase.json"
has "Vercel-only API detected" "info: Vercel-only APIs used in 1 source file(s): src/api/kv.js:1"
has "Replit config detected" "info: Replit"
has "Cursor config detected" "info: Cursor / Windsurf editor config"
has "informational tone on vendor lines" "a trade-off, not necessarily a problem"
has "SDK spread across folders -> thin wrapper WARN" "WARN|lockin-coupling|Firebase SDK is imported directly in 3 files across 3 folders"
has "wrapper advice wording" "consider a thin wrapper"
hasnt "single-file Vercel usage is not a coupling WARN" "Vercel-only APIs SDK is imported"
has "plain npm run dev PASS" "PASS|lockin-run|'npm run dev' defined at package.json:1"
has "no Dockerfile and no docs -> exit-path WARN" "WARN|lockin-exit-path|no Dockerfile"
[ "$before" = "$(tree_sum "$L")" ] && ok "lockin.sh never modifies the project" || bad "lockin.sh never modifies the project"

L="$SANDBOX/l2"
w "$L/package.json" '{"scripts":{"start":"node server.js"},"dependencies":{"@supabase/supabase-js":"2"}}'
w "$L/lib/supabase.js" 'import { createClient } from "@supabase/supabase-js";'
w "$L/lib/users.js" 'import { createClient } from "@supabase/supabase-js";'
w "$L/Dockerfile" 'FROM node:20'
run "$L" lockin
contract "lockin contained"
has "Supabase info line" "info: Supabase used in 2 source file(s)"
has "contained SDK -> coupling PASS" "PASS|lockin-coupling|"
hasnt "no coupling WARN when in one folder" "WARN|lockin-coupling"
has "npm start PASS" "PASS|lockin-run|plain 'npm start'"
has "Dockerfile is an exit path" "PASS|lockin-exit-path|container definition found: Dockerfile"

L="$SANDBOX/l3"
w "$L/package.json" '{"scripts":{"dev":"vercel dev"},"dependencies":{}}'
w "$L/README.md" '# App
## Install
npm install'
w "$L/index.js" 'console.log(1)'
run "$L" lockin
has "vendor CLI in dev script -> WARN" "WARN|lockin-run|start/dev script needs a vendor CLI at package.json:1"
has "documented setup counts as exit path" "PASS|lockin-exit-path|no Dockerfile, but README.md:"
has "no vendor SDK -> PASS" "PASS|lockin-vendors|no platform-specific"
L="$SANDBOX/l4"
mkdir -p "$L"
run "$L" lockin
contract "lockin empty dir"
L="$SANDBOX/l5"
w "$L/main.py" 'import firebase_admin
print(1)'
run "$L" lockin
has "python firebase_admin detected" "info: Firebase used in 1 source file(s): main.py:1"

echo "== templates, agent, skills"
fm() {  # fm <file> <key>
  awk -v k="$2" 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1 && index($0,k":")==1{sub("^"k":[ ]*","");print;exit}' "$1"
}
for f in templates/DATA.md skills/mogger-privacy/SKILL.md skills/mogger-docs/SKILL.md agents/docs-writer.md scripts/a11y-browser.mjs; do
  [ -f "$ROOT/$f" ] && ok "exists: $f" || bad "exists: $f"
done
for f in skills/mogger-privacy/SKILL.md skills/mogger-docs/SKILL.md agents/docs-writer.md; do
  [ -n "$(fm "$ROOT/$f" name)" ] && ok "frontmatter name: $f" || bad "frontmatter name: $f"
  [ -n "$(fm "$ROOT/$f" description)" ] && ok "frontmatter description: $f" || bad "frontmatter description: $f"
done
[ "$(fm "$ROOT/skills/mogger-privacy/SKILL.md" name)" = "mogger-privacy" ] && ok "privacy skill name matches dir" || bad "privacy skill name"
[ "$(fm "$ROOT/skills/mogger-docs/SKILL.md" name)" = "mogger-docs" ] && ok "docs skill name matches dir" || bad "docs skill name"
[ "$(fm "$ROOT/agents/docs-writer.md" name)" = "docs-writer" ] && ok "docs-writer name" || bad "docs-writer name"
[ "$(fm "$ROOT/agents/docs-writer.md" model)" = "sonnet" ] && ok "docs-writer is sonnet" || bad "docs-writer model"
tools=$(fm "$ROOT/agents/docs-writer.md" tools)
[ "$tools" = "Read, Grep, Glob, Write, Bash" ] && ok "docs-writer tools" || bad "docs-writer tools: [$tools]"
grep -q 'TODO(owner)' "$ROOT/agents/docs-writer.md" && ok "docs-writer uses TODO(owner) for unknowns" || bad "TODO(owner)"
grep -q 'log-savings.sh' "$ROOT/agents/docs-writer.md" && ok "docs-writer has savings-log section" || bad "savings-log section"
grep -q 'docs.sh' "$ROOT/agents/docs-writer.md" && ok "docs-writer is grounded in docs.sh output" || bad "docs.sh grounding"
grep -qi 'read-only' "$ROOT/agents/docs-writer.md" && ok "docs-writer Bash is read-only" || bad "read-only rule"
grep -q 'OWNER TO DECIDE' "$ROOT/templates/DATA.md" && ok "DATA.md uses OWNER TO DECIDE" || bad "DATA.md OWNER TO DECIDE"
grep -qi 'not legal advice' "$ROOT/templates/DATA.md" && ok "DATA.md says not legal advice" || bad "DATA.md legal line"
grep -qi 'not legal advice' "$ROOT/skills/mogger-privacy/SKILL.md" && ok "privacy skill says not legal advice" || bad "skill legal line"
for col in "Where collected" "Where stored" "Why" "Who receives it" "How long kept" "How deleted"; do
  grep -qF "$col" "$ROOT/templates/DATA.md" && ok "DATA.md column: $col" || bad "DATA.md column: $col"
done
grep -qi 'never invent' "$ROOT/skills/mogger-privacy/SKILL.md" && ok "privacy skill forbids invented retention/legal basis" || bad "never invent"
grep -q 'privacy.sh' "$ROOT/skills/mogger-privacy/SKILL.md" && ok "privacy skill names the script" || bad "skill names script"
grep -q 'docs-writer' "$ROOT/skills/mogger-docs/SKILL.md" && ok "docs skill dispatches docs-writer" || bad "docs skill dispatch"
grep -q 'hooks' "$ROOT/hooks/hooks.json" 2>/dev/null && ! grep -q -E 'privacy[.]sh|docs[.]sh|a11y[.]sh|lockin[.]sh' "$ROOT/hooks/hooks.json" && ok "no hooks registered for report-only checks" || bad "hooks.json references checks"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# Tests for the app-security layer: scripts/checks/security.sh, dep-audit.sh,
# hooks/scripts/check-risky-code.sh, check-diy-payments.sh.
# Run: bash tests/security.test.sh   (self-contained temp sandbox, no network)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
SEC="$ROOT/scripts/checks/security.sh"
DEP="$ROOT/scripts/checks/dep-audit.sh"
PASS=0; FAIL=0

SANDBOX=$(mktemp -d)
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT
export TMPDIR="$SANDBOX/tmp"; mkdir -p "$TMPDIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset MOGGER_CHECK_RISKY MOGGER_CHECK_PAYMENTS MOGGER_AUDIT_FIXTURE MOGGER_AUDIT_TIMEOUT MOGGER_SECURITY_MAX

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want '$1', got '$2')"; fi; }

# ---------- sandbox helpers ----------
P="$SANDBOX/p"; mkdir -p "$P"
newp() { rm -rf "$P/$1"; mkdir -p "$P/$1"; }
w() {  # w <proj> <relpath> <content...>   (writes lines, one per extra arg)
  local proj="$1" rel="$2"; shift 2
  mkdir -p "$P/$proj/$(dirname "$rel")"
  : > "$P/$proj/$rel"
  local l; for l in "$@"; do printf '%s\n' "$l" >> "$P/$proj/$rel"; done
}
scan() { bash "$SEC" "$P/$1" 2>&1; }
# has <output> <LEVEL> <id> [substring]
has() {
  local o="$1" lvl="$2" id="$3" sub="${4:-}" desc="$5" l found=1
  while IFS= read -r l; do
    case "$l" in "$lvl|$id|"*) if [ -z "$sub" ]; then found=0; else case "$l" in *"$sub"*) found=0;; esac; fi;; esac
  done <<EOT
$o
EOT
  if [ $found -eq 0 ]; then ok "$desc"; else bad "$desc (no $lvl|$id|*$sub* in output)"; fi
}
lacks() {  # lacks <output> <LEVEL> <id> <desc>
  local o="$1" lvl="$2" id="$3" desc="$4" l found=1
  while IFS= read -r l; do case "$l" in "$lvl|$id|"*) found=0;; esac; done <<EOT
$o
EOT
  if [ $found -ne 0 ]; then ok "$desc"; else bad "$desc (unexpected $lvl|$id| line)"; fi
}

# Fake credentials assembled at runtime.
AWS="AKIA""IOSFODNN7QWERTYU"

echo "== security.sh: secrets"
newp s1
w s1 .env.local 'NEXT_PUBLIC_STRIPE_SECRET_KEY=abc'
O=$(scan s1)
has "$O" FAIL secrets-public-env ".env.local:1" "NEXT_PUBLIC_*SECRET* is FAIL with file:line"
newp s2
w s2 src/api.ts 'const a = 1;' 'const k = import.meta.env.VITE_OPENAI_API_KEY;'
O=$(scan s2); has "$O" FAIL secrets-public-env "src/api.ts:2" "VITE_OPENAI_API_KEY is FAIL"
newp s3
w s3 .env.example 'NEXT_PUBLIC_API_URL=x' 'NEXT_PUBLIC_SUPABASE_ANON_KEY=x' 'NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=x' 'VITE_KEYBOARD_LAYOUT=us' 'NEXT_PUBLIC_FIREBASE_API_KEY=x'
O=$(scan s3); has "$O" PASS secrets-public-env "" "public-safe names (URL/anon/publishable/keyboard/firebase) pass"
lacks "$O" FAIL secrets-public-env "no FAIL for public-safe names"; lacks "$O" WARN secrets-public-env "no WARN for public-safe names"
newp s4
w s4 src/cfg.js 'const k = process.env.REACT_APP_API_KEY;'
O=$(scan s4); has "$O" WARN secrets-public-env "heuristic" "generic REACT_APP_API_KEY is WARN (heuristic)"
newp s5
w s5 src/components/Pay.tsx '"use client"' 'const s = process.env.STRIPE_SECRET_KEY;'
O=$(scan s5); has "$O" FAIL secrets-client-server-var "src/components/Pay.tsx:2" "server secret in use-client file is FAIL"
newp s6
w s6 lib/stripe.ts 'export const s = process.env.STRIPE_SECRET_KEY;'
O=$(scan s6); has "$O" PASS secrets-client-server-var "" "secret in server file is fine"
newp s7
w s7 src/components/Card.tsx 'const s = process.env.STRIPE_SECRET_KEY;'
O=$(scan s7); has "$O" WARN secrets-client-server-var "server component" "secret in components/ (no use client) is WARN"
newp s8
w s8 public/app.html '<script>var k = process.env.OPENAI_API_KEY;</script>'
O=$(scan s8); has "$O" FAIL secrets-client-server-var "public/app.html:1" "server secret in public html is FAIL"
newp s9
w s9 components/A.tsx '"use client"' 'const u = process.env.NEXT_PUBLIC_API_URL; const e = process.env.NODE_ENV;'
O=$(scan s9); has "$O" PASS secrets-client-server-var "" "NEXT_PUBLIC_ and NODE_ENV in client are fine"
newp s10
w s10 src/aws.js "const key = '$AWS';"
O=$(scan s10); has "$O" FAIL secrets-literal "src/aws.js:1" "AWS key literal is FAIL"
case "$O" in *"$AWS"*) bad "full key leaked into output";; *) ok "scan never prints the full key";; esac
newp s11
w s11 src/k.js "const k = 'sk-ant-your-key-here-xxxxxxxxxxxxxxxxxxxx';"
w s11 src/c.html '<div class="task-management-dashboard-layout-wrapper-container">x</div>'
O=$(scan s11); has "$O" PASS secrets-literal "" "placeholder key and long css class are not secrets"
newp s12
w s12 src/a.ts "// const key = '$AWS'"
O=$(scan s12); has "$O" PASS secrets-literal "" "key in a comment is ignored"

echo "== security.sh: input validation"
newp v1
w v1 server.js 'app.post("/x", (req, res) => { const n = req.body.name; res.json({n}); });'
O=$(scan v1); has "$O" WARN input-validation "server.js:1" "req.body with no schema lib is WARN"
has "$O" WARN input-validation "heuristic" "input-validation says heuristic"
newp v2
w v2 server.js 'app.post("/x", (req, res) => { const n = req.body.name; res.json({n}); });'
w v2 package.json '{"dependencies":{"zod":"^3.0.0"}}'
O=$(scan v2); has "$O" PASS input-validation "zod" "zod in package.json passes"
newp v3
w v3 lib.js 'export const add = (a, b) => a + b;'
O=$(scan v3); has "$O" PASS input-validation "" "no request handling passes"
newp v4
w v4 app.py 'data = request.get_json()'
w v4 requirements.txt 'flask==3.0.0' 'pydantic==2.5.0'
O=$(scan v4); has "$O" PASS input-validation "pydantic" "pydantic in requirements passes"
newp v5
w v5 app.py 'data = request.get_json()'
O=$(scan v5); has "$O" WARN input-validation "app.py:1" "flask request.get_json with no lib is WARN"

echo "== security.sh: auth"
newp a1
w a1 server.js "app.get('/users/:id', (req, res) => { res.json(db.users); });"
O=$(scan a1); has "$O" WARN auth-routes "server.js:1" "route with no auth anywhere is WARN"
has "$O" WARN auth-routes "heuristic" "auth-routes says heuristic"
newp a2
w a2 server.js "import { getServerSession } from 'next-auth';" "app.get('/users/:id', (req, res) => { res.json(db.users); });"
O=$(scan a2); has "$O" PASS auth-routes "" "next-auth in project passes"
newp a3
w a3 server.js "app.get('/users/:id', (req, res) => { res.json(db.users); });"
w a3 middleware.ts 'export function middleware(req) {}'
O=$(scan a3); has "$O" PASS auth-routes "middleware.ts" "middleware.ts file counts as an auth signal"
newp a4
w a4 lib.js 'export const x = 1;'
O=$(scan a4); has "$O" SKIP auth-routes "no route handlers" "no routes is SKIP"
newp a5
w a5 server.js "app.get('/health', (req, res) => res.send('ok'));"
O=$(scan a5); has "$O" WARN auth-routes "server.js" "route in server.js still WARN even if health (file-level, path not name)"
newp a5b
w a5b app/api/health/route.ts 'export async function GET(req: NextRequest) { return NextResponse.json({ok:true}); }'
O=$(scan a5b); lacks "$O" WARN auth-routes "health route file is exempt"
newp a6
w a6 app/api/items/route.ts 'export async function GET(req: NextRequest) { return NextResponse.json(await db.items()); }'
O=$(scan a6); has "$O" WARN auth-routes "app/api/items/route.ts:1" "Next route.ts with no auth is WARN"
newp a7
w a7 src/api/client.ts 'export const get = (u) => fetch(u).then(r => r.json());'
O=$(scan a7); has "$O" SKIP auth-routes "" "client fetch helper in src/api is not a route"
newp r1
w r1 supabase/migrations/001.sql 'create table public.todos (' '  id int,' '  user_id uuid' ');'
O=$(scan r1); has "$O" FAIL auth-rls "supabase/migrations/001.sql:1" "supabase table without RLS is FAIL"
newp r2
w r2 supabase/migrations/001.sql 'create table public.todos (id int);' 'alter table public.todos enable row level security;'
O=$(scan r2); has "$O" PASS auth-rls "" "table with RLS passes"
newp r3
w r3 supabase/migrations/001.sql 'CREATE TABLE IF NOT EXISTS notes (id int);' 'CREATE TABLE users (id int);' 'ALTER TABLE users ENABLE ROW LEVEL SECURITY;'
O=$(scan r3); has "$O" FAIL auth-rls "'notes'" "only the table lacking RLS is named"
lacks "$O" PASS auth-rls "no PASS when one table lacks RLS"
newp r4
w r4 db/schema.sql 'create table x (id int);'
O=$(scan r4); has "$O" SKIP auth-rls "no supabase" "non-supabase SQL is SKIP"
newp f1
w f1 firestore.rules 'service cloud.firestore {' '  match /{d=**} { allow read, write: if true; }' '}'
O=$(scan f1); has "$O" FAIL auth-firebase-rules "firestore.rules:2" "firebase allow read, write: if true is FAIL"
newp f2
w f2 firestore.rules 'match /u/{id} { allow read, write: if request.auth.uid == id; }'
O=$(scan f2); has "$O" PASS auth-firebase-rules "" "auth-scoped firebase rules pass"
newp f3
w f3 firestore.rules 'match /{d=**} { allow read, write: if request.time < timestamp.date(2030, 1, 1); }'
O=$(scan f3); has "$O" WARN auth-firebase-rules "test mode" "firebase test-mode rule is WARN"
newp i1
w i1 routes/post.js 'const p = await Post.findById(req.params.id);'
O=$(scan i1); has "$O" WARN auth-idor "routes/post.js:1" "findById(req.params.id) with no owner is WARN"
newp i2
w i2 routes/post.js 'const p = await Post.findOne({ _id: x });' 'const q = await Post.findById(req.params.id); if (q.userId !== req.user.id) return;'
O=$(scan i2); has "$O" PASS auth-idor "" "owner check in file suppresses idor warning"
newp i3
w i3 app/x.ts 'const r = await prisma.post.findUnique({ where: { id: params.id } });'
O=$(scan i3); has "$O" WARN auth-idor "app/x.ts:1" "prisma findUnique by params.id is WARN"

echo "== security.sh: injection"
newp j1
w j1 db.js 'const r = await db.query(`SELECT * FROM users WHERE id = ${req.query.id}`);'
O=$(scan j1); has "$O" FAIL inject-sql "db.js:1" "template SQL with req.query is FAIL"
newp j2
w j2 db.py 'cur.execute(f"SELECT * FROM t WHERE name = {request.args[\"n\"]}")'
O=$(scan j2); has "$O" FAIL inject-sql "db.py:1" "python f-string SQL with request.args is FAIL"
newp j3
w j3 db.js 'db.query("SELECT * FROM t WHERE id = " + req.params.id);'
O=$(scan j3); has "$O" FAIL inject-sql "db.js:1" "SQL concatenation with req.params is FAIL"
newp j4
w j4 db.js 'db.query("SELECT * FROM t WHERE id = $1", [req.params.id]);' 'db.query("select * from t where id = ?", [req.query.id]);' 'sequelize.query("select * from t where id = :id", { replacements: { id: req.params.id } });' 'cur.execute("SELECT * FROM t WHERE id = %s", (request.args["id"],))'
O=$(scan j4); lacks "$O" FAIL inject-sql "parameterized queries are never FAIL"; lacks "$O" WARN inject-sql "parameterized queries are never WARN"
newp j5
w j5 db.js '// const q = `select * from t where id = ${req.query.id}`' '# "SELECT * FROM t WHERE id = " + request.args'
O=$(scan j5); has "$O" PASS inject-sql "" "commented-out SQL is ignored"
newp j6
w j6 db.js 'const t = "Please select all items from the list";' 'const u = `hello ${req.query.name}`;'
O=$(scan j6); lacks "$O" FAIL inject-sql "prose with 'select ... from' and unrelated template is fine"
newp j7
w j7 db.js 'await pool.query(`SELECT * FROM ${table} WHERE a = 1`);'
O=$(scan j7); has "$O" WARN inject-sql "heuristic" "interpolated query() is WARN heuristic"
newp x1
w x1 A.tsx 'return <div dangerouslySetInnerHTML={{ __html: userHtml }} />;'
O=$(scan x1); has "$O" WARN inject-xss "A.tsx:1" "dangerouslySetInnerHTML with variable is WARN"
newp x2
w x2 A.tsx 'return <div dangerouslySetInnerHTML={{ __html: "<b>hi</b>" }} />;'
O=$(scan x2); has "$O" PASS inject-xss "" "dangerouslySetInnerHTML with literal passes"
newp x3
w x3 A.tsx "import DOMPurify from 'dompurify';" 'return <div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(h) }} />;'
O=$(scan x3); has "$O" PASS inject-xss "" "sanitized innerHTML passes"
newp x4
w x4 a.js 'el.innerHTML = value;' "el.innerHTML = '';" 'el.textContent = value;'
O=$(scan x4); has "$O" WARN inject-xss "a.js:1" "innerHTML = value is WARN"
case "$O" in *"a.js:2"*) bad "empty-string innerHTML flagged";; *) ok "innerHTML = '' and textContent not flagged";; esac
newp e1
w e1 a.js 'const r = eval(userInput);'
O=$(scan e1); has "$O" WARN inject-eval "a.js:1" "eval(variable) is WARN"
newp e2
w e2 a.js 'const r = eval(req.body.code);'
O=$(scan e2); has "$O" FAIL inject-eval "a.js:1" "eval(req.body.code) is FAIL"
newp e3
w e3 a.js 'const msg = "never call eval(x) on input";' "const r = eval('1+1');" 'const m = /a/.exec(s);' 'const f = obj.eval(x);' '// eval(x)'
w e3 a.py 'import ast' 'v = ast.literal_eval(s)'
O=$(scan e3); has "$O" PASS inject-eval "" "eval in strings/comments/literals/methods/literal_eval is fine"
newp e4
w e4 a.py 'subprocess.run(cmd, shell=True)'
O=$(scan e4); has "$O" WARN inject-eval "a.py:1" "shell=True is WARN"
newp e5
w e5 a.py 'subprocess.run(["ls", "-l"])'
O=$(scan e5); has "$O" PASS inject-eval "" "list-form subprocess is fine"
newp e6
w e6 a.py 'os.system(f"rm -rf {path}")'
O=$(scan e6); has "$O" WARN inject-eval "a.py:1" "os.system f-string is WARN"
newp e7
w e7 a.js 'const f = new Function(code);'
O=$(scan e7); has "$O" WARN inject-eval "a.js:1" "new Function(variable) is WARN"

echo "== security.sh: config"
newp c1
w c1 app.js "app.use(cors({ origin: '*', credentials: true }));"
O=$(scan c1); has "$O" FAIL config-cors "app.js:1" "CORS * + credentials is FAIL"
newp c2
w c2 app.js "app.use(cors({ origin: '*' }));"
O=$(scan c2); has "$O" PASS config-cors "" "CORS * without credentials passes"
newp c3
w c3 app.js "app.use(cors({ origin: 'https://a.com', credentials: true }));"
O=$(scan c3); has "$O" PASS config-cors "" "specific origin + credentials passes"
newp c4
w c4 app.py 'CORS(app, origins=["*"], supports_credentials=True)'
O=$(scan c4); has "$O" FAIL config-cors "app.py:1" "flask-cors * + supports_credentials is FAIL"
newp t1
w t1 a.py 'requests.get(u, verify=False)'
O=$(scan t1); has "$O" FAIL config-tls "a.py:1" "verify=False is FAIL"
newp t2
w t2 a.js 'const agent = new https.Agent({ rejectUnauthorized: false });'
O=$(scan t2); has "$O" FAIL config-tls "a.js:1" "rejectUnauthorized false is FAIL"
newp t3
w t3 .env 'NODE_TLS_REJECT_UNAUTHORIZED=0'
O=$(scan t3); has "$O" FAIL config-tls ".env:1" "NODE_TLS_REJECT_UNAUTHORIZED=0 is FAIL"
newp t4
w t4 a.py 'requests.get("https://localhost:8443", verify=False)' '# verify=False' 'requests.get(u, verify=True)'
O=$(scan t4); has "$O" PASS config-tls "" "localhost, comment and verify=True are fine"
newp d1
w d1 settings.py 'DEBUG = True'
O=$(scan d1); has "$O" WARN config-debug "settings.py:1" "DEBUG = True is WARN"
newp d2
w d2 settings_prod.py 'DEBUG = True'
O=$(scan d2); has "$O" FAIL config-debug "settings_prod.py:1" "DEBUG = True in a prod-named file is FAIL"
newp d3
w d3 settings.py 'DEBUG = False' 'debug_toolbar = True'
O=$(scan d3); has "$O" PASS config-debug "" "DEBUG = False passes"
newp k1
w k1 auth.js 'const t = jwt.sign(payload, "supersecret123");'
O=$(scan k1); has "$O" FAIL config-jwt "auth.js:1" "jwt.sign with literal secret is FAIL"
case "$O" in *supersecret123*) bad "JWT secret leaked in output";; *) ok "JWT secret value not printed";; esac
newp k2
w k2 auth.js 'const t = jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: "1h" });'
O=$(scan k2); has "$O" PASS config-jwt "" "jwt secret from env passes"
newp k3
w k3 auth.js 'const secret = process.env.JWT_SECRET || "dev-secret";'
O=$(scan k3); has "$O" FAIL config-jwt "auth.js:1" "JWT_SECRET || literal fallback is FAIL"
newp q1
w q1 a.js "res.cookie('session', token);"
O=$(scan q1); has "$O" WARN config-cookies "a.js:1" "session cookie without flags is WARN"
newp q2
w q2 a.js "res.cookie('session', token, {" "  httpOnly: true," "  secure: true," "});"
O=$(scan q2); has "$O" PASS config-cookies "" "cookie with httpOnly+secure passes"
newp q3
w q3 a.js "res.cookie('theme', 'dark');"
O=$(scan q3); has "$O" PASS config-cookies "" "non-session cookie is fine"

# git tracking
newp g1
( cd "$P/g1" && git init -q . && printf 'K=1\n' > .env && printf 'K=\n' > .env.example && git add -A && git commit -q -m i ) >/dev/null 2>&1
O=$(scan g1); has "$O" FAIL config-env-tracked ".env" "tracked .env is FAIL"
case "$O" in *"tracked by git (.env.example"*) bad ".env.example flagged";; *) ok ".env.example tracked is fine";; esac
newp g2
( cd "$P/g2" && git init -q . && printf 'K=1\n' > .env && printf '.env\n' > .gitignore && git add .gitignore && git commit -q -m i ) >/dev/null 2>&1
O=$(scan g2); has "$O" PASS config-env-tracked "" "untracked ignored .env passes"
newp g3
w g3 .env 'K=1'
O=$(cd "$P/g3" && GIT_CEILING_DIRECTORIES="$SANDBOX" bash "$SEC" . 2>&1); has "$O" SKIP config-env-tracked "not a git" "non-git dir is SKIP"

echo "== security.sh: payments"
newp y1
w y1 pay.js 'console.log("card", cardNumber);'
O=$(scan y1); has "$O" FAIL pay-card-data "pay.js:1" "logging cardNumber is FAIL"
newp y2
w y2 pay.js "const el = elements.create('cardNumber');" '<label>CVV</label>'
O=$(scan y2); has "$O" PASS pay-card-data "" "Stripe elements cardNumber and CVV label are fine"
newp y3
w y3 luhn.js 'function luhnCheck(n) { return true; }'
O=$(scan y3); has "$O" FAIL pay-luhn "luhn.js:1" "Luhn function is FAIL"
newp y4
w y4 prisma/schema.prisma 'model Card {' '  id String @id' '  cvv String' '}'
O=$(scan y4); has "$O" FAIL pay-card-data "prisma/schema.prisma:3" "model with cvv column is FAIL"
newp y5
w y5 prisma/schema.prisma 'model Card {' '  id String @id' '  last4 String' '  exp_month Int' '  exp_year Int' '}'
O=$(scan y5); has "$O" PASS pay-card-data "" "model with last4+expiry only is fine"
newp y6
w y6 api/webhook.ts "import Stripe from 'stripe';" 'const event = JSON.parse(body);' "if (event.type === 'checkout.session.completed') { fulfil(event); }"
O=$(scan y6); has "$O" WARN pay-webhook "api/webhook.ts:3" "unsigned Stripe webhook is WARN"
newp y7
w y7 api/webhook.ts "import Stripe from 'stripe';" 'const event = stripe.webhooks.constructEvent(body, sig, secret);' "if (event.type === 'checkout.session.completed') { fulfil(event); }"
O=$(scan y7); has "$O" PASS pay-webhook "" "constructEvent webhook passes"

echo "== security.sh: contract and hygiene"
newp z1
w z1 node_modules/x/index.js "const k = '$AWS'; eval(userInput);"
w z1 dist/app.js "const k = '$AWS';"
w z1 tests/a.test.js 'db.query("SELECT * FROM t WHERE id = " + req.params.id);'
O=$(scan z1); has "$O" PASS secrets-literal "" "node_modules/dist are skipped"
lacks "$O" FAIL inject-sql "test files are skipped"
newp z2
w z2 a.js 'const x = 1;'
O=$(scan z2)
BADLINES=0; while IFS= read -r l; do case "$l" in PASS\|*\|*|WARN\|*\|*|FAIL\|*\|*|SKIP\|*\|*) ;; *) BADLINES=$((BADLINES+1));; esac; done <<EOT
$O
EOT
check 0 "$BADLINES" "every output line is LEVEL|id|message"
for id in secrets-public-env secrets-client-server-var secrets-literal input-validation auth-routes auth-rls auth-firebase-rules auth-idor inject-sql inject-xss inject-eval config-cors config-tls config-debug config-jwt config-cookies config-env-tracked pay-card-data pay-luhn pay-webhook; do
  case "$O" in *"PASS|$id|"*|*"SKIP|$id|"*) ;; *) bad "clean project prints PASS/SKIP for $id";; esac
done
ok "clean project checked all ids for PASS/SKIP"
case "$O" in *FAIL\|*|*WARN\|*) bad "clean project has no findings";; *) ok "clean project has no FAIL/WARN";; esac
bash "$SEC" "$P/z2" >/dev/null 2>&1; check 0 $? "exits 0"
bash "$SEC" "$SANDBOX/nope" >"$SANDBOX/o" 2>&1; check 0 $? "missing dir exits 0"
grep -q '^SKIP|' "$SANDBOX/o" && ok "missing dir is SKIP" || bad "missing dir is SKIP"
newp z3
w z3 db.js 'db.query("SELECT * FROM t WHERE id = " + req.params.id);'
BEFORE=$(cd "$P/z3" && find . -type f | sort | tr '\n' ' ')$(cat "$P/z3/db.js" | cksum)
bash "$SEC" "$P/z3" >/dev/null 2>&1
AFTER=$(cd "$P/z3" && find . -type f | sort | tr '\n' ' ')$(cat "$P/z3/db.js" | cksum)
check "$BEFORE" "$AFTER" "scan does not modify the project"
newp z4
for n in 1 2 3 4 5 6 7 8; do w z4 "s$n.js" 'db.query("SELECT * FROM t WHERE id = " + req.params.id);'; done
O=$(scan z4)
case "$O" in *"and 3 more"*) ok "findings are capped with an 'and N more' line";; *) bad "cap line missing";; esac
S=$(date +%s); bash "$SEC" "$P/z4" >/dev/null 2>&1; E=$(date +%s)
[ $((E-S)) -lt 30 ] && ok "scan finishes well under 30s" || bad "scan too slow"

echo "== dep-audit.sh"
dep() { bash "$DEP" "$P/$1" 2>&1; }
fx() { printf '%s' "$2" > "$SANDBOX/fx.$1.json"; }
fx npm '{"vulnerabilities":{"lodash":{"severity":"critical"},"express":{"severity":"high"},"minimist":{"severity":"high"},"ms":{"severity":"low"}},"metadata":{}}'
fx clean '{"vulnerabilities":{},"metadata":{}}'
fx mod '{"vulnerabilities":{"ms":{"severity":"moderate"}}}'
fx pnpm '{"advisories":{"1":{"module_name":"axios","severity":"high"},"2":{"module_name":"qs","severity":"moderate"}}}'
fx pip '{"dependencies":[{"name":"flask","version":"1.0","vulns":[{"id":"PYSEC-1"}]},{"name":"requests","version":"2.0","vulns":[]}]}'
fx cargo '{"vulnerabilities":{"list":[{"advisory":{"id":"RUSTSEC-1"},"package":{"name":"time","version":"0.1"}}]}}'
fx osv '{"results":[{"packages":[{"package":{"name":"gin"},"vulnerabilities":[{"id":"GO-1","database_specific":{"severity":"HIGH"}}]}]}]}'
fx err '{"error":{"code":"ENOTFOUND","summary":"request to https://registry.npmjs.org failed, reason: getaddrinfo ENOTFOUND"}}'
fx bad 'this is not json'
newp da
w da package.json '{' '  "dependencies": {' '    "lodash": "^4.0.0"' '  }' '}'
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.npm.json" dep da)
has "$O" FAIL dep-audit "1 critical, 2 high, 0 moderate, 1 low" "npm fixture counts by severity"
has "$O" FAIL dep-audit "lodash(critical, package.json:3)" "top package named with package.json:line evidence"
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.clean.json" dep da); has "$O" PASS dep-audit "no known" "clean fixture is PASS"
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.mod.json" dep da); has "$O" WARN dep-audit "1 moderate" "moderate-only is WARN not FAIL"
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.pnpm.json" dep da); has "$O" FAIL dep-audit "axios(high" "pnpm advisories shape parsed"
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.pip.json" dep da); has "$O" WARN dep-audit "flask" "pip-audit shape parsed (flask only, no severity)"
case "$O" in *requests\(*) bad "clean pip package listed";; *) ok "pip-audit package without vulns not listed";; esac
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.cargo.json" dep da); has "$O" WARN dep-audit "time(" "cargo-audit shape parsed"
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.osv.json" dep da); has "$O" FAIL dep-audit "gin(high" "osv-scanner shape parsed with severity"
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.err.json" dep da); has "$O" SKIP dep-audit "ENOTFOUND" "npm error JSON becomes SKIP with reason"
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.bad.json" dep da); has "$O" SKIP dep-audit "not JSON" "non-JSON output is SKIP with reason"
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/none.json" dep da); has "$O" SKIP dep-audit "not found" "missing fixture file is SKIP"
MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.npm.json" bash "$DEP" "$P/da" >/dev/null 2>&1; check 0 $? "dep-audit exits 0 with findings"

newp db
w db package.json '{' '  "name": "a",' '  "description": "",' '  "dependencies": {' '    "react": "latest",' '    "left-pad": "1.0.0",' '    "any": "*"' '  },' '  "devDependencies": { "x": "1" }' '}'
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.clean.json" dep db)
has "$O" WARN dep-lockfile "package.json:1" "package.json without lockfile is WARN"
has "$O" WARN dep-pinned "package.json:5" "react: latest flagged at its line"
has "$O" WARN dep-pinned "package.json:7" "'*' version flagged at its line"
case "$O" in *"package.json:3"*|*"left-pad"*) bad "empty description / pinned version flagged";; *) ok "empty description and exact pin not flagged";; esac
newp dc
w dc package.json '{"dependencies":{"a":"^1.0.0"}}'
w dc package-lock.json '{}'
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.clean.json" dep dc)
has "$O" PASS dep-lockfile "" "lockfile present is PASS"
has "$O" PASS dep-pinned "" "no latest/* is PASS"
newp dd
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.clean.json" dep dd); has "$O" SKIP dep-lockfile "no package.json" "no manifests is SKIP"
newp de
w de Cargo.toml '[package]' 'name = "x"' '[dependencies]' 'serde = "*"'
O=$(MOGGER_AUDIT_FIXTURE="$SANDBOX/fx.clean.json" dep de)
has "$O" WARN dep-lockfile "Cargo.toml:1" "Cargo.toml without Cargo.lock is WARN"
has "$O" WARN dep-pinned "Cargo.toml:4" "crate version * flagged"

# fake tools on PATH (no real network)
FAKEBIN="$SANDBOX/fakebin"; mkdir -p "$FAKEBIN"
newp df
w df package.json '{"dependencies":{"lodash":"^4.0.0"}}'
w df package-lock.json '{}'
printf '#!/bin/sh\ncat "%s"\nexit 1\n' "$SANDBOX/fx.npm.json" > "$FAKEBIN/npm"; chmod +x "$FAKEBIN/npm"
O=$(PATH="$FAKEBIN:$PATH" dep df); has "$O" FAIL dep-audit-npm "1 critical" "runs npm audit and parses JSON despite nonzero exit"
printf '#!/bin/sh\ncat "%s"\nexit 1\n' "$SANDBOX/fx.err.json" > "$FAKEBIN/npm"
O=$(PATH="$FAKEBIN:$PATH" dep df); has "$O" SKIP dep-audit-npm "ENOTFOUND" "npm network error is SKIP with reason"
printf '#!/bin/sh\necho "npm ERR! offline" >&2\nexit 1\n' > "$FAKEBIN/npm"
O=$(PATH="$FAKEBIN:$PATH" dep df); has "$O" SKIP dep-audit-npm "npm ERR! offline" "empty output surfaces stderr reason"
printf '#!/bin/sh\nsleep 6\n' > "$FAKEBIN/npm"
S=$(date +%s); O=$(PATH="$FAKEBIN:$PATH" MOGGER_AUDIT_TIMEOUT=1 dep df); E=$(date +%s)
has "$O" SKIP dep-audit-npm "timed out after 1s" "hung tool is killed and SKIPped"
[ $((E-S)) -lt 5 ] && ok "timeout returns promptly" || bad "timeout took $((E-S))s"
rm -f "$FAKEBIN/npm"
# tool absent: PATH with only basic utilities
SHIM="$SANDBOX/shim"; mkdir -p "$SHIM"
for c in bash sh sed grep awk find head tail tr cut sort mktemp wc cat rm sleep python3 xargs ls dirname git kill touch; do
  p=$(command -v "$c" 2>/dev/null) && [ -n "$p" ] && ln -sf "$p" "$SHIM/$c"
done
O=$(PATH="$SHIM" bash "$DEP" "$P/df" 2>&1); has "$O" SKIP dep-audit-npm "npm is not installed" "missing npm is SKIP with reason"
newp dg
w dg requirements.txt 'flask==3.0.0'
O=$(PATH="$SHIM" bash "$DEP" "$P/dg" 2>&1); has "$O" SKIP dep-audit-python "pip-audit is not installed" "missing pip-audit is SKIP with reason"
newp dh
w dh package.json '{"dependencies":{"a":"1"}}'
O=$(PATH="$SHIM" bash "$DEP" "$P/dh" 2>&1); has "$O" SKIP dep-audit-npm "no lockfile" "npm audit without lockfile is SKIP"
case "$(cd "$P/dh" && find . -type f | sort | tr '\n' ' ')" in "./package.json ") ok "dep-audit never creates files in the project";; *) bad "dep-audit created files";; esac

echo "== hooks"
jstr() {
  if command -v jq >/dev/null 2>&1; then printf '%s' "$1" | jq -Rs .
  else printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'; fi
}
wj() { printf '{"tool_name":"Write","tool_input":{"file_path":%s,"content":"x"}}' "$(jstr "$1")"; }
HP="$SANDBOX/hp"; mkdir -p "$HP"
hf() {  # hf <relpath> <lines...>  -> absolute path
  local rel="$1"; shift; mkdir -p "$HP/$(dirname "$rel")"; : > "$HP/$rel"
  local l; for l in "$@"; do printf '%s\n' "$l" >> "$HP/$rel"; done
  printf '%s' "$HP/$rel"
}
expect() {  # expect <code> <hook> <file> <desc> [env...]
  local want="$1" hook="$2" file="$3" desc="$4" got
  printf '%s' "$(wj "$file")" | bash "$H/$hook" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then ok "$hook: $desc"; else bad "$hook: $desc (want $want, got $got)"; fi
}
R=check-risky-code.sh
expect 2 $R "$(hf a/.env.example 'NEXT_PUBLIC_OPENAI_API_KEY=')" "blocks NEXT_PUBLIC_OPENAI_API_KEY in .env.example"
expect 2 $R "$(hf a/x.ts 'const s = process.env.NEXT_PUBLIC_STRIPE_SECRET_KEY;')" "blocks NEXT_PUBLIC_*_SECRET_KEY"
expect 2 $R "$(hf a/y.ts 'const p = import.meta.env.VITE_DATABASE_PASSWORD;')" "blocks VITE_DATABASE_PASSWORD"
expect 0 $R "$(hf a/z.ts 'const u = process.env.NEXT_PUBLIC_API_URL;')" "allows NEXT_PUBLIC_API_URL"
expect 0 $R "$(hf a/z2.ts 'const k = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;' 'const p = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY;')" "allows anon and publishable keys"
expect 0 $R "$(hf a/z3.ts 'const k = process.env.VITE_KEYBOARD_LAYOUT;' 'const a = process.env.REACT_APP_API_KEY;')" "allows keyboard and generic API_KEY (conservative)"
expect 2 $R "$(hf a/firestore.rules 'match /x { allow read, write: if true; }')" "blocks firebase allow read, write: if true"
expect 0 $R "$(hf a/ok.rules 'match /x { allow read, write: if request.auth != null; }')" "allows auth-scoped firebase rules"
expect 2 $R "$(hf a/t.py 'requests.get(u, verify=False)')" "blocks verify=False"
expect 2 $R "$(hf a/t.js 'new https.Agent({ rejectUnauthorized: false })')" "blocks rejectUnauthorized false"
expect 0 $R "$(hf a/t2.py 'requests.get("https://localhost:8000", verify=False)')" "allows verify=False against localhost"
expect 0 $R "$(hf a/t3.py '# requests.get(u, verify=False)')" "allows commented verify=False"
expect 2 $R "$(hf a/q.js 'db.query(`SELECT * FROM u WHERE id = ${req.query.id}`);')" "blocks SQL template with request data"
expect 2 $R "$(hf a/q.py 'cur.execute(f"select * from u where n = {request.args[0]}")')" "blocks python f-string SQL with request data"
expect 2 $R "$(hf a/q2.js 'db.query("SELECT * FROM u WHERE id = " + req.params.id);')" "blocks SQL concatenation with request data"
expect 0 $R "$(hf a/q3.js 'db.query("SELECT * FROM u WHERE id = $1", [req.params.id]);')" "allows parameterized query"
expect 0 $R "$(hf a/q4.js 'db.query("select * from u where id = :id", { replacements: { id: req.params.id } });')" "allows named replacements"
expect 0 $R "$(hf a/q5.js 'db.query(`SELECT * FROM ${TABLE} WHERE a = 1`);')" "allows interpolated constant (left to the scan)"
expect 2 $R "$(hf a/e.js 'const r = eval(req.body.code);')" "blocks eval(req.body...)"
expect 0 $R "$(hf a/e2.js 'const r = eval(userInput);')" "allows eval(variable) (scan-only)"
expect 0 $R "$(hf a/e3.js '// eval(req.body.code)' 'const m = "do not eval(req.body)";')" "allows comment/string mentioning eval"
expect 2 $R "$(hf a/app/C.tsx '"use client"' 'const s = process.env.STRIPE_SECRET_KEY;')" "blocks server secret in use-client file"
expect 2 $R "$(hf a/public/app.js 'const s = process.env.OPENAI_API_KEY;')" "blocks server secret in public/ js"
expect 0 $R "$(hf a/lib/server.ts 'const s = process.env.STRIPE_SECRET_KEY;')" "allows server secret in server file"
expect 0 $R "$(hf a/app/C2.tsx '"use client"' 'const u = process.env.NEXT_PUBLIC_API_URL;')" "allows public var in client file"
expect 0 $R "$(hf a/api/x.tsx '"use client"' 'const s = process.env.STRIPE_SECRET_KEY;')" "api dir is never client"
expect 0 $R "$(hf a/tests/t.test.js 'db.query("select * from u where id = " + req.query.id);')" "ignores test files"
expect 0 $R "$(hf a/README.md 'NEXT_PUBLIC_STRIPE_SECRET_KEY verify=False')" "ignores markdown"
expect 0 $R "$HP/does-not-exist.js" "fails open on missing file"
printf '%s' 'not json' | bash "$H/$R" >/dev/null 2>&1; check 0 $? "$R: fails open on bad JSON"
printf '%s' '' | bash "$H/$R" >/dev/null 2>&1; check 0 $? "$R: empty input exits 0"
printf '%s' "$(wj "$HP/a/t.py")" | MOGGER_CHECK_RISKY=off bash "$H/$R" >/dev/null 2>&1; check 0 $? "$R: MOGGER_CHECK_RISKY=off"
MSG=$(printf '%s' "$(wj "$HP/a/t.py")" | bash "$H/$R" 2>&1 >/dev/null)
case "$MSG" in *"t.py:1"*) ok "$R: message cites file:line";; *) bad "$R: message lacks file:line ($MSG)";; esac

D=check-diy-payments.sh
expect 2 $D "$(hf b/p.js 'console.log("card", cardNumber);')" "blocks logging cardNumber"
expect 2 $D "$(hf b/p2.js 'await fetch("/pay", { body: JSON.stringify({ cvv, name }) });')" "blocks sending cvv"
expect 2 $D "$(hf b/p3.py 'db.save(card_number=request.form["card_number"])')" "blocks saving card_number"
expect 2 $D "$(hf b/p4.js 'localStorage.setItem("cc", cvc);')" "blocks localStorage of cvc"
expect 2 $D "$(hf b/luhn.js 'function isLuhnValid(n) { return true; }')" "blocks Luhn implementation"
expect 2 $D "$(hf b/luhn.py 'def luhn_check(n):' '    return True')" "blocks python luhn_check"
expect 2 $D "$(hf b/schema.prisma 'model Card {' '  cvv String' '}')" "blocks prisma cvv column"
expect 2 $D "$(hf b/m.sql 'create table cards (' ' card_number varchar(16),' ' expiry date' ');')" "blocks sql card number + expiry"
expect 2 $D "$(hf b/models.py 'class Card(models.Model):' '    card_number = models.CharField()' '    exp_month = models.IntegerField()')" "blocks django card number + expiry"
expect 2 $D "$(hf b/api/stripe/webhook.ts "import Stripe from 'stripe';" 'const e = JSON.parse(await req.text());' "if (e.type === 'payment_intent.succeeded') grant(e);")" "blocks unsigned stripe webhook"
expect 0 $D "$(hf b/api/stripe/ok.ts "import Stripe from 'stripe';" 'const e = stripe.webhooks.constructEvent(body, sig, s);' "if (e.type === 'payment_intent.succeeded') grant(e);")" "allows signed webhook"
expect 0 $D "$(hf b/api/stripe/ok2.py 'import stripe' 'e = stripe.Webhook.construct_event(p, h, s)' 'if e["type"] == "invoice.paid": pay(e)')" "allows python construct_event"
expect 0 $D "$(hf b/api/other.ts "import Stripe from 'stripe';" 'const b = JSON.parse(x);')" "allows stripe file that is not an event handler"
expect 0 $D "$(hf b/el.js "const n = elements.create('cardNumber'); console.log(n);")" "allows Stripe Elements cardNumber"
expect 2 $D "$(hf b/el2.tsx 'import { CardNumberElement } from "@stripe/react-stripe-js";' 'fetch("/x", { body: cardNumber });')" "stripe import elsewhere does not excuse sending cardNumber (exemption is line-level)"
expect 0 $D "$(hf b/form.tsx '<label>Card number</label>' '<input name="cardNumber" />' 'if (!cardNumber) return;')" "allows form field and validation without store/log/send"
expect 0 $D "$(hf b/last4.prisma 'model Pm {' '  last4 String' '  exp_month Int' '  exp_year Int' '  card_number_last4 String' '}')" "allows last4 + expiry model"
expect 0 $D "$(hf b/c.js '// console.log(cardNumber)')" "allows commented code"
expect 0 $D "$(hf b/tests/x.test.js 'console.log(cardNumber)')" "ignores tests"
expect 0 $D "$(hf b/n.md 'console.log(cardNumber)')" "ignores markdown"
expect 0 $D "$HP/nofile.js" "fails open on missing file"
printf '%s' 'garbage' | bash "$H/$D" >/dev/null 2>&1; check 0 $? "$D: fails open on bad JSON"
printf '%s' "$(wj "$HP/b/p.js")" | MOGGER_CHECK_PAYMENTS=off bash "$H/$D" >/dev/null 2>&1; check 0 $? "$D: MOGGER_CHECK_PAYMENTS=off"
MSG=$(printf '%s' "$(wj "$HP/b/p.js")" | bash "$H/$D" 2>&1 >/dev/null)
case "$MSG" in *"never handle card numbers"*"p.js:1"*|*"p.js:1"*"never handle card numbers"*) ok "$D: message has guidance and file:line";; *) bad "$D: message ($MSG)";; esac

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

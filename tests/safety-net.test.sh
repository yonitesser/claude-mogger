#!/usr/bin/env bash
# Tests for checkpoint/rewind, secret guard, and package verification.
# Run: bash tests/safety-net.test.sh   (no network: registries are a local
# python3 http.server or unreachable ports; skipped parts are reported.)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
REWIND="$ROOT/scripts/mogger-rewind.sh"
PASS=0; FAIL=0

SANDBOX=$(mktemp -d)
SRV_PID=""
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$SANDBOX"; }
trap cleanup EXIT
export TMPDIR="$SANDBOX/tmp"; mkdir -p "$TMPDIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
unset MOGGER_SECRET_GUARD MOGGER_VERIFY_PACKAGES MOGGER_CHECKPOINT MOGGER_MAX_CHECKPOINTS MOGGER_CHECKPOINT_INTERVAL
REPO="$SANDBOX/repo"; mkdir -p "$REPO"; cd "$REPO"
git init -q -b main . 2>/dev/null || { git init -q .; git checkout -q -b main; }
echo base > a.txt; git add a.txt; git commit -q -m init

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want '$1', got '$2')"; fi; }

jstr() {  # JSON-encode a string
  if command -v jq >/dev/null 2>&1; then printf '%s' "$1" | jq -Rs .
  else printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'; fi
}
write_json() { printf '{"tool_name":"Write","tool_input":{"file_path":%s,"content":%s}}' "$(jstr "$1")" "$(jstr "$2")"; }
edit_json()  { printf '{"tool_name":"Edit","tool_input":{"file_path":%s,"old_string":"x","new_string":%s}}' "$(jstr "$1")" "$(jstr "$2")"; }
bash_json()  { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jstr "$1")"; }

expect() {  # expect <code> <hook> <json> <desc>
  local want="$1" hook="$2" json="$3" desc="$4" got
  printf '%s' "$json" | bash "$H/$hook" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then ok "$hook: $desc"; else bad "$hook: $desc (want $want, got $got)"; fi
}

# Fake credentials assembled at runtime so this file holds no scannable secret.
AWS="AKIA""IOSFODNN7QWERTYU"
GHP="ghp_""$(printf 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8')"
GHPAT="github_pat_""11ABCDEFG0abcdefghijkl_mnopqrstuvwxyz0123456789"
ANT="sk-ant-""api03-abcdefghijklmnop1234567890"
OAI="sk-""proj1234567890abcdefghijklmnopqrstuvwxyz12"
STRIPE="sk_live_""51Habcdefghijklmnop1234"
SLACK="xoxb-""1234567890-abcdefghij"
PK="-----BEGIN RSA ""PRIVATE KEY-----"

echo "== secret-guard.sh (Write/Edit)"
expect 2 secret-guard.sh "$(write_json app.py "key = \"$AWS\"")"              "blocks AWS key"
expect 2 secret-guard.sh "$(write_json app.py "t = '$GHP'")"                  "blocks GitHub ghp_ token"
expect 2 secret-guard.sh "$(write_json app.py "t = '$GHPAT'")"                "blocks GitHub fine-grained PAT"
expect 2 secret-guard.sh "$(write_json app.py "k = '$ANT'")"                  "blocks Anthropic key"
expect 2 secret-guard.sh "$(write_json app.py "k = '$OAI'")"                  "blocks OpenAI key"
expect 2 secret-guard.sh "$(write_json app.py "k = '$STRIPE'")"               "blocks Stripe live key"
expect 2 secret-guard.sh "$(write_json app.py "t = '$SLACK'")"                "blocks Slack token"
expect 2 secret-guard.sh "$(write_json k.pem "$PK
abc")"                                                                        "blocks private key block"
expect 2 secret-guard.sh "$(write_json cfg.py 'password = "hunter2hunter2hunter2"')" "blocks generic password literal"
expect 2 secret-guard.sh "$(write_json cfg.json '{"api_key": "abcd1234efgh5678ijkl"}')" "blocks JSON api_key literal"
expect 2 secret-guard.sh "$(edit_json app.py "k = \"$AWS\"")"                 "Edit new_string is scanned too"
expect 2 secret-guard.sh "$(write_json .env 'FOO=bar')"                       "blocks writing .env"
expect 2 secret-guard.sh "$(write_json cfg/.env.local 'FOO=bar')"             "blocks writing .env.local (nested)"
expect 2 secret-guard.sh "$(write_json .env.production 'FOO=bar')"            "blocks writing .env.production"
expect 0 secret-guard.sh "$(write_json .env.example 'API_KEY=your-key-here')" "allows .env.example"
expect 0 secret-guard.sh "$(write_json .env.sample 'API_KEY=')"               "allows .env.sample"
expect 0 secret-guard.sh "$(write_json .env.template 'API_KEY=')"             "allows .env.template"
expect 0 secret-guard.sh "$(write_json env.py 'password = input("pw: ")')"    "allows variable named password, no literal"
expect 0 secret-guard.sh "$(write_json a.py 'def check(password, secret): return password == secret')" "allows password as identifier"
expect 0 secret-guard.sh "$(write_json a.py 'password = os.environ["DB_PASSWORD"]')" "allows os.environ"
expect 0 secret-guard.sh "$(write_json a.js 'const apiKey = process.env.API_KEY;')" "allows process.env"
expect 0 secret-guard.sh "$(write_json a.py 'api_key = "your-key-here-please-1234"')" "allows your-key-here placeholder"
expect 0 secret-guard.sh "$(write_json a.py 'api_key = "xxxxxxxxxxxxxxxxxxxx1"')"  "allows xxx placeholder"
expect 0 secret-guard.sh "$(write_json a.py 'secret = "<your-secret-value-123456>"')" "allows <...> placeholder"
expect 0 secret-guard.sh "$(write_json a.yml 'token: "${GITHUB_TOKEN_VALUE_123456}"')" "allows \${...} placeholder"
expect 0 secret-guard.sh "$(write_json a.py 'aws = "AKIAIOSFODNN7EXAMPLE"')"    "allows AWS documented EXAMPLE key"
expect 0 secret-guard.sh "$(write_json a.py 'label = "some_input_field_name"')" "allows short/no-digit literal"
expect 0 secret-guard.sh "$(write_json a.py 'password_field = "user_password_input_box"')" "allows non-credential string named password_*"
expect 0 secret-guard.sh "$(write_json README.md 'Set the sk- prefix key in your env')" "allows prose mentioning sk-"
expect 0 secret-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"x.py"}}' "allows empty content"
expect 0 secret-guard.sh 'not json'                                            "fails open on garbage input"
MOGGER_SECRET_GUARD=off bash "$H/secret-guard.sh" <<<"$(write_json .env 'A=b')" >/dev/null 2>&1
check 0 $? "secret-guard.sh: MOGGER_SECRET_GUARD=off bypasses"
msg=$(printf '%s' "$(write_json app.py "k = \"$AWS\"")" | bash "$H/secret-guard.sh" 2>&1 >/dev/null)
case "$msg" in *"$AWS"*) bad "block message leaks the full secret" ;; *) ok "block message does not echo full secret" ;; esac

echo "== secret-guard-bash.sh"
echo 'SECRET=1' > .env; echo 'X=1' > .env.example; echo 'ok' > clean.txt
expect 2 secret-guard-bash.sh "$(bash_json 'git add .env')"                   "blocks git add .env"
expect 2 secret-guard-bash.sh "$(bash_json 'git add src/a.py .env.local')"    "blocks git add .env.local among others"
expect 2 secret-guard-bash.sh "$(bash_json 'cd x && git add -f build/out.js')" "blocks git add -f"
expect 2 secret-guard-bash.sh "$(bash_json 'git add --force dist')"           "blocks git add --force"
expect 2 secret-guard-bash.sh "$(bash_json 'git add -A')"                     "blocks add -A while untracked .env exists"
expect 2 secret-guard-bash.sh "$(bash_json 'git add .')"                      "blocks add . while untracked .env exists"
expect 0 secret-guard-bash.sh "$(bash_json 'git add .env.example')"           "allows git add .env.example"
expect 0 secret-guard-bash.sh "$(bash_json 'git add clean.txt')"              "allows adding a normal file"
expect 0 secret-guard-bash.sh "$(bash_json 'git status')"                     "ignores unrelated git"
expect 0 secret-guard-bash.sh "$(bash_json 'ls -la')"                         "ignores non-git commands"
echo '.env' > .gitignore
expect 0 secret-guard-bash.sh "$(bash_json 'git add .')"                      "allows add . once .env is gitignored"
rm .env .gitignore
echo "k = \"$AWS\"" > leak.py; git add leak.py
expect 2 secret-guard-bash.sh "$(bash_json 'git commit -m wip')"              "blocks commit with staged secret"
git reset -q leak.py
echo "clean code" > ok.py; git add ok.py
expect 0 secret-guard-bash.sh "$(bash_json 'git commit -m fine')"             "allows commit with clean staged diff"
git reset -q ok.py; rm -f ok.py leak.py
echo "k = \"$AWS\"" > a.txt
expect 2 secret-guard-bash.sh "$(bash_json 'git commit -am wip')"             "blocks commit -a with secret in tracked change"
git checkout -q a.txt
expect 0 secret-guard-bash.sh "$(bash_json 'git commit -am wip')"             "allows commit -a on clean tree"
MOGGER_SECRET_GUARD=off bash "$H/secret-guard-bash.sh" <<<"$(bash_json 'git add -f x')" >/dev/null 2>&1
check 0 $? "secret-guard-bash.sh: MOGGER_SECRET_GUARD=off bypasses"
( cd "$SANDBOX" && printf '%s' "$(bash_json 'git add .env')" | bash "$H/secret-guard-bash.sh" >/dev/null 2>&1; echo $? > "$SANDBOX/rc" )
check 0 "$(cat "$SANDBOX/rc")" "secret-guard-bash.sh: fails open outside a git repo"

echo "== verify-packages.sh (parsing, no network)"
parse() { printf '%s' "$(bash_json "$1")" | MOGGER_VERIFY_MODE=parse bash "$H/verify-packages.sh" 2>/dev/null | tr '\n' ',' ; }
check "npm lodash,npm express,"       "$(parse 'npm install lodash express@4.1 --save-dev')" "npm install: names, version stripped, flags skipped"
check "npm @scope/pkg,"               "$(parse 'pnpm add @scope/pkg@^2')"                     "pnpm add scoped package"
check ""                              "$(parse 'npm install')"                                "bare npm install has no packages"
check "npm left-pad,"                 "$(parse 'yarn add left-pad')"                          "yarn add"
check ""                              "$(parse 'npm i ./local ../up github:o/r user/repo https://x.y/z.tgz')" "skips paths/URLs/shorthands"
check "pypi requests,pypi flask,"     "$(parse 'pip install requests>=2 flask[async]==3.0')"  "pip: specifiers and extras stripped"
check ""                              "$(parse 'pip install -r requirements.txt')"            "pip -r skipped"
check "pypi rich,"                    "$(parse 'pip install -r req.txt rich')"                "pip -r value consumed, rich kept"
check "pypi httpx,"                   "$(parse 'uv pip install httpx')"                       "uv pip install"
check "pypi pydantic,"                "$(parse 'uv add pydantic')"                            "uv add"
check "pypi numpy,"                   "$(parse 'python3 -m pip install numpy')"               "python -m pip install"
check "crates serde,crates tokio,"    "$(parse 'cargo add serde tokio@1 --features full')"    "cargo add: features value skipped"
check "go github.com/spf13/cobra,"    "$(parse 'go get github.com/spf13/cobra@v1.8.0')"       "go get strips version"
check ""                              "$(parse 'go get ./...')"                               "go get ./... skipped"
check "npm a,pypi b,"                 "$(parse 'npm i a && pip install b')"                   "chained commands"
check ""                              "$(parse 'echo hello world')"                           "unrelated command"
check ""                              "$(parse 'git commit -m "npm install stuff"' )"         "git message containing 'npm install' still parsed as text only"

echo "== verify-packages.sh (local stub registry)"
if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  REG="$SANDBOX/reg"
  mkdir -p "$REG/npm/@scope" "$REG/pypi/requests" "$REG/crates" "$REG/go/github.com/foo/bar/@v"
  echo '{}' > "$REG/npm/real-pkg"; echo '{}' > "$REG/npm/@scope/real"
  echo '{}' > "$REG/pypi/requests/json"; echo '{}' > "$REG/crates/serde"
  echo 'v1.0.0' > "$REG/go/github.com/foo/bar/@v/list"
  PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
  ( cd "$REG" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) &
  SRV_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/" && break; sleep 0.25
  done
  export MOGGER_NPM_REGISTRY="http://127.0.0.1:$PORT/npm" MOGGER_PYPI_URL="http://127.0.0.1:$PORT/pypi" \
         MOGGER_CRATES_URL="http://127.0.0.1:$PORT/crates" MOGGER_GOPROXY="http://127.0.0.1:$PORT/go"
  expect 0 verify-packages.sh "$(bash_json 'npm install real-pkg')"            "existing npm package allowed"
  expect 0 verify-packages.sh "$(bash_json 'npm install @scope/real@1.0.0')"   "existing scoped npm package allowed"
  expect 2 verify-packages.sh "$(bash_json 'npm install real-pkg totally-fake-pkg')" "nonexistent npm package blocked"
  expect 0 verify-packages.sh "$(bash_json 'pip install requests==2.0')"       "existing pypi package allowed"
  expect 2 verify-packages.sh "$(bash_json 'pip install requestz')"            "nonexistent pypi package blocked"
  expect 0 verify-packages.sh "$(bash_json 'cargo add serde')"                 "existing crate allowed"
  expect 2 verify-packages.sh "$(bash_json 'cargo add serde-fake-xyz')"        "nonexistent crate blocked"
  expect 0 verify-packages.sh "$(bash_json 'go get github.com/foo/bar@v1.0.0')" "existing go module allowed"
  expect 0 verify-packages.sh "$(bash_json 'go get github.com/foo/bar/sub/pkg')" "go subpackage resolves via parent module"
  expect 2 verify-packages.sh "$(bash_json 'go get github.com/nobody/nothing')" "nonexistent go module blocked"
  expect 0 verify-packages.sh "$(bash_json 'npm install fake --registry https://my.private/npm')" "custom registry skipped"
  MOGGER_VERIFY_PACKAGES=off bash "$H/verify-packages.sh" <<<"$(bash_json 'npm install totally-fake-pkg')" >/dev/null 2>&1
  check 0 $? "verify-packages.sh: MOGGER_VERIFY_PACKAGES=off bypasses"
  err=$(printf '%s' "$(bash_json 'npm install totally-fake-pkg')" | bash "$H/verify-packages.sh" 2>&1 >/dev/null)
  case "$err" in *"package 'totally-fake-pkg' does not exist on registry.npmjs.org"*) ok "verify-packages.sh: block message names package and registry" ;; *) bad "block message wrong: $err" ;; esac
else
  echo "  skip stub-registry tests (need python3 + curl)"
fi
# unreachable registry => fail open (port 1 refuses instantly)
MOGGER_NPM_REGISTRY="http://127.0.0.1:1/npm" MOGGER_PYPI_URL="http://127.0.0.1:1/pypi" \
  bash "$H/verify-packages.sh" <<<"$(bash_json 'npm install fake-thing && pip install fake-thing')" >/dev/null 2>&1
check 0 $? "verify-packages.sh: fails open when registry unreachable"

echo "== checkpoint.sh"
cd "$REPO"; git status --short | head -n0
export MOGGER_CHECKPOINT_INTERVAL=0
ncp() { git for-each-ref refs/mogger/checkpoints | wc -l | tr -d ' '; }
HEAD0=$(git rev-parse HEAD); BR0=$(git rev-parse --abbrev-ref HEAD)
echo "wip" > new.txt; echo "changed" > a.txt
git add a.txt
STAT0=$(git status --porcelain)
INDEX0=$(git ls-files -s)
expect 0 checkpoint.sh "$(write_json a.txt x)"                   "exits 0 in a repo"
check 1 "$(ncp)" "one checkpoint created"
check "$STAT0" "$(git status --porcelain)"  "working tree/index status untouched"
check "$INDEX0" "$(git ls-files -s)"        "real index untouched"
check "$HEAD0" "$(git rev-parse HEAD)"      "HEAD untouched"
check "$BR0" "$(git rev-parse --abbrev-ref HEAD)" "branch untouched"
cp1=$(git for-each-ref --format='%(refname)' refs/mogger/checkpoints)
check "wip" "$(git show "$cp1:new.txt")"     "checkpoint contains untracked file"
check "changed" "$(git show "$cp1:a.txt")"   "checkpoint contains modified file"
expect 0 checkpoint.sh "$(write_json a.txt x)"                   "second call (identical tree) exits 0"
check 1 "$(ncp)" "identical tree not re-snapshotted"
echo "more" >> new.txt
expect 0 checkpoint.sh "$(write_json a.txt x)"                   "changed tree exits 0"
check 2 "$(ncp)" "new checkpoint when tree changed (interval 0)"
MOGGER_CHECKPOINT_INTERVAL=3600 bash "$H/checkpoint.sh" <<<"$(write_json a.txt x)" >/dev/null 2>&1
echo "again" >> new.txt
MOGGER_CHECKPOINT_INTERVAL=3600 bash "$H/checkpoint.sh" <<<"$(write_json a.txt x)" >/dev/null 2>&1
check 2 "$(ncp)" "dedupe: within interval, no new checkpoint"
printf -- '- [ ] 1. First task — files: a.txt\n' > TASKS.md
MOGGER_CHECKPOINT_INTERVAL=3600 bash "$H/checkpoint.sh" <<<"$(write_json a.txt x)" >/dev/null 2>&1
n_a=$(ncp)
echo "more2" >> new.txt
MOGGER_CHECKPOINT_INTERVAL=3600 bash "$H/checkpoint.sh" <<<"$(write_json a.txt x)" >/dev/null 2>&1
check "$n_a" "$(ncp)" "same open task within interval: no new checkpoint"
printf -- '- [x] 1. First task — files: a.txt\n- [ ] 2. Second — files: b.txt\n' > TASKS.md
MOGGER_CHECKPOINT_INTERVAL=3600 bash "$H/checkpoint.sh" <<<"$(write_json a.txt x)" >/dev/null 2>&1
check "$((n_a + 1))" "$(ncp)" "first-open-task change forces a checkpoint"
rm TASKS.md
MOGGER_CHECKPOINT=off bash "$H/checkpoint.sh" <<<"$(write_json a.txt x)" >/dev/null 2>&1; echo z >> new.txt
before=$(ncp); MOGGER_CHECKPOINT=off bash "$H/checkpoint.sh" <<<"$(write_json a.txt x)" >/dev/null 2>&1
check "$before" "$(ncp)" "MOGGER_CHECKPOINT=off takes nothing"
( cd "$SANDBOX" && printf '%s' "$(write_json a.txt x)" | bash "$H/checkpoint.sh" >/dev/null 2>&1; echo $? > "$SANDBOX/rc" )
check 0 "$(cat "$SANDBOX/rc")" "exits 0 outside a git repo"
printf 'garbage' | bash "$H/checkpoint.sh" >/dev/null 2>&1; check 0 $? "exits 0 on garbage stdin"

echo "== checkpoint cap"
rm -rf "$SANDBOX/cap"; mkdir "$SANDBOX/cap"; cd "$SANDBOX/cap"; git init -q .; echo 1 > f; git add f; git commit -q -m i
for i in 1 2 3 4 5; do echo "$i" > f; MOGGER_MAX_CHECKPOINTS=3 bash "$H/checkpoint.sh" <<<"$(write_json f x)" >/dev/null 2>&1; done
check 3 "$(git for-each-ref refs/mogger/checkpoints | wc -l | tr -d ' ')" "MOGGER_MAX_CHECKPOINTS=3 keeps 3"
newest=$(git for-each-ref --sort=-refname --count=1 --format='%(refname)' refs/mogger/checkpoints)
check "5" "$(git show "$newest:f")" "cap keeps the newest, drops oldest"
rm -rf "$SANDBOX/cap"; mkdir "$SANDBOX/cap"; cd "$SANDBOX/cap"; git init -q .   # no commits at all
echo x > f; bash "$H/checkpoint.sh" <<<"$(write_json f x)" >/dev/null 2>&1
check 1 "$(git for-each-ref refs/mogger/checkpoints | wc -l | tr -d ' ')" "works in a repo with no commits"

echo "== mogger-rewind.sh"
cd "$REPO"
out=$(bash "$REWIND" list); case "$out" in *"before"*) ok "list shows checkpoints" ;; *) bad "list output: $out" ;; esac
id1=$(git for-each-ref --sort=refname --count=1 --format='%(refname)' refs/mogger/checkpoints); id1="${id1##*/}"
out=$(bash "$REWIND" show "$id1"); case "$out" in *new.txt*) ok "show lists differing files" ;; *) bad "show output: $out" ;; esac
# restore: state at checkpoint 1 had new.txt=wip, a.txt=changed
echo "garbage" > new.txt; echo "junk" > a.txt; echo "extra" > created-later.txt
out=$(bash "$REWIND" restore "$id1" 2>&1); rc=$?
check 0 "$rc" "restore exits 0"
check "wip" "$(cat new.txt)" "restore brings back checkpointed content"
check "changed" "$(cat a.txt)" "restore reverts tracked file"
[ ! -e created-later.txt ] && ok "restore removes files created since" || bad "created-later.txt survived"
case "$out" in *"previous state saved as checkpoint"*) ok "restore reports pre-restore checkpoint" ;; *) bad "restore output: $out" ;; esac
pre=$(printf '%s\n' "$out" | sed -n 's/.*saved as checkpoint \([0-9A-Za-z-]*\) .*/\1/p')
check "$HEAD0" "$(git rev-parse HEAD)" "restore leaves HEAD alone"
bash "$REWIND" restore "$pre" >/dev/null 2>&1
check "garbage" "$(cat new.txt)" "restoring the pre-restore checkpoint undoes the restore"
check "extra" "$(cat created-later.txt)" "undo brings back deleted file"
echo "keepme" > ignored.log; echo "*.log" > .gitignore
bash "$REWIND" restore "$id1" >/dev/null 2>&1
check "keepme" "$(cat ignored.log)" "restore never touches ignored files"
bash "$REWIND" restore nosuchid >/dev/null 2>&1; check 1 $? "restore of unknown id fails"
bash "$REWIND" restore >/dev/null 2>&1; check 1 $? "restore without id fails"
bash "$REWIND" bogus >/dev/null 2>&1; check 1 $? "unknown subcommand fails"
( cd "$SANDBOX" && bash "$REWIND" restore latest >/dev/null 2>&1; echo $? > "$SANDBOX/rc" )
check 1 "$(cat "$SANDBOX/rc")" "restore refuses outside a git repo"
( cd "$SANDBOX" && bash "$REWIND" list >/dev/null 2>&1; echo $? > "$SANDBOX/rc" )
check 1 "$(cat "$SANDBOX/rc")" "list refuses outside a git repo"
mkdir -p "$SANDBOX/empty" && ( cd "$SANDBOX/empty" && git init -q . && bash "$REWIND" list ) 2>&1 | grep -q "no checkpoints" && ok "list with none says so" || bad "empty list message"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

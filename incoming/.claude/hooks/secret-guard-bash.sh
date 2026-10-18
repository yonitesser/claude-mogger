#!/usr/bin/env bash
# PreToolUse — matcher: Bash
# The git side of the secret guard. Blocks:
#   - `git add` naming a .env file (except .env.example/.sample/.template)
#   - `git add -f` / `--force` (force-adding is how ignored secret files get in)
#   - `git add .` / `-A` / `-a` while an untracked, non-ignored .env file exists
#   - `git commit` when the staged diff (or, with -a, the tracked working
#     diff) adds lines matching secret-patterns.sh
#
# Fails OPEN outside a git repo or when jq/python3 are missing.
# Escape hatch: MOGGER_SECRET_GUARD=off.
source "${0%/*}/lib.sh"
source "${0%/*}/secret-patterns.sh"

[ "${MOGGER_SECRET_GUARD:-on}" = "off" ] && exit 0

INPUT=$(cat)
CMD=$(json_get "$INPUT" '.tool_input.command')
[ -z "$CMD" ] && exit 0
# A key typed into any shell command (curl header, echo > .env) is a leak too.
# Only the named key formats (ghp_, AKIA, sk-ant-...): the generic password pattern is for files.
# (named formats only, so the pre-filter is the prefix list; generic words would match every command)
case "$CMD" in *AKIA*|*gh[pousr]_*|*github_pat_*|*sk-*|*_live_*|*-----BEGIN*|*xox[abprs]-*) MAYBE=1 ;; *) MAYBE=0 ;; esac
if [ "$MAYBE" = 1 ] && FOUND=$(printf '%s\n' "$CMD" | MOGGER_SECRET_SKIP_GENERIC=1 mogger_find_secret); then
  mogger_event block "blocked a secret in a shell command"; echo "BLOCKED: this command contains what looks like a hardcoded secret: $FOUND. Read it from an environment variable instead, and rotate the credential if it was ever real." >&2
  exit 2
fi
mogger_re "$CMD" '(^|[^[:alnum:]_-])git[[:space:]]+([^;&|]*[[:space:]])?(add|commit)([[:space:]]|$)' || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

is_env_file() {  # basename check: .env, .env.local... but not the example/sample/template trio
  local b="${1##*/}"
  case "$b" in
    .env.example|.env.sample|.env.template) return 1 ;;
    .env|.env.*) return 0 ;;
  esac
  return 1
}

# Split on ; & | and newlines, look at each git add / git commit segment.
SEGS=$(printf '%s\n' "$CMD" | sed -E 's/(&&|\|\||[;&|])/\
/g')
while IFS= read -r seg; do
  case "$seg" in
    *git*add*|*git*commit*) ;;
    *) continue ;;
  esac

  if echo "$seg" | grep -qE '(^|[[:space:]])git[[:space:]]+([^;&|]*[[:space:]])?add([[:space:]]|$)'; then
    ADD_ALL=0
    for tok in $(echo "$seg" | sed -E 's/.*git[[:space:]]+([^;&|]*[[:space:]])?add//'); do
      tok="${tok%\"}"; tok="${tok#\"}"; tok="${tok%\'}"; tok="${tok#\'}"
      case "$tok" in
        -f|--force)
          mogger_event block "blocked git add -f"; echo "BLOCKED: 'git add $tok' force-adds files past .gitignore, which is how secrets get committed. Add files normally; if a file is ignored, it is ignored on purpose." >&2
          exit 2 ;;
        -A|--all|-a|.|:/) ADD_ALL=1 ;;
        -*) ;;
        *) if is_env_file "$tok"; then
             mogger_event block "blocked staging a secrets file"; echo "BLOCKED: '$tok' is a secrets file — never stage it. Add it to .gitignore, commit .env.example with placeholders instead." >&2
             exit 2
           fi ;;
      esac
    done
    if [ "$ADD_ALL" -eq 1 ]; then
      ENVS=$(git ls-files -o --exclude-standard 2>/dev/null | while IFS= read -r f; do is_env_file "$f" && echo "$f"; done)
      if [ -n "$ENVS" ]; then
        mogger_event block "blocked staging a secrets file"; echo "BLOCKED: 'git add' of everything would stage an untracked secrets file: $(echo "$ENVS" | head -n1). Add it to .gitignore first, or stage specific files by name." >&2
        exit 2
      fi
    fi
  fi

  if echo "$seg" | grep -qE '(^|[[:space:]])git[[:space:]]+([^;&|]*[[:space:]])?commit([[:space:]]|$)'; then
    DIFF=$(git diff --cached 2>/dev/null)
    if echo "$seg" | grep -qE '[[:space:]]-[a-zA-Z]*a[a-zA-Z]*([[:space:]]|$)|[[:space:]]--all([[:space:]]|$)'; then
      DIFF="$DIFF
$(git diff 2>/dev/null)"
    fi
    FOUND=$(printf '%s\n' "$DIFF" | grep -E '^\+' | grep -vE '^\+\+\+' | mogger_find_secret) && {
      mogger_event block "blocked a secret in a commit"; echo "BLOCKED: this commit would include what looks like a hardcoded secret: $FOUND. Unstage the file (git restore --staged <file>), move the value to an environment variable, and rotate the credential if it was ever real. Do not commit around this." >&2
      exit 2
    }
  fi
done <<EOF2
$SEGS
EOF2
exit 0

#!/usr/bin/env bash
# PreToolUse — matcher: Bash
# The hard stop. Blocks: pushes, merges into protected branches, PR merges,
# production deploys, and money-moving CLIs. Nothing talks its way past a
# bash script that exits 2.
#
# Tightened after review: reading a file NAMED payment_service.py is not
# spending money. Only actual billing/payment CLIs are blocked.
#
# Each part has three states (see hooks/guards.tsv, skill mogger-config):
#   MOGGER_PUSH_GUARD, MOGGER_MERGE_GUARD, MOGGER_DEPLOY_GUARD, MOGGER_MONEY_GUARD
#   on = block (default), ask = permission prompt for the human, off = allow.
#   Force pushes and pushes to a protected branch stay blocked in every state.
# Opt-out for repos whose own workflow owns releases:
#   MOGGER_ALLOW_PUSH=on  — same as MOGGER_PUSH_GUARD=off: plain pushes of feature branches.
#   Set it per-repo in .claude/settings.local.json: {"env": {"MOGGER_ALLOW_PUSH": "on"}}
source "$(dirname "$0")/lib.sh"

INPUT=$(cat)
CMD=$(json_get "$INPUT" '.tool_input.command')
[ -z "$CMD" ] && exit 0

# --- states: on = block, ask = the human gets a permission prompt, off = allow.
# MOGGER_ALLOW_PUSH=on is the old name for MOGGER_PUSH_GUARD=off. merge-guard
# has no off. Where no prompt can be shown, ask blocks.
PUSH=$(mogger_state MOGGER_PUSH_GUARD on)
[ "${MOGGER_ALLOW_PUSH:-off}" = "on" ] && [ "$PUSH" = on ] && PUSH=off
MERGE=$(mogger_state MOGGER_MERGE_GUARD on); [ "$MERGE" = off ] && MERGE=on
DEPLOY=$(mogger_state MOGGER_DEPLOY_GUARD on)
MONEY=$(mogger_state MOGGER_MONEY_GUARD on)
ASKS=""

# gate <state> <event> <block message> <ask reason>
gate() {
  case "$1" in
    off) return 0 ;;
    ask)
      if mogger_can_ask "$INPUT"; then ASKS="${ASKS:-$4}"; return 0; fi
      mogger_event block "$2"; echo "BLOCKED: $3 (Ask mode is on, but this session cannot show a prompt, so it is blocked.)" >&2
      exit 2 ;;
    *) mogger_event block "$2"; echo "BLOCKED: $3" >&2; exit 2 ;;
  esac
}

# Look at what actually runs, not the raw text: unwrap bash -c / eval / $(...),
# drop sudo/env/git -C prefixes, and ignore quoted prose (a commit message that
# mentions "git push" is not a push). Falls back to the raw line without python3.
NORM=""
if command -v python3 >/dev/null 2>&1; then
  NORM=$(printf '%s' "$CMD" | python3 "$(dirname "$0")/cmd-normalize.py" 2>/dev/null)
fi
[ -n "$NORM" ] || NORM="$CMD"

check_line() {
  local CMD="$1"
  # --- git push ---
  if echo "$CMD" | grep -qE '(^|[;&|]\s*|\s)git\s+push(\s|$)'; then
    if [ "$PUSH" = on ]; then
      mogger_event block "blocked git push"; echo "BLOCKED: git push requires human approval. Say the branch is ready and stop. Do not retry with --force or another remote." >&2
      exit 2
    fi

    # Opted in: still never force, never push a protected branch.
    PUSH_ARGS=$(echo "$CMD" | sed -E 's/.*git[[:space:]]+push//; s/[;&|].*//')
    REMOTE_SEEN=0
    REFSPECS=0
    for tok in $PUSH_ARGS; do
      case "$tok" in
        --force|--force-with-lease|--force-with-lease=*|--force-if-includes|-f|--mirror|--delete|-d|--all)
          mogger_event block "blocked a force push"; echo "BLOCKED: '$tok' is never allowed, even with MOGGER_ALLOW_PUSH=on. Push a normal feature branch instead." >&2
          exit 2 ;;
        -*) continue ;;
      esac
      if [ "$REMOTE_SEEN" -eq 0 ]; then REMOTE_SEEN=1; continue; fi
      REFSPECS=$((REFSPECS + 1))
      case "$tok" in
        +*) mogger_event block "blocked a force push"; echo "BLOCKED: '+' refspec is a force push. Not allowed, even with MOGGER_ALLOW_PUSH=on." >&2; exit 2 ;;
      esac
      DEST="${tok##*:}"
      DEST="${DEST#refs/heads/}"
      if [ "$DEST" = "HEAD" ]; then DEST=$(git_branch); fi
      if is_protected_branch "$DEST"; then
        mogger_event block "blocked push to a protected branch"; echo "BLOCKED: pushing to protected branch '$DEST' requires human approval. Open a PR instead." >&2
        exit 2
      fi
    done
    if [ "$REFSPECS" -eq 0 ]; then
      BR=$(git_branch)
      if [ -z "$BR" ] || is_protected_branch "$BR"; then
        mogger_event block "blocked git push on a protected branch"; echo "BLOCKED: bare 'git push' while on '${BR:-unknown}' requires human approval. Switch to a feature branch." >&2
        exit 2
      fi
    fi
    gate "$PUSH" "blocked git push" "git push requires human approval. Say the branch is ready and stop." "Mogger: git push. Approve only if you want this branch pushed."
  fi

  # --- git merge: only when on a protected branch (merging main INTO a feature branch is fine) ---
  if echo "$CMD" | grep -qE '(^|[;&|]\s*|\s)git\s+merge(\s|$)'; then
    BR=$(git_branch)
    if [ -z "$BR" ] || is_protected_branch "$BR"; then
      gate "$MERGE" "blocked git merge on a protected branch" "merging while on '${BR:-unknown}' requires human approval. Report the branch is ready for review instead." "Mogger: git merge while on ${BR:-an unknown branch}. Approve only if you want this merge."
    fi
  fi

  # --- PR merge ---
  if echo "$CMD" | grep -qE 'gh\s+pr\s+merge'; then
    gate "$MERGE" "blocked a PR merge" "merging a PR requires human approval. Open/update the PR and stop." "Mogger: merge a pull request. Approve only if you want it merged."
  fi

  # --- production deploys / publishes ---
  if echo "$CMD" | grep -qE '(vercel\s+.*--prod|netlify\s+deploy\s+.*--prod|npm\s+publish|pnpm\s+publish|yarn\s+npm\s+publish|cargo\s+publish|docker\s+push|kubectl\s+(apply|delete|rollout)|helm\s+(install|upgrade|uninstall)|terraform\s+(apply|destroy)|pulumi\s+(up|destroy)|railway\s+up|fly\s+deploy|firebase\s+deploy|serverless\s+deploy|wrangler\s+(deploy|publish|rollback)|sst\s+deploy|amplify\s+(push|publish)|prisma\s+(migrate\s+(deploy|reset)|db\s+(push|execute))|drizzle-kit\s+push|supabase\s+(db\s+(push|reset)|functions\s+deploy)|gh\s+(release\s+(create|delete)|repo\s+(delete|create\s+[^;&|]*--public|edit\s+[^;&|]*--visibility)|gist\s+create)|sam\s+deploy|cdk\s+deploy|gcloud\s+.*deploy|az\s+.*deployment\s+.*create)'; then
    gate "$DEPLOY" "blocked a deploy command" "production deploy/publish command. Requires human approval. Stop and report what would be deployed." "Mogger: a deploy or publish command. Approve only if you want it to go out."
  fi

  # --- money: actual CLIs that move or configure spend, not file names ---
  if echo "$CMD" | grep -qE '(^|[;&|]\s*|\s)(stripe\s+(charges|payment_intents|invoices|subscriptions|refunds|payouts|customers)\s+(create|update|delete|cancel|capture|confirm|pay|void)|aws\s+(ce|budgets|billing|cur|pricing)\s|gcloud\s+billing|az\s+(consumption|billing|costmanagement)|paypal\s|braintree\s|twilio\s+.*(buy|purchase))'; then
    gate "$MONEY" "blocked a money command" "this command moves or configures money. Requires human approval regardless of amount. Stop and describe what it would do." "Mogger: a command that moves or configures money. Approve only if you want it to run."
  fi
  return 0
}

while IFS= read -r LINE; do
  [ -n "$LINE" ] && check_line "$LINE"
done <<< "$NORM"

if [ -n "$ASKS" ]; then
  mogger_event warn "asked before a risky command"
  mogger_ask_json "$ASKS"
fi
exit 0

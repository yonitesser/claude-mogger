#!/usr/bin/env bash
# PreToolUse — matcher: Bash
# The hard stop. Blocks: pushes, merges into protected branches, PR merges,
# production deploys, and money-moving CLIs. Nothing talks its way past a
# bash script that exits 2.
#
# Tightened after review: reading a file NAMED payment_service.py is not
# spending money. Only actual billing/payment CLIs are blocked.
#
# Opt-out for repos whose own workflow owns releases:
#   MOGGER_ALLOW_PUSH=on  — allows plain pushes of feature branches.
#   Force pushes and pushes to a protected branch stay blocked regardless.
#   Set it per-repo in .claude/settings.local.json: {"env": {"MOGGER_ALLOW_PUSH": "on"}}
source "$(dirname "$0")/lib.sh"

INPUT=$(cat)
CMD=$(json_get "$INPUT" '.tool_input.command')
[ -z "$CMD" ] && exit 0

# --- git push ---
if echo "$CMD" | grep -qE '(^|[;&|]\s*|\s)git\s+push(\s|$)'; then
  if [ "${MOGGER_ALLOW_PUSH:-off}" != "on" ]; then
    echo "BLOCKED: git push requires human approval. Say the branch is ready and stop. Do not retry with --force or another remote." >&2
    exit 2
  fi

  # Opted in: still never force, never push a protected branch.
  PUSH_ARGS=$(echo "$CMD" | sed -E 's/.*git[[:space:]]+push//; s/[;&|].*//')
  REMOTE_SEEN=0
  REFSPECS=0
  for tok in $PUSH_ARGS; do
    case "$tok" in
      --force|--force-with-lease|--force-with-lease=*|--force-if-includes|-f|--mirror|--delete|-d|--all)
        echo "BLOCKED: '$tok' is never allowed, even with MOGGER_ALLOW_PUSH=on. Push a normal feature branch instead." >&2
        exit 2 ;;
      -*) continue ;;
    esac
    if [ "$REMOTE_SEEN" -eq 0 ]; then REMOTE_SEEN=1; continue; fi
    REFSPECS=$((REFSPECS + 1))
    case "$tok" in
      +*) echo "BLOCKED: '+' refspec is a force push. Not allowed, even with MOGGER_ALLOW_PUSH=on." >&2; exit 2 ;;
    esac
    DEST="${tok##*:}"
    DEST="${DEST#refs/heads/}"
    if [ "$DEST" = "HEAD" ]; then DEST=$(git_branch); fi
    if is_protected_branch "$DEST"; then
      echo "BLOCKED: pushing to protected branch '$DEST' requires human approval. Open a PR instead." >&2
      exit 2
    fi
  done
  if [ "$REFSPECS" -eq 0 ]; then
    BR=$(git_branch)
    if [ -z "$BR" ] || is_protected_branch "$BR"; then
      echo "BLOCKED: bare 'git push' while on '${BR:-unknown}' requires human approval. Switch to a feature branch." >&2
      exit 2
    fi
  fi
fi

# --- git merge: only when on a protected branch (merging main INTO a feature branch is fine) ---
if echo "$CMD" | grep -qE '(^|[;&|]\s*|\s)git\s+merge(\s|$)'; then
  BR=$(git_branch)
  if [ -z "$BR" ] || is_protected_branch "$BR"; then
    echo "BLOCKED: merging while on '${BR:-unknown}' requires human approval. Report the branch is ready for review instead." >&2
    exit 2
  fi
fi

# --- PR merge ---
if echo "$CMD" | grep -qE 'gh\s+pr\s+merge'; then
  echo "BLOCKED: merging a PR requires human approval. Open/update the PR and stop." >&2
  exit 2
fi

# --- production deploys / publishes ---
if echo "$CMD" | grep -qE '(vercel\s+.*--prod|netlify\s+deploy\s+.*--prod|npm\s+publish|pnpm\s+publish|yarn\s+npm\s+publish|cargo\s+publish|docker\s+push|kubectl\s+(apply|delete|rollout)|helm\s+(install|upgrade|uninstall)|terraform\s+(apply|destroy)|pulumi\s+(up|destroy)|railway\s+up|fly\s+deploy|firebase\s+deploy|serverless\s+deploy|sam\s+deploy|cdk\s+deploy|gcloud\s+.*deploy|az\s+.*deployment\s+.*create)'; then
  echo "BLOCKED: production deploy/publish command. Requires human approval. Stop and report what would be deployed." >&2
  exit 2
fi

# --- money: actual CLIs that move or configure spend, not file names ---
if echo "$CMD" | grep -qE '(^|[;&|]\s*|\s)(stripe\s+(charges|payment_intents|invoices|subscriptions|refunds|payouts|customers)\s+(create|update|delete|cancel|capture|confirm|pay|void)|aws\s+(ce|budgets|billing|cur|pricing)\s|gcloud\s+billing|az\s+(consumption|billing|costmanagement)|paypal\s|braintree\s|twilio\s+.*(buy|purchase))'; then
  echo "BLOCKED: this command moves or configures money. Requires human approval regardless of amount. Stop and describe what it would do." >&2
  exit 2
fi

exit 0
#!/usr/bin/env bash
# PreToolUse hook — matches: Bash
# This is the hard stop. No subagent, no Lead, no clever prompt can get
# around this. If a command matches, it blocks — every time.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# --- Merges / pushes to shared history ---
if echo "$CMD" | grep -qE '(^|\s)git\s+push(\s|$)'; then
  echo "BLOCKED: git push requires human approval. Tell the user the branch is ready and stop here. Do not retry with --force or a different remote." >&2
  exit 2
fi

if echo "$CMD" | grep -qE '(^|\s)git\s+merge(\s|$)' ; then
  echo "BLOCKED: git merge requires human approval. Report the branch is ready for review instead." >&2
  exit 2
fi

if echo "$CMD" | grep -qE 'gh\s+pr\s+merge'; then
  echo "BLOCKED: merging a PR requires human approval. Open/update the PR and stop — do not merge it." >&2
  exit 2
fi

# --- Deploys ---
if echo "$CMD" | grep -qE '(vercel\s+.*--prod|netlify\s+deploy\s+.*--prod|npm\s+publish|docker\s+push|kubectl\s+apply|terraform\s+apply|railway\s+up|fly\s+deploy|firebase\s+deploy|serverless\s+deploy)'; then
  echo "BLOCKED: this is a production deploy/publish command. Requires human approval. Stop and report what would be deployed." >&2
  exit 2
fi

# --- Money ---
if echo "$CMD" | grep -qiE '(stripe |billing|invoice|charge|payment|aws.*ce |cost-explorer|budgets)'; then
  echo "BLOCKED: this command touches money/billing. Requires human approval regardless of amount. Stop and describe what it would do." >&2
  exit 2
fi

exit 0

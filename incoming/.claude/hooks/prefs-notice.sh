#!/usr/bin/env bash
# SessionStart — no matcher. Stdout goes to Claude's context.
# First load of mogger in a project: tell Claude to show the user that guard
# preferences (on / ask / off) exist, once, and offer the mogger-config skill.
# Shown once per project (marker .claude/state/prefs-shown). Never blocks: it only
# adds a few lines of context, and the user may ignore the question.
# Silent (and no marker) where nobody can answer: headless/SDK runs, permission
# modes that skip prompts, MOGGER_HEADLESS=on. Silent when .claude/mogger.json
# already exists (the user has chosen). MOGGER_PREFS_PROMPT=off disables it.
source "$(dirname "$0")/lib.sh"
[ "${MOGGER_PREFS_PROMPT:-on}" = "off" ] && exit 0
INPUT=""; [ -t 0 ] || INPUT=$(cat 2>/dev/null)
mogger_can_ask "$INPUT" || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
[ -f .claude/state/prefs-shown ] && exit 0
[ -f .claude/mogger.json ] && exit 0
mkdir -p .claude/state 2>/dev/null && : > .claude/state/prefs-shown 2>/dev/null || exit 0
cat <<'MSG'
## mogger first run (ask once, then never again)
Before the user's task, tell them in two sentences: every mogger guard can be set to on (block), ask (they get a permission prompt) or off (allow), and safety guards warn before they go off. Then ask once with AskUserQuestion: "Keep the defaults" or "Review my guard choices". On "Review", load skill mogger-config and walk them through `list`. If no answer comes, keep the defaults and do the task. Do not ask again.
MSG
exit 0

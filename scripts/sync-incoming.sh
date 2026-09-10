#!/usr/bin/env bash
# Regenerates incoming/ (the manual-install shape) from the plugin (canonical).
# Run after changing anything in agents/, hooks/, skills/, or templates/.
# The plugin uses ${CLAUDE_PLUGIN_ROOT}; the manual shape uses .claude/hooks/.
set -e
cd "$(dirname "$0")/.."
rm -rf incoming
mkdir -p incoming/.claude/agents incoming/.claude/hooks
cp agents/*.md incoming/.claude/agents/
cp hooks/scripts/*.sh incoming/.claude/hooks/
chmod +x incoming/.claude/hooks/*.sh
cp templates/CONSTRAINTS.md templates/RUNS.md templates/STACK.md templates/pricing.json incoming/
cp scripts/savings-report.py scripts/savings-report.sh incoming/
chmod +x incoming/savings-report.sh incoming/savings-report.py
# settings.json = hooks.json with plugin paths rewritten to project-relative paths
sed 's|bash \\"${CLAUDE_PLUGIN_ROOT}\\"/hooks/scripts/|bash .claude/hooks/|g' hooks/hooks.json > incoming/.claude/settings.json
# CLAUDE.md.snippet = the two skills' bodies (minus frontmatter), for people who'd rather have it in CLAUDE.md
{
  echo "# --- mogger: append everything below to your CLAUDE.md ---"
  echo
  echo "## Before anything else"
  echo
  echo "Read CONSTRAINTS.md at the start of every session (the SessionStart hook"
  echo "injects it automatically when installed as a plugin; in manual installs,"
  echo "read it yourself). Every line is a hard rule."
  echo
  for s in skills/mogger-loop/SKILL.md skills/mogger-standards/SKILL.md; do
    awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$s"
    echo
  done
} > incoming/CLAUDE.md.snippet
python3 -c "import json;json.load(open('incoming/.claude/settings.json'))"
echo "incoming/ regenerated:"; find incoming -type f | sort

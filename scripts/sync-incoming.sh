#!/usr/bin/env bash
# Regenerates incoming/ (the manual-install shape) from the plugin (canonical).
# Run with --check to only compare (CI). Run after changing anything in agents/, hooks/, skills/, or templates/.
# The plugin uses ${CLAUDE_PLUGIN_ROOT}; the manual shape uses .claude/hooks/.
set -e
cd "$(dirname "$0")/.."
NEW=incoming.new   # build aside, swap in at the end
trap 'rm -rf "$NEW"' EXIT
rm -rf "$NEW"
mkdir -p $NEW/.claude/agents $NEW/.claude/hooks
# agents name plugin paths; rewrite them to the manual layout (hooks in .claude/hooks, scripts and checks/ at the project root)
for f in agents/*.md; do
  sed -e 's|${CLAUDE_PLUGIN_ROOT}/hooks/scripts/|.claude/hooks/|g' -e 's|${CLAUDE_PLUGIN_ROOT}/scripts/checks/|checks/|g' -e 's|${CLAUDE_PLUGIN_ROOT}/scripts/||g' "$f" > "$NEW/.claude/agents/$(basename "$f")"
done
cp hooks/scripts/*.sh hooks/scripts/*.py $NEW/.claude/hooks/
chmod +x $NEW/.claude/hooks/*.sh
cp hooks/guards.tsv $NEW/.claude/guards.tsv
cp templates/CONSTRAINTS.md templates/RUNS.md templates/STACK.md templates/DECISIONS.md templates/SPEC.md templates/DATA.md templates/HANDOFF.md templates/pricing.json $NEW/
cp scripts/savings-report.py scripts/savings-report.sh scripts/mogger-rewind.sh scripts/mogger-config.sh scripts/smoke-check.sh scripts/smoke-browser.mjs scripts/ship-check.sh scripts/cost-report.sh scripts/context-cost.sh scripts/a11y-browser.mjs scripts/pentest-probe.sh $NEW/
mkdir -p $NEW/checks
cp scripts/checks/*.sh $NEW/checks/
chmod +x $NEW/checks/*.sh
chmod +x $NEW/*.sh $NEW/savings-report.py
# settings.json = hooks.json with plugin paths rewritten to project-relative paths
sed 's|bash \\"${CLAUDE_PLUGIN_ROOT}\\"/hooks/scripts/|bash .claude/hooks/|g' hooks/hooks.json > $NEW/.claude/settings.json
# CLAUDE.md.snippet = the skills' bodies (minus frontmatter), for people who'd rather have it in CLAUDE.md
{
  echo "# --- mogger: append everything below to your CLAUDE.md ---"
  echo
  echo "## Before anything else"
  echo
  echo "Read CONSTRAINTS.md at the start of every session (the SessionStart hook"
  echo "injects it automatically when installed as a plugin; in manual installs,"
  echo "read it yourself). Every line is a hard rule."
  echo
  for s in skills/loop/SKILL.md skills/standards/SKILL.md skills/grounding/SKILL.md; do
    awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$s"
    echo
  done
} > $NEW/CLAUDE.md.snippet
python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$NEW/.claude/settings.json"
if [ "${1:-}" = "--check" ]; then
  # exec bits matter for hooks, so compare modes too
  if diff -r incoming "$NEW" >/dev/null && [ "$(cd incoming && find . -type f -perm -u+x | LC_ALL=C sort)" = "$(cd "$NEW" && find . -type f -perm -u+x | LC_ALL=C sort)" ]; then
    rm -rf "$NEW"; echo "incoming/ is in sync"; exit 0
  fi
  rm -rf "$NEW"; echo "incoming/ is out of sync: run bash scripts/sync-incoming.sh" >&2; exit 1
fi
# built aside first: a failed copy above leaves the old incoming/ untouched
rm -rf incoming && mv "$NEW" incoming
echo "incoming/ regenerated:"; find incoming -type f | sort

#!/usr/bin/env bash
# Build the single-skill edition of mogger (agensi/mogger/) from the plugin.
# Run after changing skills, agents, hooks or agensi/SKILL.template.md.
set -euo pipefail
cd "${0%/*}/.."
out=agensi/mogger
rm -rf "$out"
mkdir -p "$out/hooks/scripts" "$out/references/agents" "$out/scripts/checks"

# hooks: the safety set only (what a skill can carry)
hooks="require-approval danger-guard secret-guard-bash secret-read-guard secret-guard config-guard taint-guard taint-mark verify-packages require-approval-mcp"
for h in $hooks; do cp "hooks/scripts/$h.sh" "$out/hooks/scripts/"; done
cp hooks/scripts/lib.sh hooks/scripts/secret-patterns.sh hooks/scripts/cmd-normalize.py "$out/hooks/scripts/"
cp hooks/guards.tsv "$out/hooks/"

# scripts the references call
cp scripts/ship-check.sh scripts/smoke-check.sh scripts/smoke-browser.mjs scripts/mogger-config.sh scripts/mogger-rewind.sh "$out/scripts/"
cp scripts/checks/*.sh "$out/scripts/checks/"

# references: every skill body, sub-files, and agent prompts
fix='s#\${CLAUDE_PLUGIN_ROOT}#<skill-dir>#g'
for d in skills/*/; do
  n=$(basename "$d")
  for f in "$d"*.md; do
    b=$(basename "$f" .md)
    if [ "$b" = SKILL ]; then t="$n.md"; else t="$n-$b.md"; fi
    sed "$fix" "$f" > "$out/references/$t"
  done
done
for f in agents/*.md; do sed "$fix" "$f" > "$out/references/agents/$(basename "$f")"; done

# SKILL.md: frontmatter (hooks) + template
{
  echo '---'
  echo 'name: mogger'
  echo 'description: "Safety and discipline kit for Claude Code: hook-blocked push, merge, deploy, money and destructive commands; secret-in-code and secret-read blocks; test-first, proof-before-done loop; review, security, edge-case and ship checks. Use at the start of any coding task, and before shipping."'
  echo 'hooks:'
  python3 - <<'PY'
import json
h = json.load(open("hooks/hooks.json"))["hooks"]
keep = {"require-approval","danger-guard","secret-guard-bash","secret-read-guard","secret-guard","config-guard","taint-guard","taint-mark","verify-packages","require-approval-mcp"}
by = {}
# ${CLAUDE_SKILL_DIR} is NOT set inside hook commands (tested, Claude Code 2.1.316),
# so the command finds the skill itself: project install first, then user install.
LOC = ('for d in "${CLAUDE_PROJECT_DIR}/.claude/skills/mogger" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/mogger"; '
       'do [ -f "$d/hooks/scripts/NAME.sh" ] && exec bash "$d/hooks/scripts/NAME.sh"; done; '
       'echo "mogger guard NAME not found in .claude/skills/mogger" >&2; exit 1')
for ev in ("PreToolUse", "PostToolUse"):
    for g in h.get(ev, []):
        for x in g["hooks"]:
            n = x["command"].split("/")[-1].rstrip('"').removesuffix(".sh")
            if n in keep:
                by.setdefault(ev, []).append((g["matcher"], n, x))
for ev, items in by.items():
    print(f"  {ev}:")
    for m, n, x in items:
        print(f'    - matcher: "{m}"')
        print("      hooks:")
        print("        - type: command")
        print("          command: '" + LOC.replace("NAME", n) + "'")
        if x.get("onFailure"): print(f'          onFailure: {x["onFailure"]}')
        print(f'          timeout: {x["timeout"]}')
PY
  echo '---'
  echo
  cat agensi/SKILL.template.md
} > "$out/SKILL.md"
echo "built $out: $(find "$out" -type f | wc -l) files, $(du -sk "$out" | cut -f1) KB"

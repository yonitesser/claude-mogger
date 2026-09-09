# jays-claude-moggage

A curated Claude Code enhancement kit. Everything in here was evaluated
against a written rubric ([CURATION.md](CURATION.md)), and everything we
looked at and *didn't* include is listed with the reason
([CONSIDERED.md](CONSIDERED.md)). That's the whole point: the internet is
full of "make Claude 1000x better" threads that are 80% noise. This is the
20%, with receipts.

## What this actually does

No config file makes the model smarter. What a kit *can* do, and what this
one does:

1. **Enforce discipline the model won't apply on its own.** Tests must
   actually pass (checked by exit code, not by the model saying so) before
   review. One task at a time. Surgical changes, no scope creep. A "done
   when" condition that's a real check, not an adjective.
2. **Hard-gate anything irreversible.** `git push`, merges, deploys, and
   anything touching money are blocked at the tool-call level by hooks —
   no prompt, no agent, no clever reasoning gets around a bash script that
   returns exit code 2.
3. **Feed it current facts, not stale memory.** Context7 for
   version-specific library docs. A STACK.md so library choices are made
   once, deliberately, and stay consistent.
4. **Cut waste.** Every agent has a `model:` assignment: Haiku reads
   files, greps the codebase, and runs tests; Sonnet builds and reviews;
   only the orchestrating Lead needs a frontier model. The Lead is told, in
   writing, not to Read or Grep itself. Output-token discipline on top (no
   preambles, no re-printing unchanged code). Optional compression proxy
   (headroom) for heavy tool output.
5. **Remember corrections.** CONSTRAINTS.md is a permanent, append-only
   home for every "don't do that again." A `retro` agent proposes new
   entries from run history; a human approves them.
6. **Auto-format on every edit.** A PostToolUse hook runs the project's
   own formatter/linter (prettier, ruff, gofmt, rustfmt, etc.) on each
   file Claude touches. Clean code isn't a prompt instruction, it's a
   hook.

## What's in the box

```
README.md            you're here
CURATION.md          the rubric — what earns a place in this kit
CONSIDERED.md        every tool we evaluated, with verdicts
INTEGRATION.md       how to merge this into a project that already has a .claude/ setup
incoming/            the actual files, staged — nothing auto-copies
  .claude/hooks/     approval gates, test gate, cost routing, auto-format
  .claude/agents/    planner, builder, tester, reviewer, retro, explorer, bulk-reader, code-writer
  .claude/settings.json
  CLAUDE.md.snippet  orchestration loop, model routing, coding principles, library rules, token discipline
  CONSTRAINTS.md     append-only corrections
  RUNS.md            append-only run log
  STACK.md           library choices for this project
```

## Install

Drop the whole repo into your project root and tell Claude Code:

> Read INTEGRATION.md and install this kit into the project.

INTEGRATION.md handles both cases: a **fresh project** with no `.claude/`
yet (it copies things in and fills what it can), and an **existing setup**
with its own agents and hooks (it merges by intent instead of overwriting).
Either way it tells you what it did and what's now gated.

Needs `jq` on the machine — the hooks use it to parse tool input.

## Recommended companions (external, install separately)

Real tools, verified, that cover things a config file can't:

| Tool | Why | Overlaps with |
|---|---|---|
| [Context7](https://github.com/upstash/context7) | Current library docs in-prompt; kills hallucinated APIs | nothing — pure add |
| [headroom](https://github.com/headroomlabs-ai/headroom) | Local compression proxy; reversible; `headroom wrap claude` | bulk-reader/code-writer (pick one) |
| [SkillSpector](https://github.com/NVIDIA/SkillSpector) | Scan any third-party skill before installing it | nothing — pure add |
| [Superpowers](https://github.com/obra/superpowers) | Mature plan/build/test/review loop | this kit's agents (pick one; keep the hooks either way) |

Details and the one-adjustment-each notes are in `CLAUDE.md.snippet`.

## Philosophy in one line

If a claim can't be verified by exit code, a benchmark with methodology,
or a diff you can read — it's not in here.

## License

MIT. Take it, fork it, get mogged.

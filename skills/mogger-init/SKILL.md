---
name: mogger-init
description: First-run setup for the mogger plugin in a project. Creates CONSTRAINTS.md, RUNS.md, STACK.md, and .claude/state/ if missing, fills STACK.md from existing dependency files, checks jq/python3 are present, and reports what's now gated. Run once per project, or when the user says "set up mogger" / "init mogger".
---

# mogger init

A plugin can't create files in the user's project at install time. This
skill does that on first run. It's idempotent — re-running it never
overwrites a file that already exists.

## Steps

1. **Dependency check.** `command -v jq || command -v python3` (and verify
   python3 actually runs, not a Windows Store stub: `python3 -c '1'`). If
   neither works, stop and tell the user: the hooks parse JSON with one of
   these and will fail open (block nothing) without them.

2. **Context7 — already active, nothing to do.** This plugin bundles
   Context7 as a hosted remote MCP server (`.mcp.json` at the plugin root,
   pointed at `https://mcp.context7.com/mcp`). It registered automatically
   when the plugin installed — no local npx, no separate step. Works
   anonymously; `CONTEXT7_API_KEY` in the environment raises rate limits
   but isn't required. Just confirm it's in the tool list and mention it's
   live, rather than re-explaining the mechanism.

3. **SkillSpector — auto-install if missing.** Run `command -v skillspector`.
   If absent: check for `uv` (`command -v uv`); if present, run
   `uv tool install git+https://github.com/NVIDIA/skillspector.git`
   automatically — a small, reversible CLI install, not a system change, so
   don't ask first, just do it and report the result. If `uv` itself is
   missing, tell the user the one command to install it
   (`curl -LsSf https://astral.sh/uv/install.sh | sh` on macOS/Linux, docs
   at https://docs.astral.sh/uv/ on Windows) rather than chaining a second
   unrequested install — a language-level package manager is a bigger step
   than one CLI on top of it.

4. **Scaffold files, only if missing.** Templates live in the plugin at
   `${CLAUDE_PLUGIN_ROOT}/templates/`. For each of `CONSTRAINTS.md`,
   `RUNS.md`, `STACK.md`: if the project root doesn't have it, copy the
   template. If it does, leave it alone and say so. Also
   `mkdir -p .claude/state` (tester writes its result marker there, and
   the Haiku agents append to `.claude/state/savings.jsonl` there too —
   touch that file into existence if missing so the first agent call
   doesn't fail on a missing directory, though the log script itself
   already does `mkdir -p`).

5. **Fill STACK.md from what's visible.** Read `package.json`,
   `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, `composer.json` —
   whichever exist. Fill the language/version and package manager lines,
   and any table rows you can determine from actual dependencies (the
   HTTP client they already use, the test framework already installed).
   Leave rows blank when you'd be guessing. Note the formatter/linter
   from config files present (`.prettierrc`, `ruff.toml`, etc.) — the
   auto-format hook reads those directly, but the record helps humans.

6. **Check for conflicting project config.** If `.claude/settings.json`
   exists with its own hooks, list them. If any duplicate a mogger hook
   (a second formatter on PostToolUse, a second push-blocker), tell the
   user — don't silently run two. If `CLAUDE.md` says anything that
   contradicts the approval boundary (e.g. "auto-merge when tests pass"),
   quote it and stop — the human resolves that, not you.

7. **Report, briefly.** What was created, what was already there, which
   dependency check passed, whether SkillSpector got installed (and how),
   that Context7 is live, and this exact summary of what's now enforced:

   - `git push`, merge while on a protected branch, PR merge, prod
     deploys, and money CLIs are blocked until a human approves.
   - Edits to CI/CD, Dockerfiles, Terraform, and payment code are blocked.
   - `reviewer` cannot run without a real recorded test pass.
   - You cannot end a turn with open tasks in TASKS.md and no blocker.
   - Every edited file gets the project's own formatter run on it.
   - Haiku handles reads/searches/tests; Sonnet builds/reviews; the Lead
     orchestrates.
   - Context7 is available for current library docs; SkillSpector is
     installed (or the user has the one command to add it).
   - `bash scripts/savings-report.py` shows an *estimate* of cost avoided
     by Haiku routing so far — self-reported by the agents, not verified,
     and clearly labeled as such in its own output. Not required reading,
     just available if the user is curious.

   Then suggest: "Add your first correction to CONSTRAINTS.md the first
   time I do something you have to fix twice."

## What this does NOT do

- Doesn't touch git config, remotes, or branches.
- Doesn't install jq, formatters, headroom, or anything beyond
  SkillSpector. Reports what else is missing; the human installs the rest.
- Doesn't edit an existing CLAUDE.md. If the user wants the loop
  described there too, they can ask — the skills already cover it.

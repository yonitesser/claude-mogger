---
name: mogger-init
description: First-run setup for the mogger plugin in a project. Creates CONSTRAINTS.md, RUNS.md, STACK.md, and .claude/state/ if missing, fills STACK.md from existing dependency files, checks jq/python3 are present, and reports what's now gated. Run once per project, or when the user says "set up mogger" / "init mogger".
---

# mogger init

A plugin can't create files in the user's project at install time. This
skill does that on first run. It's idempotent — re-running it never
overwrites a file that already exists.

## Steps

1. **Dependency check.** `command -v jq || command -v python3`. If neither
   exists, stop and tell the user: the hooks parse JSON with one of these
   and will fail open (block nothing) without them. Don't proceed as if
   the gates work.

2. **Scaffold files, only if missing.** Templates live in the plugin at
   `${CLAUDE_PLUGIN_ROOT}/templates/`. For each of `CONSTRAINTS.md`,
   `RUNS.md`, `STACK.md`: if the project root doesn't have it, copy the
   template. If it does, leave it alone and say so. Also
   `mkdir -p .claude/state` (tester writes its result marker there).

3. **Fill STACK.md from what's visible.** Read `package.json`,
   `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, `composer.json` —
   whichever exist. Fill the language/version and package manager lines,
   and any table rows you can determine from actual dependencies (the
   HTTP client they already use, the test framework already installed).
   Leave rows blank when you'd be guessing. Note the formatter/linter
   from config files present (`.prettierrc`, `ruff.toml`, etc.) — the
   auto-format hook reads those directly, but the record helps humans.

4. **Check for conflicting project config.** If `.claude/settings.json`
   exists with its own hooks, list them. If any duplicate a mogger hook
   (a second formatter on PostToolUse, a second push-blocker), tell the
   user — don't silently run two. If `CLAUDE.md` says anything that
   contradicts the approval boundary (e.g. "auto-merge when tests pass"),
   quote it and stop — the human resolves that, not you.

5. **Report, briefly.** What was created, what was already there, which
   dependency check passed, and this exact summary of what's now enforced:

   - `git push`, merge while on a protected branch, PR merge, prod
     deploys, and money CLIs are blocked until a human approves.
   - Edits to CI/CD, Dockerfiles, Terraform, and payment code are blocked.
   - `reviewer` cannot run without a real recorded test pass.
   - You cannot end a turn with open tasks in TASKS.md and no blocker.
   - Every edited file gets the project's own formatter run on it.
   - Haiku handles reads/searches/tests; Sonnet builds/reviews; the Lead
     orchestrates.

   Then suggest: "Add your first correction to CONSTRAINTS.md the first
   time I do something you have to fix twice."

## What this does NOT do

- Doesn't touch git config, remotes, or branches.
- Doesn't install jq, formatters, Context7, headroom, or anything else.
  It reports what's missing; the human installs.
- Doesn't edit an existing CLAUDE.md. If the user wants the loop
  described there too, they can ask — the skills already cover it.

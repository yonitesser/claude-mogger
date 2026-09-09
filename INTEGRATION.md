# INTEGRATION.md — read this before touching anything

You are a Claude Code agent installing this kit into a project **manually**
(the user chose not to use the plugin install, or wants the files in their
repo). Everything to install lives under `incoming/` — a generated mirror of
the plugin in project-relative shape. First, figure out which situation
you're in — the steps are different.

If the user just wants the plugin: `/plugin marketplace add <owner>/claude-mogger`
then `/plugin install mogger@claude-mogger`, then run the
`mogger-init` skill. This file is not needed for that path.

## Step 0: which path?

Run `ls -la .claude/ CLAUDE.md 2>/dev/null` in the project root.

**Path A — fresh project.** No `.claude/` directory, or an empty one, and no
CLAUDE.md (or one with nothing about agents/hooks in it). → Follow
"Path A" below. It's mostly copying.

**Path B — existing setup.** A `.claude/` with its own agents, hooks, or
settings.json, and/or a CLAUDE.md that already describes how the project
runs. → Follow "Path B" below. It's merging by intent, and the rest of this
file is mostly for you.

If you're unsure, it's Path B — merging carefully into an empty setup costs
nothing extra; copying blindly over a real one breaks things.

---

## Path A — fresh project

1. `cp -r incoming/.claude .claude` and `chmod +x .claude/hooks/*.sh`.
2. Copy `incoming/CONSTRAINTS.md`, `incoming/RUNS.md`, and
   `incoming/STACK.md` to the project root.
3. If no CLAUDE.md exists, `cp incoming/CLAUDE.md.snippet CLAUDE.md` and
   remove the first line (the "append everything below" banner). If a
   minimal CLAUDE.md exists (project description, build commands), append
   the snippet's contents below what's there.
4. Confirm `jq` or `python3` is installed — the hooks parse JSON with one
   of them (see `hooks/lib.sh`). If neither is present, say so: the hooks
   will fail open (block nothing) until one is installed.
5. Open `STACK.md` and fill in what you can see from the existing
   dependencies (package.json, pyproject.toml, go.mod, Cargo.toml). Leave
   rows you can't fill blank — don't guess.
6. Tell the user: what was installed, that the three approval-gate hooks
   are now active (`git push`/merge/deploy/money are blocked until they
   approve), which model each agent runs on, and that `jq` is (or isn't)
   present. Then stop.

Skip the rest of this file. It's about reconciling with things you don't
have.

---

## Path B — existing setup

This kit is NOT meant to be copied over an existing `.claude/`. Your job is
to fold the *intent* of these files into what already exists, not paste
files on top of it.

Do not run `cp -r incoming/.claude .claude` or anything like it. Read the
rest of this file, then look at what's actually in the project's `.claude/`,
then merge piece by piece.

---

## What this is trying to do, in one paragraph

The user wants Claude Code to plan → build → test → review with minimal
check-ins, but with a hard, non-negotiable boundary: no agent, however
persuasive its reasoning, may push to git, merge, deploy, or touch anything
money-related without a human approving it first. Everything in `incoming/`
either (a) implements that loop, or (b) enforces that boundary. Nothing here
is about coding style or productivity tricks — it's about where the human
approval gate sits and making sure nothing can talk its way around it.

---

## What's non-negotiable vs what's flexible

**Non-negotiable — must end up in the project one way or another, even if
renamed or merged into existing files:**

- The hard block on `git push`, `git merge`, `gh pr merge`, deploy commands,
  and money/billing commands (`incoming/.claude/hooks/require-approval.sh`).
- The block on editing CI/CD and payment config files without approval
  (`incoming/.claude/hooks/protect-pipeline-files.sh`).
- The rule that a review/approval step cannot run on a self-reported test
  pass — it must check a real exit code
  (`incoming/.claude/hooks/require-tests-pass.sh`).
- The Stop hook that refuses to end a turn with open tasks and no recorded
  blocker (`incoming/.claude/hooks/stop-done-means-done.sh`). Without it,
  "done" is whatever the model says it is.

If the project already has hooks or subagents that cover any of these, do
not add a duplicate — verify the existing one actually enforces the same
thing (exits non-zero / blocks the tool call), and only add what's missing.

**Flexible — adapt to match what the project already has, or skip if
redundant:**

- The specific subagent names (`planner`, `builder`, `tester`, `reviewer`,
  `retro`, `bulk-reader`, `code-writer`). If the project already has
  subagents doing equivalent jobs under different names, keep the
  project's names and graft the missing behavior (see per-file notes below)
  into them instead of adding parallel agents that do the same thing twice.
- `CONSTRAINTS.md` / `RUNS.md` file names — if the project already has a
  "lessons learned" or "changelog" file serving the same purpose, point the
  new instructions at that file instead of creating a second one.
- The 350-line threshold in the bulk-read hooks, the retry cap, the CI
  file-pattern list — all tunable, not sacred.

---

## Per-file intent

### `incoming/.claude/hooks/require-approval.sh`
**Intent:** hard-block git push/merge, PR merge, deploy commands, and
anything money-related, at the Bash-tool level, regardless of which agent
or prompt is trying to run it.
**Merge action:** if the project's `settings.json` already has a
`PreToolUse` entry matching `Bash`, add this script to that matcher's
`hooks` array — don't create a second `Bash` matcher block. If a similar
guard already exists, read it and confirm it actually covers push/merge/
deploy/money; if it's narrower (e.g. only blocks `rm -rf`), keep both.

### `incoming/.claude/hooks/protect-pipeline-files.sh`
**Intent:** same idea, for file edits instead of shell commands — CI
configs, Dockerfiles, Terraform, payment/billing files.
**Merge action:** same as above, but under the project's `Edit|Write`
matcher.

### `incoming/.claude/hooks/require-tests-pass.sh`
**Intent:** this is the one to take most seriously. It reads
`.claude/state/last_test_result.json` and blocks any `Task` call to a
review-type subagent unless that file says `"status": "pass"` with a
timestamp newer than the most recent file edit. The point: a review agent
grading code it (or a sibling agent) wrote will find reasons to approve it.
This hook makes "tests actually passed" a fact checked outside any LLM's
judgment.
**Merge action:** find whichever existing subagent does final
review/approval before a human looks at the work. Point this hook's
`subagent_type` check at that agent's actual name (edit the
`if [ "$SUBAGENT" != "reviewer" ]` line). If the project's test-running
agent doesn't currently write a machine-readable result file, that's the
one required change — see `tester.md` below for the pattern to copy.

### `incoming/.claude/agents/tester.md`
**Intent:** shows the pattern for writing `.claude/state/last_test_result.json`
with a real exit code, not a prose claim.
**Merge action:** if the project has its own test-running subagent, don't
replace it — add the "write the marker file with the real exit code" step
to its existing instructions. Only use this file wholesale if there's no
existing equivalent.

### `incoming/.claude/agents/reviewer.md`
**Intent:** final check before human approval. Explicitly has no git access
beyond `git diff`/`git log` (read-only) — cannot merge, push, or approve its
own gate.
**Merge action:** if the project has an existing reviewer/approver-style
agent, confirm it's similarly read-only on git and gate it behind
`require-tests-pass.sh`. Don't duplicate the role.

### `incoming/.claude/agents/planner.md` and `builder.md`
**Intent:** planner breaks work into small tasks with a machine-checkable
"done when" condition (not "done when it works well"); builder does exactly
one task at a time, doesn't look ahead, doesn't merge/push.
**Merge action:** if the project's existing planning/coding agents already
enforce small-scoped tasks and a real stop condition, no change needed.
If they don't, the "done when must be a check, not an adjective" rule
(planner.md) and the "one task at a time, no git access" rule (builder.md)
are the parts worth grafting in.

### `incoming/.claude/agents/retro.md`
**Intent:** a meta-loop, run on demand (not automatic), that reads run
history and proposes edits to CONSTRAINTS.md/CLAUDE.md — and explicitly
never applies its own proposals. This exists because an agent that can
edit its own constraints unsupervised will eventually edit away the
constraint that's inconvenient.
**Merge action:** genuinely new capability in most setups — add as-is,
using project's actual file names for its own constraints/changelog file
if different from CONSTRAINTS.md/RUNS.md.

### `incoming/.claude/agents/bulk-reader.md`, `code-writer.md`, and `explorer.md`
**Intent:** cost-routing — all three run on Haiku so the expensive Lead
model never spends its context on I/O. `bulk-reader` reads big files and
answers one question. `explorer` finds where code lives (grep + paths).
`code-writer` copies an existing pattern into boilerplate.
**Merge action:** unrelated to the approval-gate stuff. If the project
already has cheap-model subagents for reading/searching, keep theirs —
but check their `model:` line. If an existing read/search/test agent is
running on Sonnet or Opus, that's the single easiest cost win in this
whole merge: change it to `haiku`. Nothing those agents do gets better
with a smarter model. Skip these files entirely if headroom is installed —
it handles the same job upstream.

### `incoming/.claude/hooks/session-start.sh`
**Intent:** SessionStart hook — prints CONSTRAINTS.md corrections, filled
STACK.md rows, and TASKS.md status to stdout, which Claude Code adds to
context. Turns "please read CONSTRAINTS.md" into "it's already there."
Also warns if neither jq nor python3 is installed.
**Merge action:** add under `SessionStart`. If the project already has a
SessionStart hook, add ours alongside it — they don't conflict.

### `incoming/.claude/hooks/stop-done-means-done.sh`
**Intent:** Stop hook — exits 2 (sending the Lead back to work) if TASKS.md
has unchecked items and no `BLOCKED:` line, no `## Status: awaiting-approval`,
and no open questions. Checks `stop_hook_active` so it never loops.
**Merge action:** add under `Stop`. If the project uses a different task
file than TASKS.md, edit the filename in the script. If the project has no
task-board convention at all, this hook is a no-op (no TASKS.md → allow).

### `incoming/.claude/hooks/lib.sh`
**Intent:** shared helper every hook sources — `json_get` (jq or python3),
`git_branch`, `is_protected_branch`. Not a hook itself; has no entry in
settings.json.
**Merge action:** must be copied alongside the other scripts. Hooks
`source "$(dirname "$0")/lib.sh"` so it has to sit in the same directory.

### `incoming/.claude/hooks/auto-format.sh`
**Intent:** PostToolUse hook — after every Edit/Write, runs the project's
*own* formatter and linter on the touched file. Detects prettier/biome/
eslint/ruff/black/gofmt/rustfmt/rubocop/etc. from the project's existing
config files. Installs nothing, imposes nothing the project didn't already
choose. Always exits 0 — a formatter hiccup must never block an edit.
**Merge action:** add under a `PostToolUse` → `Edit|Write` matcher. If the
project already has a post-edit formatting hook, keep theirs — don't run
two formatters. If the project has no formatter configured at all, the hook
is a harmless no-op until one is added.

### `incoming/STACK.md`
**Intent:** one place where library choices are recorded so every agent
uses the same dependency for the same job, and so the "why" survives.
**Merge action:** if the project already documents its stack (an
ARCHITECTURE.md, a tech-stack section in README), point the CLAUDE.md
"Library selection" rule at that instead of adding a second file. Otherwise
add it and let the team fill in the table over time — an empty STACK.md is
still useful because the rule says "check here first."

### `incoming/CONSTRAINTS.md` and `incoming/RUNS.md`
**Intent:** CONSTRAINTS.md is a permanent, append-only home for corrections
the user makes, loaded at the start of every session. RUNS.md is an append-only
log of completed tasks, feeding `retro`.
**Merge action:** check for an existing file serving either purpose first
(a CHANGELOG, a NOTES.md, a lessons-learned doc). If one exists, redirect
CLAUDE.md instructions to it instead of creating a duplicate. Only add
these files if nothing like them exists.

### `incoming/CLAUDE.md.snippet`
**Intent:** defines the orchestration loop (plan → build → test → review →
stop) and states the approval boundary in plain language for whichever
agent is acting as Lead.
**Merge action:** do not append this wholesale if the project's CLAUDE.md
already describes its own orchestration loop — that will create
contradictory instructions. Instead: diff the two. Keep the project's
existing loop description. Only add the specific sentences that state the
approval boundary (the "Hard boundary" section) if the project's CLAUDE.md
doesn't already say something equivalent. If it contradicts (e.g. the
project's CLAUDE.md currently permits auto-merge), stop and flag this to
the user rather than silently overriding either one.

---

## Path B checklist

1. Read the project's current `.claude/settings.json`, `.claude/agents/*`,
   and `CLAUDE.md` in full before changing anything.
2. Identify which of the three non-negotiable hooks are missing or weaker
   than what's in `incoming/.claude/hooks/`. Add only what's missing, into
   existing matcher blocks where possible.
3. Identify which existing subagent plays each role (planner/builder/
   tester/reviewer-equivalent). Graft in the specific missing behaviors
   listed above rather than adding parallel agents.
4. Add `retro` and (optionally) `bulk-reader`/`code-writer` as new agents
   only if nothing already fills those roles.
5. Reconcile CONSTRAINTS.md/RUNS.md against any existing equivalent files.
6. Reconcile CLAUDE.md.snippet against the existing CLAUDE.md — merge
   language, don't duplicate or contradict.
7. Before finishing, state back to the user in plain terms: what was added, what
   was skipped as redundant, and any contradiction you found and didn't
   resolve on your own.

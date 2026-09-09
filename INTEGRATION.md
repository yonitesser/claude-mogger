# INTEGRATION.md — read this before touching anything

You are a Claude Code agent working inside a project that already has a
fleshed-out `.claude/` setup. This zip is NOT meant to be copied over that
setup. Everything you need to merge lives under `incoming/`. Your job is to
fold the *intent* of these files into what already exists, not paste files
on top of it.

Do not run `cp -r incoming/.claude .claude` or anything like it. Read this
whole file first, then look at what's actually in the project's `.claude/`,
then merge piece by piece.

---

## What this is trying to do, in one paragraph

Jay wants Claude Code to plan → build → test → review with minimal
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

### `incoming/.claude/agents/bulk-reader.md` and `code-writer.md`
**Intent:** cost-routing — cheap model (Haiku) handles big-file reads and
boilerplate so the frontier model isn't spending budget on I/O.
**Merge action:** unrelated to the approval-gate stuff above. Skip entirely
if the project already has its own cost-routing subagents or doesn't need
this. Not part of the safety boundary — purely optional.

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
Jay makes, loaded at the start of every session. RUNS.md is an append-only
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
Jay rather than silently overriding either one.

---

## Checklist for you (the integrating agent)

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
7. Before finishing, state back to Jay in plain terms: what was added, what
   was skipped as redundant, and any contradiction you found and didn't
   resolve on your own.

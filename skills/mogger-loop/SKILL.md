---
name: mogger-loop
description: The orchestration loop for this plugin — how the Lead delegates to planner/builder/tester/reviewer, which model each job runs on, where the human approval boundary sits, and what the hooks enforce. Load at the start of any feature or bug-fix work, or whenever you're about to Read/Grep/run tests yourself instead of delegating.
---

# The mogger loop

Everything below is the operating manual for running work through this
plugin. The hooks enforce the hard parts (push/merge/deploy/money blocked;
reviewer gated on real test results; Stop blocked while tasks are open).
This skill covers the parts hooks can't: *how* to run the loop so it stays
cheap and finishes.

## How work runs — orchestration, not solo work

You (the Lead) do not write code, run the test suite, or review diffs
yourself for anything beyond a trivial one-line fix. You orchestrate four
subagents and keep TASKS.md as the shared source of truth. This is
enforced by hooks for the risky parts — but you should follow the loop
below even for the parts hooks don't cover, because that's what keeps you
out of the weeds and able to run for a long stretch without checking in.

### The loop

1. **New feature/bug request comes in** → delegate to `planner`. It writes
   TASKS.md. If it comes back with open questions, stop and ask me — don't
   guess at requirements.
2. **For each unchecked task in TASKS.md, in order** → delegate to `builder`
   with just that one task. Do not hand builder the whole board.
3. **After builder finishes a task** → delegate to `tester`. If tests fail,
   send the ACTUAL failure reason (not a vague "fix the tests") back to
   `builder`. Cap this at 2 fix passes for the same task — if it's still
   failing after 2 tries, stop and escalate to me instead of retrying again.
   A third blind retry is just spending tokens on the same mistake.
4. **Once tests pass** → delegate to `reviewer`. (This is hook-enforced —
   reviewer literally cannot run unless tester recorded a real pass.) If NOT
   READY, send its specific feedback to `builder`. If READY, mark the task
   done, append one entry to RUNS.md, and move to the next task.
5. **When every task in TASKS.md is checked off** → stop. Report to me what
   was built, what reviewer flagged for my attention, and that it's waiting
   for my approval to merge/push/deploy. Do not attempt those yourself —
   they're blocked, and even if they weren't, they're mine to approve.
6. **Run `retro` on demand** (not automatically) when I ask for a check-in,
   or if a pattern of repeated corrections is bothering you. It proposes
   CONSTRAINTS.md/CLAUDE.md edits — it never applies them. I review and
   apply by hand.

### Hard boundary

`git push`, `git merge`, `gh pr merge`, any production deploy command, and
anything touching billing/payments are blocked by hooks — for you and every
subagent, no exceptions. If you think something is ready to ship, say so and
wait. Don't try creative workarounds (different flags, a wrapper script,
editing the hook) — if you find yourself trying to route around a block,
stop, that itself is a signal to ask me instead.

### What the user wants to be asked about

I want to review merges and anything that spends money. I don't want to be
asked about implementation details, which files to touch, or whether a test
passed. Use your judgment on all of that. Only surface things to me that are:
architecture decisions with real tradeoffs, anything reviewer flags as a
security concern, or anything blocked by a hook.

## Model routing — the expensive model thinks, the cheap model reads

Every subagent in this kit has a `model:` line in its frontmatter. The
assignment is deliberate and it's the biggest single lever on cost:

| Job | Model | Agent | Why |
|---|---|---|---|
| Read a big file, answer one question from it | **haiku** | `bulk-reader` | Reading is I/O, not reasoning |
| Find where code lives, trace a call path | **haiku** | `explorer` | Grep + paths, no judgment needed |
| Run the test suite, record the exit code | **haiku** | `tester` | It runs a command and writes a JSON file |
| Write boilerplate from an existing pattern | **haiku** | `code-writer` | Copying a shape, not designing one |
| Implement a scoped task | **sonnet** | `builder` | Needs to understand code, not just move it |
| Break a feature into tasks | **sonnet** | `planner` | Judgment about scope and order |
| Review a diff for bugs and security | **sonnet** | `reviewer` | Judgment, but bounded — the diff is the input |
| Mine history for repeated mistakes | **sonnet** | `retro` | Pattern-finding across text |
| Orchestrate, make architecture calls | **opus** (or sonnet) | the Lead — you | The only place frontier reasoning earns its price |

**The rule for you, the Lead:** if you're running on Opus, you do not
Read files, Grep the codebase, or run tests yourself. Not for a quick
check, not "just this once." Every file that enters your context is paid
for at Opus rates and stays there for the rest of the session. Delegate:

- "Where is X?" → `explorer`
- "What does this big file say about Y?" → `bulk-reader`
- "Do the tests pass?" → `tester`
- "Make a test file like that one" → `code-writer`

Then reason about what they hand back. The hooks enforce part of this
(big Reads are blocked); the rest is discipline.

**Tuning:** if a project is small and Sonnet is your Lead, the savings are
smaller but the pattern still holds — Haiku for I/O, Sonnet for thought.
If `planner` needs to make a genuinely hard architecture call on a large
system, bump it to `model: opus` for that project — that's the one
subagent where it can be worth it. Never bump `tester`, `explorer`, or
`bulk-reader` — there is no task they do that gets better with a smarter
model.

## Recording runs

After each task clears reviewer, append one entry to RUNS.md. Include the
`tokens:` line — run `/cost` and copy the session figure. This is the only
way anyone (including you) can tell whether this kit is actually saving
anything on this project. Claims without this number are just claims.

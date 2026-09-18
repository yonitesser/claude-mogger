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
yourself for anything beyond a trivial one-line fix. You orchestrate the
subagents and keep TASKS.md as the shared source of truth. This is
enforced by hooks for the risky parts — but you should follow the loop
below even for the parts hooks don't cover, because that's what keeps you
out of the weeds and able to run for a long stretch without checking in.

### The loop

1. **New feature/bug request comes in** → delegate to `planner`. It writes
   TASKS.md with a `files:` list per task (hook-enforced scope), a
   machine-checkable `done when:`, `[parallel-with: N]` on tasks that are
   safe to run concurrently, and `[library-scout first]` on tasks that
   would otherwise reinvent a solved problem. If it comes back with open
   questions, stop and ask me — don't guess at requirements.

2. **Any task marked `[library-scout first]`** → delegate to
   `library-scout` before the builder starts. Pass its recommendation to
   the builder verbatim. "Write it yourself" is a valid, common answer —
   don't re-run the scout hoping for a different one.

3. **Dispatch the work:**
   - Tasks marked `[parallel-with: N]` that form a group → dispatch those
     builders **concurrently, in a single message with multiple Task
     calls**. This is the biggest wall-clock win available in this loop;
     use it whenever planner marked a group.
   - Everything else → one builder at a time, in order. Never hand a
     builder the whole board.
   - **Before dispatching any parallel group, verify the `files:` lists
     don't overlap.** Planner marks them, but you own the final check —
     two builders editing one file is a merge conflict you then have to
     untangle by hand, which costs more than the parallelism saved. If
     they overlap at all, run them sequentially and ignore the marking.

4. **After builder(s) finish** → delegate to `tester`. During the loop it
   runs only the affected tests (fast); that's enough to catch a broken
   task early. If tests fail, send the ACTUAL failure reason (not a vague
   "fix the tests") back to `builder`. Cap this at 2 fix passes for the
   same task — if it's still failing after 2 tries, stop and escalate to
   me instead of retrying again. A third blind retry is just spending
   tokens on the same mistake.

5. **Before review, get a full-suite pass** → have `tester` run the
   complete suite once (not just affected tests). This is hook-enforced:
   `require-tests-pass.sh` rejects a `reviewer` dispatch whose recorded
   test scope isn't `full`.

6. **Then** → delegate to `reviewer`. If NOT READY, send its specific
   feedback to `builder`. If READY, mark the task done, append one entry
   to RUNS.md, and move on.

7. **When every task in TASKS.md is checked off** → stop. Report to me what
   was built, what reviewer flagged for my attention, and that it's waiting
   for my approval to merge/push/deploy. Do not attempt those yourself —
   they're blocked, and even if they weren't, they're mine to approve.

8. **Run `retro` on demand** (not automatically) when I ask for a check-in,
   or if a pattern of repeated corrections is bothering you. It proposes
   CONSTRAINTS.md/CLAUDE.md edits — it never applies them. I review and
   apply by hand.

### Reading discipline — diffs, not re-reads

After anything has been edited, read `git diff` rather than re-reading the
file. Re-reading a 600-line file to confirm a 10-line change cost you 600
lines of context to learn what 10 lines would have told you, and that
context stays in your window for the rest of the session.

- Verify an edit landed → `git diff -- <path>`
- Understand what changed across a task → `git diff --stat` then
  `git diff` on the files that matter
- Need to know what a file looked like before → `git show HEAD:<path>`,
  not a full read plus guessing

This applies to you and to every subagent. It's advisory, not hooked —
but it's one of the largest recurring savings available, because re-reads
are the most common way a session's context quietly fills up.

### Prompt ordering for cache hits

Cached input bills at roughly a tenth of normal input, so the order
content appears in a prompt has real cost consequences. Put stable content
first and volatile content last:

1. Stable, reused across calls: CONSTRAINTS.md, STACK.md, the skill text,
   project conventions, the file(s) under discussion
2. Then: the specific task, the current diff, the failure output, this
   turn's question

Keeping the stable prefix byte-identical between calls is what lets it
cache. Re-ordering it, re-summarizing it, or inserting a timestamp near
the top breaks the prefix and forfeits the discount. When you delegate to
a subagent repeatedly in a loop (builder → tester → builder), hand it the
same stable preamble each time rather than a freshly-worded one.

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
| Decide library vs hand-rolled | **sonnet** | `library-scout` | Weighing tradeoffs, reading docs, saying no |
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

## Optional: the savings estimate is a different thing than RUNS.md tokens

RUNS.md's `tokens:` field is the real, actual session total from `/cost` —
solid ground. `bash scripts/savings-report.py` is something weaker and
should never be confused with it: an *estimate* of what Haiku-routed calls
would have cost if billed at the Lead's model rate instead, based on
self-reported (not verified) output length. No task here was ever run
twice to produce a real before/after number — this is a disclosed
calculation, not a measurement. Both the terminal output and the generated
`savings-dashboard.html` state this plainly. If asked "how much did this
kit save," point to RUNS.md's real totals first; mention the estimate
second, with its caveat intact.

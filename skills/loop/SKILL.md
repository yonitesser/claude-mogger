---
name: loop
description: The work loop: plan, build, test, review. The Lead does plan/build/test itself and delegates only reading and independent review. Model per job, the approval boundary, what hooks enforce. Load before feature or bug-fix work.
---

# The mogger loop

Everything below is the operating manual for running work through this
plugin. The hooks enforce the hard parts (push/merge/deploy/money blocked;
reviewer gated on real test results; Stop blocked while tasks are open).
This skill covers the parts hooks can't: *how* to run the loop so it stays
on track and finishes.

## How work runs: one loop, few hand-offs

You (the Lead) plan, build and test in your own context, so nothing is lost
in a summary between agents. You delegate only two kinds of work: reading
(`explorer`, `bulk-reader`: you want the answer, not the file) and
independent review (`reviewer`, `security-reviewer`, `fact-checker`: not
seeing your reasoning is the point). TASKS.md is the shared source of truth.

### The loop

1. **Feature or bug request** → plan it yourself. Read `planning.md` in this
   folder for the TASKS.md format (`files:` list is hook-enforced scope,
   machine-checkable `done when:`, `R` lines, `[library-scout first]`). Open
   questions about requirements: stop and ask me, don't guess. A single small
   fix needs no board.

2. **Task marked `[library-scout first]`** → run `library-scout` before you
   build it, and follow its answer. "Write it yourself" is a valid answer.

3. **Build and test one task at a time.** Read `doing.md` in this folder:
   build rules, the two-phase test run (affected tests while building, the
   full suite once before review), the `last_test_result.json` marker, and the
   smoke check. Failing tests: fix the real cause, run again. Two fix passes
   for the same task, then stop and ask me.

4. **Before review, get a full-suite pass.** This is hook-enforced:
   `require-tests-pass.sh` rejects a `reviewer` dispatch whose recorded test
   scope isn't `full` or whose hook-recorded run did not pass.

   If I ask you to commit: one commit per finished task, with the tests
   passing. Never commit unasked.

5. **Then** → delegate to `reviewer`. If NOT READY, fix only the failed units,
   one return form each (never the whole batch; passed units stay untouched):

   ```
   UNIT      <task or file>
   VERDICT   red
   REASON    <what failed>
   EVIDENCE  <file:line or command output>
   SCOPE     fix this unit only; do not touch other files or tasks
   ```

   If READY, mark the task done, append one entry to RUNS.md, and move on.

6. **When every task is checked off** → stop. Report what was built, what
   reviewer flagged, and that it is waiting for my approval to merge/push/
   deploy. Those are blocked and mine to approve.

7. **Run `retro` on demand** (not automatically) when I ask for a check-in.
   It proposes CONSTRAINTS.md/CLAUDE.md edits; it never applies them.

### Companion steps (optional but recommended)

- Vague request? Run `mogger:idea` first → SPEC.md → plan from it.
- After tests pass on anything with a UI/server: run the smoke check (see `doing.md`) before reviewer.
- End of each task: dispatch `explainer` for the user. Record lasting choices with `mogger:decisions`.
- Before calling the whole thing finished: `scripts/ship-check.sh` (report only).
- Never assert a fact about the code you have not checked: see `mogger:grounding`.

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
because re-reads are the most common way a session's context quietly
fills up.

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
a subagent repeatedly in a loop (reviewer → fix → reviewer), hand it the
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

## Model routing — the Lead thinks, Haiku reads

Every subagent in this kit has a `model:` line in its frontmatter. The
assignment is deliberate:

| Job | Model | Agent | Why |
|---|---|---|---|
| Read a big file, answer one question from it | **haiku** (`effort: low`) | `bulk-reader` | Reading is I/O, not reasoning |
| Find where code lives, trace a call path | **haiku** (`effort: low`) | `explorer` | Grep + paths, no judgment needed |
| Write boilerplate from an existing pattern | **haiku** (`effort: low`) | `code-writer` | Copying a shape, not designing one |
| Decide library vs hand-rolled | **sonnet** | `library-scout` | Weighing tradeoffs, reading docs, saying no |
| Review a diff for bugs and security | **sonnet** | `reviewer` | Judgment, but bounded — the diff is the input |
| Mine history for repeated mistakes | **sonnet** | `retro` | Pattern-finding across text |
| Orchestrate, make architecture calls | **opus** (or sonnet) | the Lead — you | The only place frontier reasoning earns its price |

**The rule for you, the Lead:** if you're running on Opus, you do not
Read big files or sweep the codebase with Grep yourself. Small files and
the files you are editing are fine. A big file in your context is paid
for at Opus rates and stays there for the rest of the session. Delegate:

- "Where is X?" → `explorer`
- "What does this big file say about Y?" → `bulk-reader`
- "Make a test file like that one" → `code-writer`

Then reason about what they hand back. The hooks enforce part of this
(big Reads are blocked); the rest is discipline.

## Recording runs

After each task clears reviewer, append one entry to RUNS.md. Include the
`tokens:` line — run `/cost` and copy the session figure. This is the only
way anyone (including you) can see what this kit costs on this project.
Claims without this number are just claims.

More on model tiers (the `effort:` dial, model aliases, an Opus Lead, the advisor tool), the
routing log and the routing estimate: `skills/loop/reference.md`. Read it only when you need it.

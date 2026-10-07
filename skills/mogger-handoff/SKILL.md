---
name: mogger-handoff
description: Writes a handoff note from TASKS.md, git and test markers so the next session can continue without chat history. Use before context runs low, at session end, or before compaction.
disable-model-invocation: true
---

# mogger handoff

Long sessions get compacted or hit limits, and the AI then forgets what was
decided and breaks earlier work. A handoff is the memory that survives.

## Two handoffs

- **Automatic**: the `precompact-save.sh` hook writes
  `.claude/state/handoff.md` before every compaction, and session start
  prints it back (if under 72 hours old). You do not write this one.
- **Manual**: `handoff.md` at the project root, from `templates/HANDOFF.md`.
  Write it when:
  - context is running low or the session limit is close,
  - the working day ends,
  - the project goes to a developer or another AI.

## How to write it

Gather facts first, then write. Run these and copy from the output:

1. `TASKS.md`: done and open items, `BLOCKED:` lines, the next open tasks.
2. `git status --porcelain` and `git log -10 --oneline`: what changed, what is uncommitted.
3. `.claude/state/last_test_result.json` and `.claude/state/smoke.json`: the last recorded test and smoke results and when.
4. `DECISIONS.md`: active decisions that constrain the next steps.
5. `SPEC.md` / `TASKS.md` `## Assumptions`: anything still unverified.

Then fill the sections of `templates/HANDOFF.md`, in this order: goal,
done, in progress, next steps, decisions, gotchas, how to run and test.

## Rules

- Every line about the project's state points at evidence: a commit hash,
  a file and line, a command and its result.
- If you did not check it in this session, write `UNVERIFIED:` in front of
  it. Never fill a section with a guess to make it look complete; write
  `none` or `UNVERIFIED: not documented`.
- Do not paste chat text as fact. Chat is where the guesses live.
- In "how to run and test", include how the site goes live, where the
  backup is, and how to roll back. If that is not documented, say so.
- Keep it under one page. The next reader has no context and little time.
- Do not commit secrets or `.env` values into it.

## After writing

Tell the user the file path and list every `UNVERIFIED:` line so they can
answer or check them.

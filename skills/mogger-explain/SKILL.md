---
name: mogger-explain
description: When and how the Lead dispatches the explainer agent to give the user a plain-English note about what changed. Use at the end of every task, and whenever the user says "explain that", "what did you change", or "I don't follow".
---

# mogger explain

The `explainer` agent (Haiku, low effort, read-only) turns a diff into a short
note for a non-expert. It is cheap, so use it freely.

## When the Lead dispatches it

1. **End of each task**, after the reviewer verdict and before you report to
   the user. Hand it the task text from TASKS.md and tell it which diff to
   read (`git diff`, or `git diff <base>...HEAD` for a committed task).
2. **On request.** If the user says "explain that", "what did you just do",
   or asks what something means, dispatch it on the most recent change.
   Do not answer from memory of what you meant to do. The point is that the
   note comes from the actual diff.

## What you pass it

- The task line from TASKS.md (or the user's question).
- The exact diff command to run. Keep it scoped to the task's files.

## What you do with the result

- Show it to the user as is. Do not rewrite it into something friendlier
  that adds claims. If it says "not verified", keep that line.
- If the note is empty or says nothing changed, say so. Do not fill the gap.

## Format it returns

`What changed` / `Why` / `How to check it yourself` / `Watch out`. Every
statement cites a file from the diff.

## Limits

It reads the diff. It does not run the code, so anything about runtime
behavior is marked "not verified". Tests and the reviewer cover that.

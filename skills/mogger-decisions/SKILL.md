---
name: mogger-decisions
description: Append-only DECISIONS.md log of why we chose X. Use when choosing a library/architecture, rejecting an approach, or before proposing something that may contradict an earlier choice.
---

# mogger decisions

`DECISIONS.md` (project root, from `templates/DECISIONS.md`) is the log of
why things are the way they are. Active decisions are shown at session
start so they are not re-argued from scratch.

## When to record

- Choosing a library, framework, architecture, data model, or pattern.
- Rejecting an approach someone might propose again.
- Resolving a dispute between builder and reviewer, or with the user.

Do not record trivia (variable names, formatting) or anything already fully
covered by `STACK.md`, unless the reason is non-obvious.

## How to record

Append a new entry at the bottom, numbered one higher than the last:

```
## #7 — Use SQLite, not Postgres
- Date: 2026-09-29
- Decision: single-file SQLite for storage
- Why: one user, no server to run, backup is a file copy
- Alternatives rejected: Postgres (needs a server); JSON files (no queries)
- Evidence: SPEC.md "Users"; bench: 10k rows read in 4 ms
- Status: active
```

Keep `Why` to one line: it is what the session-start summary prints. Give
evidence you can point at: a link, `file:line`, or a benchmark result. If
there is none, say `Evidence: none, judgment call`.

## Append only

Never rewrite or delete an entry; the `protect-decisions` hook blocks it.
To change your mind, add a new entry that says what it replaces, then flip
the old entry's `Status: active` to `Status: superseded-by #n`. That single
line is the only in-place edit allowed.

## The rule: cite, then ask

Before proposing a change that contradicts an **active** decision, cite it
(`#7`) and ask the user whether to supersede it. Do not silently re-argue,
and do not quietly implement the opposite. New evidence is a reason to ask,
not a reason to skip asking.

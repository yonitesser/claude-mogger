---
name: mogger-idea
description: Spec-first interview for vague or big requests. Use when the user says "mogger idea" or gives an open-ended ask like "build me an app that...". Checks the repo first, asks at most 5 short questions one at a time (each with a default), writes SPEC.md, then hands off to the planner. Skip it when the request is already specific.
---

# mogger idea: spec before plan

A vague request produces a vague plan. This skill turns it into `SPEC.md`,
which the `planner` agent then turns into `TASKS.md`.

## 0. Should this run at all?

Skip the interview when the request already names the thing, the place, and
how to tell it worked (e.g. "add a `--json` flag to `cli.py list`; tests in
`tests/test_cli.py` must pass"). Say "Request is specific, skipping the
interview" and go straight to the planner. Run it when the request is big,
open-ended, or the user said "mogger idea".

## 1. Read before asking

Never ask what the repo can answer. Check `STACK.md`, `CLAUDE.md`,
`README.md`, `package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml`,
existing `SPEC.md`, `TASKS.md`, `DECISIONS.md`. Then state what you found in
two or three lines: "Found: Python 3.12, FastAPI, pytest, SQLite. Not asking
about those." Anything you found goes into SPEC.md as verified.

## 2. Interview rules

- At most **5** questions. Fewer is better. Stop when you can fill the spec.
- **One at a time.** Wait for the answer before the next.
- Short, plain words. No jargon the user did not use first.
- Each question carries a recommended default so the user can answer "yes":
  "Who uses it? I'd assume just you. OK?"
- Ask only about facts you cannot know:
  1. Who uses it, and what are they trying to do?
  2. Must-have vs nice-to-have (offer your own split as the default).
  3. What data it stores or reads, and anything sensitive.
  4. Where it runs, and any budget or time limit.
  5. What "done" looks like, in something you can run or click.
- If an answer is "don't know", take the default and label it `UNVERIFIED:`.

## 3. Write SPEC.md

Copy `${CLAUDE_PLUGIN_ROOT}/templates/SPEC.md` to the project root and fill
it. Sections, in order: Goal (one sentence), Users, Must have, Won't do (this
round), Data, Done when, Assumptions, Open questions.

- Number Must-have items M1, M2... so tasks can trace to them.
- Every "Done when" line is checkable: a command and the expected result
  ("`pytest -q` exits 0 with 12 passed", "`curl -s localhost:8000/health`
  returns `{"ok":true}`"). "Works well" or "is fast" is not a condition;
  rewrite it as a number or an output.
- Every assumption you did not verify by reading or running something is
  prefixed `UNVERIFIED:`. Do not present a guess as a fact.
- Unanswered questions go under Open questions, not into invented answers.

Show the user SPEC.md and ask for a yes or corrections. Do not proceed on
silence.

## 4. Hand off

Once approved, delegate to the `planner` agent: "Read SPEC.md and write
TASKS.md." Do not write code, and do not write TASKS.md yourself. If the
project is new and picks a library or architecture along the way, record it
with the `mogger-decisions` skill.

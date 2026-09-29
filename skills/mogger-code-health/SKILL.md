---
name: mogger-code-health
description: Code-health rules for vibe-coded apps — file and function size limits, no copy-paste, every error handled and logged, timeouts on every outbound call, pagination on every list, indexes on foreign keys, a backup plan, and caps on loops around paid APIs. Says which report-only check to run when (structure, resilience, database, cost-risk). Load before adding features to a growing codebase, before touching the database schema, before calling a paid API, and before shipping.
---

# mogger code health: fine for 5 users, still fine for 500

Vibe-coded apps fail in five predictable ways: one giant file with pasted
copies, a weak database, code that breaks at scale, silent failures, and
uncontrolled API bills. Two hooks catch the worst cases as you write;
four report-only checks audit the rest. Every finding cites `file:line`;
anything labelled "(heuristic)" is a pattern match, so read the line before
acting on it.

## The rules

1. **Size.** A file over 500 lines is a warning, over 1000 a failure, and the
   hook blocks a write that leaves a file over 800 (`MOGGER_MAX_FILE_LINES`).
   Functions and components stay under about 80 lines. Split by
   responsibility (routes, data access, validation, UI), not by "part 2".
2. **No copy-paste.** The same 8+ lines in two places become one function
   or module. The hook blocks a newly pasted 10-line block in the same file.
3. **Handle every error, and log why.** No empty `catch`, no `except: pass`,
   no `.catch(() => {})`. Log with context, handle it, or re-throw. If
   ignoring is intended, say so: `// ignore: <reason>` (Python `# ignore:`).
4. **Timeouts on every outbound call.** fetch, axios, requests and http
   clients get an explicit timeout or abort signal. Retries have a maximum
   attempt count and backoff.
5. **Pagination on every list.** No `findMany()` or `SELECT *` without
   `take`/`LIMIT`/paging. No query or API call inside a loop (N+1): fetch
   in one query, then group in memory.
6. **Know when it is down.** Use a logging library (not bare `console.log`),
   an error tracker (Sentry, Rollbar, Datadog, OpenTelemetry) and a
   `/health` endpoint an uptime monitor can poll.
7. **Database design.** Every table has a primary key; every foreign key
   column has an index (Postgres does not add one); rules like "email is
   unique" and NOT NULL live in the schema, not only in app code; schema
   changes go through migrations; Supabase tables enable row level security.
8. **Backups.** Have a written backup plan and test a restore. Hosted
   databases often back up automatically; confirm it and write it down.
9. **Cap anything that costs money.** No paid API call inside an unbounded
   loop, recursion, or retry. Set `max_tokens` on every LLM call, rate-limit
   public routes that trigger paid calls, never ship an API key to the
   browser, and set a spend limit in the provider dashboard. That last step
   is manual and cannot be verified from code.

## When to run which check

All are report-only (exit 0, print `LEVEL|check-id|message`) and take an
optional project directory:

| Situation | Run |
|---|---|
| A file or feature keeps growing; before a refactor | `bash scripts/checks/structure.sh` |
| Before adding routes, jobs or integrations; before a demo or launch | `bash scripts/checks/resilience.sh` |
| Before or after touching models, migrations or the schema | `bash scripts/checks/database.sh` |
| Before first calling a paid API; before publishing a public route that reaches one | `bash scripts/checks/cost-risk.sh` |
| Before shipping | all four, then fix FAILs and read each WARN |

Hooks (automatic, after Edit/Write): `check-structure.sh` blocks a file over
the line limit or a newly pasted 10-line block; `check-resilience.sh` blocks
an empty catch/except with no `ignore:` reason. Off-switches:
`MOGGER_CHECK_STRUCTURE=off`, `MOGGER_CHECK_RESILIENCE=off`.

## Working with findings

- Cite the finding's `file:line` when you report or fix it. Do not claim a
  problem exists that no check or read of the file showed.
- Fix FAILs first, then WARNs that touch user data, money or uptime.
- A WARN you decide to keep gets a one-line reason in the code or in
  DECISIONS.md, not silence.

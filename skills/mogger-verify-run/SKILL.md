---
name: mogger-verify-run
description: Confirms the app actually runs (not just tests) with scripts/smoke-check.sh and the verifier agent. Load before calling a UI, server or CLI task done.
---

# Verify it runs

Tests passing is not the same as the app working. Before you call a UI, API,
server, or CLI task done, prove it starts and responds.

## When
After `tester` records a full-suite pass, before `reviewer` (or before you say
"done" if the task has no review step). Skip for docs-only or pure-refactor
changes with no runtime surface, and say you skipped.

## How
Delegate to `verifier` (Haiku). It runs `scripts/smoke-check.sh`, which:
- resolves the start command: `MOGGER_SMOKE_CMD` (a command that must exit 0,
  for CLI/library projects), else `MOGGER_RUN_CMD`, `.claude/mogger.json`
  (`run`, `url`), STACK.md lines `run:` / `url:`, else autodetect
  (package.json `dev`/`start`, Makefile `run`, uvicorn/flask/django);
- starts it, polls the URL until 2xx/3xx (default 30s, `MOGGER_SMOKE_TIMEOUT`);
- scans output for Traceback, `Error:`, Cannot find module, EADDRINUSE,
  unhandled rejection, HTTP 500;
- always kills the process tree, then writes `.claude/state/smoke.json`.

If the autodetected command or URL is wrong, record the right ones once in
`.claude/mogger.json` or STACK.md instead of retrying.
Optional: `MOGGER_SMOKE_SCREENSHOT=on` adds console errors + `smoke.png` when
Playwright is installed; otherwise it is skipped with a note.

## Reading smoke.json
`{ok, url, status, seconds, errors[], cmd, ts, notes[], browser_errors[]}`
- `ok:true` requires a 2xx/3xx AND no error signatures in the output.
- `status` is the HTTP code, `exit N` for command mode, or `timeout` /
  `no-command`.
- `errors[]` are verbatim log lines. `browser_errors[]` are informational.

## Reporting
Report evidence, not adjectives. Say "GET http://localhost:3000 -> 200 in 4s,
no error lines", not "the app works". On failure quote the exact `errors[]`
lines and send them to `builder`; same 2-fix-pass cap as the test loop.

## Optional gate
`MOGGER_REQUIRE_SMOKE=on` makes `require-smoke-pass.sh` block `reviewer` until
smoke.json is ok:true and newer than the last source edit. Default off, so
projects without a runnable app are never wedged.

This tooling is report-only. It never pushes or deploys; that gate stays human.

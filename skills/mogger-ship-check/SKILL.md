---
name: mogger-ship-check
description: Use when asked "is this ready to ship?" or all TASKS are done. Report-only.
disable-model-invocation: true
---

# Ship-readiness checklist

`bash scripts/ship-check.sh` (add `--strict` to exit 1 on any FAIL, e.g. in CI).

**It NEVER pushes, merges, tags, or deploys.** It reads the repo and prints
PASS / WARN / FAIL / SKIP with evidence. The push/deploy decision stays with
the human; hand them this output and wait.

## What it checks
| Check | Level on problem |
|---|---|
| Full test suite recorded green and not stale (`last_test_result.json`) | FAIL |
| `.claude/state/smoke.json` ok (SKIP if never run) | FAIL |
| No AWS key / `ghp_` / `sk-ant-` / private key block in tracked files | FAIL |
| `.env` not tracked; `.gitignore` covers it | FAIL / WARN |
| No TODO/FIXME/console.log/debugger/print( in files changed vs default branch | WARN |
| Lockfile present and committed | FAIL |
| README exists | FAIL |
| 404/error-page handling mentioned (web projects, heuristic) | WARN |
| Mobile viewport meta in HTML entrypoints (web projects, heuristic) | WARN |
| Working tree clean | WARN |
| TASKS.md has no open tasks | FAIL |

CONSTRAINTS.md violations are not checked here; that is the reviewer's job.

## Using it
1. Run tester (full scope), then verifier, then ship-check.
2. Show the human the output verbatim. Do not summarize FAILs into "mostly good".
3. Fix FAILs through the normal builder/tester loop; WARNs are the human's call.
4. Never run push, merge, or deploy commands, even if everything passes.

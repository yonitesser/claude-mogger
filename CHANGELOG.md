# Changelog

## 1.0.1 — 2026-09-09

**Fixed**
- `tests/hooks.test.sh`: the `bash_cmd` test helper unconditionally shelled
  out to `python3` to build sample JSON, even when `jq` alone was sufficient.
  On Windows, `python3` on PATH is frequently a Microsoft Store stub that
  prints an install nag and exits without running anything — this silently
  produced empty/broken test input and made working hooks look like they'd
  failed. Helper now prefers `jq -Rs`, falls back to a verified-executable
  `python3`, then a pure-bash escape — never trusts `python3` presence alone.
- `hooks/scripts/lib.sh`: `json_get` now probes `python3 -c '1'` before
  trusting it as a fallback, for the same reason — a real hook running on
  a Windows machine with no `jq` installed would otherwise fail open
  (parse nothing, block nothing) without any warning.
- `session-start.sh`: dependency check updated to use the same probe, and
  now explicitly recommends installing `jq` on Windows rather than relying
  on `python3`.

## 1.0.0 — 2026-09-09

First plugin release.

**Added**
- Plugin shape (`.claude-plugin/plugin.json`, `marketplace.json`); installable via `/plugin marketplace add`.
- Three skills: `mogger-loop`, `mogger-standards`, `mogger-init`.
- `session-start` hook — injects CONSTRAINTS.md, STACK.md, and TASKS.md status into context automatically.
- `stop-done-means-done` hook — blocks ending the turn with open tasks and no recorded blocker.
- `explorer` agent (Haiku) — codebase navigation so the Lead never greps.
- `tests/hooks.test.sh` — 43 assertions across all 8 hooks.
- `hooks/scripts/lib.sh` — jq with python3 fallback; protected-branch helper.
- `tokens:` field in RUNS.md entries, sourced from `/cost`.
- `scripts/sync-incoming.sh` — regenerates the manual-install mirror from the plugin.
- CURATION.md, CONSIDERED.md, CHANGELOG.md, MIT LICENSE.

**Fixed**
- `require-approval`: money regex no longer blocks `cat payment_service.py` or `grep invoice` — only actual billing/payment CLIs.
- `require-approval`: `git merge` only blocked while *on* a protected branch; merging main into a feature branch is allowed.
- `require-tests-pass`: removed dead `date -d` code (GNU-only, unused); stale check now ignores node_modules/.venv/target/dist/build and RUNS.md/TASKS.md.
- `tester` moved from Sonnet to Haiku — it runs a command and writes a JSON file.
- Depersonalized all text for sharing.

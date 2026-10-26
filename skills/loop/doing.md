# Doing a task: build, test, smoke

Read when you start building. These rules used to live in the builder, tester and
verifier agents. You do the work in your own context, so nothing is lost in a hand-off.

## Build (one task at a time)

1. Do exactly the task. No "nice to have" work outside it.
2. Follow the conventions of the files nearby. No new pattern, library or style unless the task says so.
3. Edit only the files in the task's `files:` list (a hook blocks the rest). Need another file? Change `files:` in TASKS.md on purpose; do not work around it.
4. Check an edit with `git diff -- <path>`, never by re-reading the file.
5. Task marked `[library-scout first]`: run the `library-scout` agent first and follow it. "Write it yourself" is a real answer.
6. Before you call or import any symbol, verify it exists (grep, or docs via Context7); see `mogger:grounding`. Anything unverified: label `UNVERIFIED:` and add it to `## Assumptions` in TASKS.md.
7. Mark the task `- [x]` only after it is done. Do not commit or push unasked.

## Test

1. Find the project's real test command (package.json, Makefile, CI config). Do not guess.
2. While building, run only the tests for the changed files: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/related-tests.sh"` prints `scope:` and `command:`. Run that command. It says `full` itself when it cannot narrow. No output and exit 1 means the project has no test command: say so.
3. Once before review, run the FULL suite. An affected-only pass does not clear review.
4. Run the tests through Bash, so the hook records the real result (`.claude/state/test-evidence.json`; you cannot write that file). Take the exit code from `$?`, not from the text.
5. Then write `.claude/state/last_test_result.json` (the review gate reads it, and also needs the hook's record to say pass):
   `{"status": "pass", "exit_code": 0, "scope": "affected|full", "timestamp": "<ISO8601 now>", "command": "<what you ran>"}`
   Use `"status": "fail"` with the real exit code on failure. Never write "pass" unless the exit code was 0.
6. On failure, quote the real error, fix the cause, run again. Two fix passes for the same task, then stop and ask the human.
7. A task that touches input or I/O needs a test for each unhappy path in its `done when:` (see `mogger:edge-cases`), and you must confirm it ran, not skipped. Only the happy path tested: say "happy path only", never "clean pass".

## Smoke (UI or server tasks)

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/smoke-check.sh"` (or `scripts/smoke-check.sh`) and read `.claude/state/smoke.json`. Report `SMOKE: PASS|FAIL`, the url, status, and the error lines verbatim. The script writes smoke.json from real exit codes; never write `ok: true` yourself.

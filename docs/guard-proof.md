# Guard proof table

Each guard in `hooks/guards.tsv`, the test files that name it, and any A/B result we have.
Why this exists: "delete rules you cannot prove help" (harness advice). A guard is judged by the damage it stops, not only by an A/B win, so a guard with no A/B stays.

How the table was made: a test file is listed when it contains the guard name or its env var (`grep`). This shows a test refers to the guard. It does not prove each test blocks the exact case; open the file to check.
Rebuild it when `hooks/guards.tsv` changes (counts drift, recount).

A/B results we have (mogger vs plain Claude, small runs, our own data; see `/mnt/project-files/ab-long/vs-plugins/SUMMARY.md`):
- `secret-guard`: blocks a secret written into code, 3 of 3 runs. Plain Claude and 3 other plugins: 0 of 3.
- `claim-check` (model-judged "always" mode): cost +62%, no gain. Not a reason to cut it; it is a reason not to run it always.
- Mogger costs about 20-65% more per run than plain Claude. No guard here is a saving.

Why prose is not enough: a study of public CLAUDE.md files found only 4.4-16.6% of the security rules matched a built-in Claude Code control; hooks were not counted and the study did not test hooks (arXiv 2608.23550, Ting Yan). Hooks are the extra code that fills the gap.

| Guard | Env var | Kind | Default | Tests that name it |
|---|---|---|---|---|
| `danger-guard` | `MOGGER_DANGER_GUARD` | safety | on | `ask.test.sh` `config.test.sh` `failclosed.test.sh` `hooks.test.sh` `hygiene.test.sh` `newguards.test.sh` `prefs.test.sh` |
| `secret-guard` | `MOGGER_SECRET_GUARD` | safety | on | `evals-ab.test.sh` `failclosed.test.sh` `hygiene.test.sh` `mogger-events.test.sh` `newguards.test.sh` `safety-net.test.sh` |
| `secret-read-guard` | `MOGGER_SECRET_READ` | safety | on | `ask.test.sh` `failclosed.test.sh` `hooks.test.sh` `hygiene.test.sh` |
| `config-guard` | `MOGGER_CONFIG_GUARD` | safety | ask | `ask.test.sh` `failclosed.test.sh` `hooks.test.sh` `hygiene.test.sh` |
| `push-guard` | `MOGGER_PUSH_GUARD` | safety | on | `ask.test.sh` |
| `merge-guard` | `MOGGER_MERGE_GUARD` | safety | on | `ask.test.sh` |
| `deploy-guard` | `MOGGER_DEPLOY_GUARD` | safety | on | `ask.test.sh` |
| `money-guard` | `MOGGER_MONEY_GUARD` | safety | on | `ask.test.sh` |
| `taint-guard` | `MOGGER_TAINT` | safety | on | `hygiene.test.sh` `newguards.test.sh` |
| `verify-packages` | `MOGGER_VERIFY_PACKAGES` | safety | on | `hygiene.test.sh` `newguards.test.sh` `safety-net.test.sh` |
| `package-osv-check` | `MOGGER_OSV` | safety | on | `newguards.test.sh` |
| `scope-guard` | `MOGGER_SCOPE_GUARD` | safety | on | `hooks.test.sh` |
| `test-gate` | `MOGGER_STOP_TESTS` | safety | on | `gates.test.sh` `pentest.test.sh` |
| `tests-added` | `MOGGER_TESTS_ADDED` | safety | on | `gates.test.sh` `hygiene.test.sh` |
| `test-evidence` | `MOGGER_EVIDENCE` | safety | on | `evidence.test.sh` `hooks.test.sh` `hygiene.test.sh` |
| `test-tamper` | `MOGGER_CHECK_TAMPER` | safety | on | `gates.test.sh` `tamper.test.sh` |
| `claim-check` | `MOGGER_CLAIM_CHECK` | safety | on | `config.test.sh` `gates.test.sh` |
| `checkpoint` | `MOGGER_CHECKPOINT` | safety | on | `companion.test.sh` `continuity.test.sh` `mogger-events.test.sh` `safety-net.test.sh` |
| `payments-check` | `MOGGER_CHECK_PAYMENTS` | safety | on | `security.test.sh` |
| `risky-code-check` | `MOGGER_CHECK_RISKY` | safety | on | `security.test.sh` |
| `decisions-lock` | `MOGGER_DECISIONS_LOCK` | standard | on | `planning.test.sh` |
| `read-guard` | `MOGGER_READ_GUARD` | standard | on | `ask.test.sh` `failclosed.test.sh` `hooks.test.sh` `hygiene.test.sh` |
| `references-check` | `MOGGER_CHECK_REFERENCES` | standard | on | `grounding.test.sh` |
| `resilience-check` | `MOGGER_CHECK_RESILIENCE` | standard | on | `code-health.test.sh` |
| `structure-check` | `MOGGER_CHECK_STRUCTURE` | standard | on | `code-health.test.sh` |
| `test-quality-check` | `MOGGER_CHECK_TESTS` | standard | on | `testing.test.sh` |
| `fix-loop-guard` | `MOGGER_FIX_LOOP_GUARD` | standard | on | `testing.test.sh` |
| `repeat-call-guard` | `MOGGER_REPEAT_GUARD` | standard | on | `hooks.test.sh` |
| `hint-noisy-bash` | `MOGGER_HINT` | standard | on | `ask.test.sh` `config.test.sh` `hooks.test.sh` `hygiene.test.sh` `related-tests.test.sh` |
| `config-notice` | `MOGGER_CONFIG_NOTICE` | standard | on | `newguards.test.sh` |
| `handoff-note` | `MOGGER_HANDOFF` | standard | on | `continuity.test.sh` |
| `track-edits` | `MOGGER_TRACK_EDITS` | standard | on | `gates.test.sh` |
| `voice` | `MOGGER_VOICE` | standard | on | `code-health.test.sh` `config.test.sh` `hooks.test.sh` `security.test.sh` |
| `smoke-gate` | `MOGGER_REQUIRE_SMOKE` | optin | off | `config.test.sh` `run-check.test.sh` |
| `gate-all-tasks` | `MOGGER_GATE_ALL_TASKS` | optin | off | `hooks.test.sh` `run-check.test.sh` |
| `scope-parallel` | `MOGGER_SCOPE_PARALLEL` | optin | off | `hooks.test.sh` |
| `related-tests` | `MOGGER_RELATED_TESTS` | standard | on | `related-tests.test.sh` |
| `pentest` | `MOGGER_PENTEST` | optin | off | `context-budget.test.sh` `pentest.test.sh` |

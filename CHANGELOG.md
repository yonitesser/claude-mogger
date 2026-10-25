# Changelog

## Unreleased

- Lean companion step, from the mogger vs Superpowers A/B (`/mnt/project-files/ab-long/vs-plugins/`). (1) The session rule line gains five short rules taken from what Superpowers did well: test first, find the cause before the fix, plan multi-step work in 3 lines, and run mail or message senders with `--dry-run` first. +150 characters per session (about 40 tokens); `MAX_SESSION` in `tests/context-budget.test.sh` goes from 1980 to 2120. (2) New guard `send-guard` (`MOGGER_SEND_GUARD`, default `ask`, also `on`/`off`): `require-approval.sh` asks before a mail tool (`sendmail`, `mail`, `mutt`, `swaks`, `msmtp`), a Slack/Discord/SendGrid/Mailgun/Postmark call, or a script named send/remind/notify/blast/mailer, unless the line has `--dry-run`, `--dry`, `--check`, `--preview` or `-n`. Where no prompt can be shown it blocks. Plain text match, a seat belt, not a sandbox. In the A/B, every arm but Superpowers sent real customer email in the reminder trap. Tests: 8 in `tests/ask.test.sh`. Not yet shown to help in a paid A/B.

- The status bar shows a `tests: pass` or `tests: fail` line under the detail line. It reads the newest test run from `.claude/state/test-evidence.json`, which `record-test-run.sh` already writes; it shows nothing before the first test run, and the Detail line switch hides it. The on/ask/off guard dropdowns are unchanged. It reads one small file: no cost, no tokens. Tests: `testsOf` cases in `mods/mogger-status/hooks/log.test.ts`, 2 checks in `tests/hygiene.test.sh`. Counts: 28 suites, 3,139 assertions.

- Two fewer skills, same behaviour. `mogger:explain` is gone: the `explainer` agent description now says when to use it, and `loop` already dispatches it at task end. `mogger:superpowers-preset` moved from a skill to `docs/superpowers-preset.md` (a plain doc; nothing in it changes). Both cost description text on every turn; they now cost none. No guard, hook or test habit was cut. Three short rules from ponytail went into `mogger:standards` (fix a bug at every caller, name the shortcut, say what you skipped); see `CONSIDERED.md`. Thought behind it: a thread on newer models doing better with less process. Not tested as a quality gain.

- New opt-in `pentester` agent and `mogger:pentest` skill: it runs your app on localhost and sends real attacks (no login, user A reading user B's data, bad input, injection, leaked secrets, double submit), then reports only the bugs it proved, each with the exact request and the cause at `file:line`. It never edits code; `builder` fixes, then the same request is sent again. Off by default: new optin guard `pentest` (`MOGGER_PENTEST=on`). `pentest-gate.sh` blocks the agent while it is off. Every request goes through `scripts/pentest-probe.sh`, a curl wrapper that refuses any host but localhost, 127.0.0.1 and [::1] (also `user@host` and look-alike hosts), redirects, proxies, a second URL and a few other options; it is a speed bump, not a sandbox. It costs tokens, and mogger is not cheaper with it on. Idea from usestrix/strix (judged in `CONSIDERED.md`); Strix itself is not bundled. The context ceiling `MAX_ALWAYS` in `tests/context-budget.test.sh` goes from 7600 to 7900: the two new descriptions add 360 characters to every turn. Tests: `tests/pentest.test.sh` (50). Counts: 28 suites, 3,137 assertions, 45 hook entries, 21 skills, 15 agents, 38 guards.

- `reviewer` now notes one-way doors (migration, delete, public API change) and swallowed errors, for the human only; it never makes a READY verdict easier. Idea from warpdotdev/common-skills `merge-risk`, judged IDEAS TAKEN in `CONSIDERED.md`; its risk score was skipped, so the merge block stays a hook. Test: `tests/planning.test.sh`.

- `scripts/checks/lockin.sh` sorts its file list, so the cited evidence is the same on every machine. A CI run had failed once on ubuntu because `find` listed the files in a different order. Test: `tests/hygiene.test.sh`.

- `security-reviewer` has a new HARDENING NOTES section: a weak spot with no attacker path you can trace is listed there with no severity, not as CONFIRMED. NEEDS-HUMAN must name the one fact still unknown. Idea from cloudflare/security-audit-skill, which is judged OPTIONAL in `CONSIDERED.md` (not bundled). Test: `tests/security.test.sh`.

- Smart test selection. New `hooks/scripts/related-tests.sh` (not a hook; the tester agent and the hint call it) reads the changed files (git, else `.claude/state/edits.log`) and prints `scope: affected|full` and the command to run. It uses the project's own tool when there is one (`jest --findRelatedTests`, `vitest related`); otherwise it maps each changed file to the tests that sit with it or name it (an import, a folder name for `index` files, same-folder `_test.go`) and runs those with pytest, `go test`, mocha, jest, vitest or `bash`. It says `full` itself when a changed file has no test, when config, a lockfile or docs changed, when the runners are mixed, or when nothing changed. No dependencies. The full suite is untouched: `stop-tests-added.sh` still runs it before "done" and `require-tests-pass.sh` still wants a `full` pass before review. New standard guard `related-tests` (`MOGGER_RELATED_TESTS=off` makes every run full). The `tester` agent and `loop` skill use it; `hint-noisy-bash.sh` points at it when a bare `npm test`, `pytest`, `go test` and the like runs mid-task. `mogger_test_cmd` moved from `stop-tests-added.sh` to `lib.sh` so both share it. Tests: `tests/related-tests.test.sh` (24). Counts: 27 suites, 3,084 assertions, 37 guards.

- Fewer false blocks on text that only mentions a danger. A commit message, `gh pr create --body` or `echo` that said "git reset --hard", "rm -rf /" or "pip install some-name" was read as that command. New `mogger_prose_free` in `lib.sh` takes out heredoc bodies fed to `$(cat <<EOF` or `-F -`, and quoted spans that contain whitespace, before `danger-guard.sh` and `verify-packages.sh` look. It does nothing when something could run the quoted text (`bash -c`, `eval`, `ssh`, `python -c`, `$(`, backticks, `docker`, `xargs` and more): then the old strict reading stays. The SQL check and the `rm -r` target check still read the full text. The package check now also sees `bash -c "pip install x"`. Tests: `tests/hooks.test.sh` (13 cases both ways), `tests/safety-net.test.sh` (4).
- Edit hooks are cheaper. `check-risky-code`, `check-diy-payments`, `check-resilience` and `check-structure` now stop early, in plain bash, when the file has none of the words their rules need (or, for structure, the file is under its limit and the new text is under 10 lines). A clean edit to a small file: the four hooks went from 129 ms to 68 ms in total on this box, and from about 40 process spawns to 15. Same rules; a risky file still reaches them (upper-case and mixed-case cases are tested). New helper `mogger_text_maybe` in `lib.sh`. Tests: `tests/hygiene.test.sh`.
- Shorter `loop` skill: 292 to 190 lines. The `effort:` dial, the model-alias note, "does the Lead still need Opus", the advisor tool, the routing log and the routing estimate moved to `skills/loop/reference.md` (read only when needed). The loop steps and the Lead rules stay. Counts: 26 suites, 3,060 assertions, 44 hook entries, 20 skills, 14 agents.
- Checked and left alone. One hook dispatcher: hooks already run side by side, each takes about 12 ms, and about 8 ms of that is bash start-up, `jq` and `lib.sh`, so a dispatcher saves little and puts every guard in one failure domain. Pinning `actions/checkout` to a commit SHA: this session cannot read that repository.

- Hook speed. The ten PreToolUse Bash hooks spawned 104 processes for a plain `ls -la` and now spawn 29 (measured with strace); the same ten, run one after another, went from about 340 ms to about 110 ms on this box. Same checks, same results. How: bash builtins instead of a grep/sed/tr fork per check (`mogger_re` in `lib.sh`, `shopt -s nocasematch` in place of lower-casing), one `jq` call per hook for all its fields (`json_fields` in `lib.sh`), no `dirname` fork (`${0%/*}`), a free prefilter so `require-approval` skips its python normaliser and `secret-guard*` skip their per-pattern greps when the text names no tool or key prefix, and the guard list is read once per call. Tests: `tests/hygiene.test.sh` (fork-free check and a process-count limit when `strace` exists), new upper-case and multi-line cases in `tests/hooks.test.sh`.

- Audit fixes (report: `research/mogger-audit-2026-10-18.md` in the project files). `verify-packages.sh` no longer reads `2>&1` or `> file` as a package named `2`. `incoming/` agents now use manual-install paths (`.claude/hooks/`, `checks/`) instead of `${CLAUDE_PLUGIN_ROOT}`. With `MOGGER_PUSH_GUARD=off`, `require-approval.sh` also catches `-uf`, `--forc` and `--del`. `taint-guard.sh` judges the URL host, so `evil.example/?r=localhost` still asks. `config-guard.sh` ignores `2>/dev/null` and `2>&1`. The Stop test run (`stop-tests-added.sh`) now defaults to 50 s, inside its 60 s hook limit. `check-test-quality.sh` no longer leaks a temp file per edit. CI gets `permissions: contents: read`, a 20 minute limit and cancel-in-progress.
- More audit fixes, each with a test. The approval gate now sees `gh -R o/r pr merge`, `gh api .../merge`, `kubectl -n x apply`, `terraform -chdir=d apply`, `npm -w p publish`, `docker --context c push`. A safety guard set to `off` in a mogger toggle file that git tracks is ignored (a cloned repo cannot switch your guards off; use an env var or an untracked file). `secret-read-guard` catches reads of a secrets file inside `$(...)`, inside `(...)`, through `git show HEAD:<file>`, and through `cp`/`mv` of it. `secret-guard-bash` blocks a named-format key (`ghp_`, `AKIA`, `sk-ant-`) typed into any shell command, and sees `git -C . add`. The taint file survives a compact or resume. Path rules (`protect-pipeline-files`, `check-structure`, `check-resilience`, `check-risky-code`) judge the path inside the project, so a project living under `/work/payments-app/` is not blocked. `scope-guard` accepts space lists and ` - ` / ` -- ` separators in `files:`. `head -c N` counts as a bounded read. Config toggles read the guard list once, not once per key. `savings-report` says "price gap", not "avoided spend". The `standards` skill is 125 lines (companion comparisons moved to `skills/standards/companions.md`). The session-start rule text keeps its quotes around "done". `scripts/sync-incoming.sh` builds aside and has `--check`; CI runs it and shellcheck.

## 1.11.2 — 2026-10-16

- Five short rules for apps that handle real money and real users, from a "before a paying customer" checklist. I checked each against the repo first; none existed. `code-health` rule 7 now says: migrations have a down/rollback step; money is integer cents or DECIMAL, never float; timestamps are UTC (`timestamptz`); user-created records get a soft delete (`deleted_at`). `edge-cases` duplicate-submit row now says: payments and webhooks use an idempotency key, and each webhook event id is stored so repeats are skipped.
- New check id `db-money-float` in `scripts/checks/database.sh`: WARN when a column named like price, amount, total, balance, cost, fee, salary or revenue is typed float/double/real (SQL, Prisma, Django/SQLAlchemy, TypeORM, Drizzle). Heuristic by name. 4 new checks in `tests/code-health.test.sh`.
- Counts: 26 suites, 2,965 assertions, 44 hook entries.

## 1.11.1 — 2026-10-12

- `mogger-status` fixes from live use on the desktop app. (1) The robot looked broken: half-block text rows get a line gap there. On the desktop, editor and phone it is now one picture (`Svg`); the terminal keeps the text rows. (2) The Guards button showed no toggles: it ran `mogger-config.sh list`, which needs `jq`, and showed nothing when that failed. The panel now reads `hooks/guards.tsv` and the switch file itself (no command, no `jq`), shows one dropdown per guard (on, ask, off; safety guards only on or ask), writes the same file, and says why when it cannot read. A test checks the panel's states against the script's `list` for all 36 guards. (3) Clicks were lost: the bar redrew every 2 seconds and on every blink, which can land between press and release. It now redraws only when something changed (once a minute for the age text), and the desktop robot does not blink. (4) `Bar` is now `Display`, opens with "What this bar shows", with Robot and Detail line dropdowns. Buttons carry an arrow and the main two use the primary style. The mod API has no cursor setting, so the pointer cannot change over a button; that is not fixable from a mod. Tests: `mods/mogger-status/hooks/*.test.ts` (31).

## 1.11.0 — 2026-10-12

- Shorter skill names. The 20 skills lost the repeated word: `/mogger:mogger-init` is now `/mogger:init`, `mogger:mogger-config` is `mogger:config`, and so on. Folders under `skills/`, the `name:` field, every reference, `evals/triggers.json` and the tests moved with them. Scripts keep their names (`scripts/mogger-config.sh`, `scripts/mogger-rewind.sh`). Anything you saved that calls the old long name needs the short one.
- First-run prefs prompt gets one line: for long sessions, `/autocompact 400k` makes Claude Code compact earlier (undo: `/autocompact auto`). Mogger only tells you. It does not change your settings. No A/B data yet on whether this helps accuracy.

## 1.10.0 — 2026-10-12

- First-run preferences prompt. New SessionStart hook `prefs-notice.sh`: on the first load of mogger in a project it tells Claude to say, in two sentences, that every guard can be on, ask or off, and to ask once with a question: "Keep the defaults" or "Review my guard choices". On Review, Claude loads the `mogger-config` skill. A marker `.claude/state/prefs-shown` makes it show once only. It never blocks: it is context text, and with no answer Claude keeps the defaults and does the task. It stays silent, and writes no marker, where nobody can answer (`CLAUDE_CODE_ENTRYPOINT` `sdk-*`, `MOGGER_HEADLESS=on`, `permission_mode` `bypassPermissions`, `dontAsk` or `auto`), so evals and CI runs are not touched. It also stays silent when `.claude/mogger.json` exists. Off: `MOGGER_PREFS_PROMPT=off`. Test: `tests/prefs.test.sh` (15 checks).
- `mogger-status` mod: the chad is redrawn as a robot (pale head, orange glowing eyes, black armour, orange chest asterisk) and the hat is gone. It is pixel art in 6 rows of text, 15 cells wide: two pixel rows per text row with half blocks and a background colour. Eyes blink when idle and glow red or yellow on a block or warning; the chest asterisk flips between plus and x while a guard fires. The band is not limited to 3 rows by the engine: it may take up to half the terminal in fullscreen, the whole height otherwise, and scrolls beyond that. Tests: `mods/mogger-status/hooks/*.test.ts`.
- `mogger-status` bar buttons. Under the text: `Guards` (a chip per changeable guard; a press cycles on, ask, off through the states the guard allows; it runs `scripts/mogger-config.sh set`, so the switch file stays the one source of truth), `Bar` (robot and detail line on or off, kept across sessions) and `Hide`. Safety guards never go off from a button and `--confirm` is never passed: they only move between on and ask, and going off stays in `/mogger:mogger-config` with its warning. A guard set by an env var is not offered. If the script fails the bar shows a toast. The mod now runs one command (that script) and stores two switches; its README safety section says so. Tests: `mods/mogger-status/hooks/panel.test.ts` and `register.test.ts`.
- Robot redrawn again, less skull: dark visor with glowing eyes, orange headphones, forehead line, narrower jaw, no nose or teeth.
- Counts: 26 suites, 2,961 assertions, 44 hook entries.
- Third guard state: **ask**. A guard is now `on` (block), `ask` (you get a permission prompt each time; Claude cannot answer it) or `off` (allow). `{"push-guard": "ask"}` in `.claude/mogger.json`, `MOGGER_PUSH_GUARD=ask`, or `mogger-config.sh set push-guard ask`. `ask` needs no `--confirm`: you still decide every time. Going to `off` on a safety guard still warns first. Defaults are unchanged: nothing is `ask` until you pick it.
- Ask-capable guards: `danger-guard`, `secret-read-guard`, `config-guard` (already asked; now also in the list), and four new rows that split the old approval gate: `push-guard` (`git push` and the GitHub tools that commit to a branch), `merge-guard` (PR merge, merge on a protected branch, auto-merge, deletes), `deploy-guard`, `money-guard`. These four take `on` or `ask` in the file; `off` is not offered (the script refuses it and a hand-written `off` is ignored). Only a human can allow them for good, with the env var (`MOGGER_PUSH_GUARD=off`, `MOGGER_DEPLOY_GUARD=off`, `MOGGER_MONEY_GUARD=off`). Force pushes and pushes to protected branches stay blocked in every state. `MOGGER_ALLOW_PUSH=on` still works and means `MOGGER_PUSH_GUARD=off`; it never weakens `ask`. Other guards stay on or off, and `mogger-config` refuses `ask` for them.
- Fail safe: where a prompt cannot be shown (`permission_mode` of `bypassPermissions`, `dontAsk` or `auto`; `CLAUDE_CODE_ENTRYPOINT` `sdk-*`; or `MOGGER_HEADLESS=on`), `ask` blocks. `config-guard` does the same now, instead of asking into the void. A bad value in the file or env keeps the guard default.
- `hooks/guards.tsv` gets two columns: `states` (allowed values) and `if ASK`. `mogger-config.sh list` shows state, allowed states and the ON, ASK and OFF text. Shared helpers `mogger_state`, `mogger_can_ask`, `mogger_ask_json` in `hooks/scripts/lib.sh`.
- `config-guard` now also asks before Claude edits `.claude/mogger.json`, so Claude cannot flip a switch in that file without you. The smoke settings kept in the same file (`run`, `url`, `smoke_cmd`) prompt too. The `mogger-config` script writes the file itself and does not prompt.
- Tests: new `tests/ask.test.sh` (75 checks: ask returns the ask decision, off allows, on blocks, bad value, env over file, no-prompt contexts, force push and chained commands, config script).

## 1.9.1 — 2026-10-12

- Plugin audit. Every hook now has a `timeout` (15 to 30 seconds; the Claude Code default is 600), so a stuck script cannot freeze a session. Test: `tests/hygiene.test.sh`.
- Fix: the big-file Read guard blocked a ranged read (`offset`/`limit`) of a big file, and sent Claude to a subagent for a few lines. A `Read` with `limit` of 350 or less, and `head`/`tail -n N` with N of 350 or less, now pass. Tests: `tests/hooks.test.sh`.
- Fix: `claude plugin validate --strict` failed on master because the mod state key `mogger.voice` was not declared in `mods/mogger-status/types/index.d.ts` (one line added; a test now checks every state key is declared).
- Marketplace entry: duplicate `safety` tag removed. `plugin.json` gets `documentationUrl` and `supportUrl` for the directory listing. Fifteen scripts that lacked the executable bit now have it (a test checks all).
- Voice: mogger now has a character: smug, dry, clever, never mean. (1) The `mogger-status` mod picks a one-liner from a pool of 8-10 lines per moment (block, warn, handled, tests passed, false "done" caught, idle, back to quiet), e.g. "Not on my watch.", "Nice try.", "Proof or it did not happen.", "Green. Obviously." The pick is a plain rotation by event count, so a line never repeats back to back. No model calls, no tokens. The toast keeps the facts first and adds the quip after ("mogger blocked git push. Hard pass."). (2) `session-start.sh` adds one 169-character line (about 42 tokens, once per session) that describes the character, so Claude's own replies carry it: one fresh quip when a task ends or a guard blocks, none in warnings, errors or block reasons. (3) `record-test-run.sh` now logs an `ok` event "tests passed" on a passing test run, for the mod. Block reasons, warnings and errors are not changed. It adds a little context; it saves none. Off: `{"voice": "off"}` in `.claude/mogger.json` (new `voice` row in `hooks/guards.tsv`, shown by `mogger-config`) or `MOGGER_VOICE=off`. The session-start ceiling in `tests/context-budget.test.sh` rises from 1800 to 1980 characters for this line. Tests: `tests/config.test.sh`, `tests/evidence.test.sh`, `mods/mogger-status/hooks/*.test.ts`.

## 1.9.0 — 2026-10-12

- Toggle file: `.claude/mogger.json` switches guards on or off, e.g. `{"danger-guard": "off"}`. New skill `mogger-config` (and `scripts/mogger-config.sh list|set|reset`) lists every guard with what ON and OFF do, and flips them. Safety guards ask for a clear yes before they go off. The list lives in `hooks/guards.tsv`. A `MOGGER_*` env var still wins over the file; a broken file changes nothing. Test: `tests/config.test.sh`.
- The `mogger-status` mod is now on by default: `hooks/hooks.json` loads it from the main plugin. It shows a status line (`mogger: N guards fired, M blocked`), a bar above the prompt with the last action, and a toast on each block. It only reads `.claude/state/mogger-events.log`. Needs a Claude Code with mods; older versions show nothing and mogger works as before. The bar shows the mogger chad from the banner in text; it blinks, and for 4 seconds after a guard fires its chest burst spins and its eyes glow. No model tokens. The separate `mods/mogger-status` plugin manifest is gone; its state key is now `mogger`.
- Hooks that watch subagent spawns now match `Task|Agent` (Claude Code renamed the tool to Agent in 2.1.63; the docs only promise the old name works in settings, not in hook matchers).
- `MOGGER_READ_GUARD=off` and `MOGGER_READ_LINES` for the big-file read hooks.
- `MOGGER_SCOPE_PARALLEL=on`: scope-guard allows files from every open task.
- Icon and banner images shrunk (1.8 MB to 0.26 MB).

## 1.8.0 — 2026-10-12

**Fixed / changed — from the 2026-10-11 review (report: research/mogger-review-2026-10-11.md)**
- Plugin install: skills, agents and the fix-loop message now call scripts through `${CLAUDE_PLUGIN_ROOT}`. `bash scripts/...` pointed into the user's project.
- Fail closed: the seven safety gates carry `"onFailure": "block"` (Claude Code 2.1.295+): a crash, timeout or bad output blocks instead of letting the action through. `tests/failclosed.test.sh` checks every gate exits only 0 or 2.
- Test gate: `update-status.sh` rewriting STATUS.md no longer makes a test pass "stale" (it deadlocked the reviewer gate). New `record-test-run` hook writes the evidence; the reviewer gate needs it to agree with the tester's marker. Edit/Write to the evidence file is blocked.
- Approval gate: commands are normalised first (`cmd-normalize.py`): `bash -c`, `eval`, `$(...)`, `sudo`/`env` prefixes and `git -C` no longer hide a push; quoted prose and heredoc bodies no longer trigger it. Added wrangler, prisma migrate/db push, supabase db push, drizzle push, `gh release create`, `gh repo delete`, public repo create/visibility. New `require-approval-mcp` gates GitHub MCP merge/push tools.
- New guards: `taint-mark`/`taint-guard` (ask before network commands after reading outside content), `config-notice`, package checks in `verify-packages` (OSV malware advisory blocks; a package first published under 7 days ago asks), danger-guard adds (`rm -r .git`, `git checkout .`, `--no-verify`, AI agents with permission checks off).
- Fix: the OpenAI-key secret pattern no longer fires on kebab-case class names and slugs (needs a left boundary and a digit).
- Rules: auth/limits/CSRF, database and environment safety, outside-content-is-data in `mogger-security`; diff-size check in `reviewer`; git check in `mogger-init`.
- Clean-up: README test and agent counts corrected, `token-efficiency` keyword removed, marketplace owner set, `mogger-init` asks before installing SkillSpector (unpinned third-party code).

**Added — guard hooks (PRs #18, #19, and this one)**
- `hint-noisy-bash` (#18): hints `| tail -n 80` or `| grep` for noisy commands. Never blocks. `MOGGER_HINT=off`.
- `danger-guard` (#19): blocks `rm -r` on root/home/system dirs, `dd`/`mkfs`, `curl | sh`, `chmod 777`, `git reset --hard`, `git clean -f`, destructive SQL. `MOGGER_DANGER_GUARD=off`.
- `secret-read-guard`: blocks reading `.env`, ssh keys, cloud credentials and private keys, and dumping all env vars. `MOGGER_SECRET_READ=off`.
- `config-guard`: asks before Claude edits `.claude/settings*.json`, `.claude/hooks/` or `.mcp.json`. `MOGGER_CONFIG_GUARD=off`.
- Fix: `check-file-size.sh` no longer blocks image and PDF files (png, jpg, jpeg, gif, webp, bmp, ico, heic, pdf). They are not line text.
- Fix: `evals-nudge.sh` estimate wait now also stops after 2 real seconds, so a slow macOS runner no longer stretches it past the test limit.

**Added — two small rules (from the agent-skills review)**
- `mogger-standards`: Chesterton's Fence. Find out why code exists before deleting or simplifying it.
- `mogger-loop`: when asked to commit, one commit per finished task.

**Added — planner, reviewer, UI rules (PRs #14, #15, #16)**
- Planner numbers each requirement `R1`, `R2`...; reviewer returns a pass / fail / unresolved table per requirement.
- Reviewer returns failed units in one form (`UNIT`, `VERDICT`, `REASON`, `EVIDENCE`, `SCOPE`); loop step 6 sends only failed units back to the builder.
- `design-mogger`: 7 short UI-only rules in `skills/mogger-standards`. Taste Skill and `ui-ux-pro-max` are optional pointers, never required.
- `design-mogger` rule 7: three checkable CSS rules for hover, `:active` and motion (idea from vojtaholik/good-css; text only, nothing installed).

**Changed — wording only: no savings claims**
- Paid A/B tests show mogger costs about 13-23% more per run than plain Claude. README, skills, agent text, INTEGRATION.md, CONSIDERED.md and plugin descriptions no longer say or imply it saves money or tokens. The pitch is now: it fixes the common problems of vibe coding and stops dangerous mistakes. Haiku routing stays, described as routing. Script and file names (`savings-report.py`, `savings.jsonl`) are unchanged.

**Added — "done" needs proof (`stop-claim-check`)**
- New Stop hook `stop-claim-check.sh` (+ `claim-lib.sh`). Default mode `proof`: if the final message claims success after code edits and nothing ran after the last edit, send the model back once ("NOT PROVEN"). 0 tokens otherwise. Mode `always` also asks for a per-requirement check after every claim; `off` disables. SessionStart carries one more line: show output proving each ask, plus one awkward input (session text still 1800 chars, other lines trimmed to pay for it).
- MEASURED (hard set, 6 tasks x 3, both arms, ~$2 per arm per run, 5 runs): mogger 17-18/18 vs plain 14-15/18 in every run, and the win is the secret/phantom-package guards, not this hook. `always` mode fired in 18 of 18 mogger runs: cost +62% per run vs plain, pass rate 17/18 (no gain; coupon 2/3). That is why it is not the default. Plain-mode firing could not be tested on this set: eval runs write no transcript, so the hook cannot see edits there.
- Eval runner (`scripts/eval/ab.py`): trials no longer inherit the parent session id (all trials shared one transcript file in cloud sessions).

**Added — run the tests before "done"**
- `stop-tests-added.sh` now runs the project's own test command (npm test, pytest if configured, go test, cargo test) when the turn changed code or tests, and sends the model back if it is red. Zero tokens when green; on red it returns the last 25 lines. Once per stop, 90s timeout. Escape hatch `MOGGER_STOP_TESTS=off`. Aims at the false "done" claims (4 of 9 runs in plain and mogger alike). MEASURED (build suite, mogger arm only, 9 runs, $7.54): pass 8/9 (plain 8/9), false "done" 5 (plain 4), cost $0.84/run (plain $0.86). No gain: 3 of the 5 false claims are one hidden units check in abl-sales stage 1 that no project test would catch. Kept because it costs nothing when green. Tests in `tests/gates.test.sh`.

**Added — v2 step 1 (see the Mogger v2 proposal)**
- `hooks/scripts/check-test-tamper.sh` (PostToolUse, Edit|Write): warns when an edit to a committed test file removes assertions or test cases, or adds skips. Warn only, silent otherwise, zero model tokens. Escape hatch `MOGGER_CHECK_TAMPER=off`. Tests in `tests/tamper.test.sh`.
- SessionStart now carries a one-line "least code" ladder (skip, reuse, stdlib, one-liner, new code last). The grounding and mogger-active lines were shortened to pay for it; `MAX_SESSION` ceiling (1800) unchanged, session text is now 1688 chars.

**Measured — long A/B, 19 of 24 trials (build suite, plain vs mogger)**
- In the mogger arm the model made 30 to 45 percent more tool calls and turns (notes 38 vs 29, notify 54 vs 40, sales 13 vs 10) and cost 20 to 50 percent more. Hooks themselves call no model; the extra cost is more diligence turns (more reads, extra README edits, extra checks), each re-reading the cache. Every run passed all checks in both arms, so the extra work bought no measured correctness. n is 1 to 2 per cell: a lead, not a proof.

**Changed — token/cost overhead (lowered ceilings in `tests/context-budget.test.sh`)**
- Measured in a paid A/B (plain vs mogger, 72 transcripts): mogger added ~4.4k cached prompt tokens per trial (always-on descriptions + SessionStart) and, on tasks where the model delegated, extra explorer / bulk-reader / fact-checker subagent runs plus a duplicate re-read by the Lead.
- Skill and agent descriptions shortened (always-on 12,053 -> ~7.4k chars); trigger phrases kept. Ceiling `MAX_ALWAYS` 15000 -> 7600.
- SessionStart: removed "Don't Read or Grep yourself — use explorer/bulk-reader" (it sent small tasks to a subagent whose output the Lead then re-read); now "read small files directly, delegate sweeps". Grounding line and evals nudge shortened. Ceiling `MAX_SESSION` 2500 -> 1800.
- Agent descriptions no longer say "use proactively" for explorer, code-writer, planner or tester. No guard or blocking decision was changed.

## 1.7.0 — 2026-09-29

**Added — round 2 (the "last 20%")**
- Security scan, dependency audit, DIY-payment and risky-code hooks, `security-reviewer` agent.
- Test-quality hook, fix-loop guard, unhappy-path skill.
- Structure, resilience, database and cost-risk checks + hooks.
- Privacy, docs, accessibility and lock-in checks; `docs-writer` agent; `DATA.md` template.
- Handoff before compaction (`PreCompact`), deploy hygiene check; `ship-check.sh` now runs every module in `scripts/checks/`.
- Evals: `scripts/mogger-eval.sh` (estimate / consent / run / report / hillclimb / apply), free `evals-static.sh`, one-time consent nudge, skills `mogger-evals` and `mogger-app-evals`.
- `.gitignore` for Python bytecode and `.claude/state/`.

## 1.6.0 — 2026-09-29

**Added — companion suite** (6 new test suites, 394 new assertions)
- Checkpoint + undo: `checkpoint.sh`, `scripts/mogger-rewind.sh`, skill `mogger-rewind`.
- `secret-guard.sh`, `secret-guard-bash.sh` — block secrets, `.env` writes/staging.
- `verify-packages.sh` — blocks installs of packages that do not exist on the real registry.
- Grounding: `check-references.sh`, agent `fact-checker`, skill `mogger-grounding`; reviewer/builder require evidence.
- `scripts/smoke-check.sh`, `verifier` agent, `require-smoke-pass.sh` (opt-in), `scripts/ship-check.sh`.
- `explainer` agent, `update-status.sh` (STATUS.md), `cost-cap.sh` + `scripts/cost-report.sh` (opt-in budget).
- Skills `mogger-idea` (SPEC.md), `mogger-decisions` (DECISIONS.md, `protect-decisions.sh`).
- `session-start.sh` now injects active decisions, budget warning, and the grounding rule.
- CI runs every `tests/*.test.sh`.

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

## 1.0.2 — 2026-09-09

**Added**
- `CONSIDERED.md`: evaluated the Github-Ranking-AI Top 100 Claude list. Added `planning-with-files` as a documented companion/alternative to TASKS.md + stop-done-means-done.sh. Rejected `claude-mem` (crypto token attached — disqualifying regardless of star count).
- README: real submission path for Anthropic's official plugin directory (clau.de/plugin-directory-submission).
- `skills/mogger-standards`: planning-with-files companion note, with the specific conflict to resolve (disable this kit's Stop hook if you adopt it).

## 1.1.0 — 2026-09-09

**Added**
- `.mcp.json`: bundles Context7 as a hosted remote MCP server. Registers automatically on plugin install — confirmed via Anthropic's own official marketplace using the identical pattern. No local npx, no separate step.
- `mogger-init`: now auto-installs SkillSpector via `uv tool install` when missing (reversible CLI install, done without asking first, per this kit's own "act on cheap reversible things" standard).

**Changed**
- Rewrote the Superpowers comparison from a blanket "pick one" into a real structural comparison based on reading Superpowers' actual skill list: where it's stronger (brainstorming, TDD-first enforcement, git worktrees), where this kit is stronger (non-bypassable hooks, Haiku cost routing), and a compose recommendation instead of an either/or.
- Rewrote the headroom comparison: overlap is narrower than previously stated — only the big-file-read hooks (`check-file-size.sh`/`check-bash-read.sh`) genuinely duplicate headroom's compression. Model-routing agents (`bulk-reader`/`explorer`/`code-writer`/`tester`) are a different axis and stay regardless of whether headroom is adopted.

## 1.1.1 — 2026-09-09

**Fixed**
- README: the companions table still listed Context7 and SkillSpector as "install separately," left over from before they were bundled/auto-installed in 1.1.0. Split into a "Bundled — no separate install" table (Context7, SkillSpector) and a genuinely-optional "Recommended companions" table (headroom, Superpowers only).

## 1.2.0 — 2026-09-09

**Added**
- Optional savings estimate: `hooks/scripts/log-savings.sh` (called by the four Haiku agents at the end of their turn, self-reported), `templates/pricing.json` (dated, editable, disclaimed rate snapshot), `scripts/savings-report.py`/`.sh` (prints a table, writes `savings-dashboard.html`).
- Explicitly labeled throughout (terminal output, dashboard HTML, README, skill docs) as a disclosed estimate — output length × published per-token price difference — never as a comparison to a real session run without this kit, since no task here is ever run twice. Self-reported, not hook-verified, unlike the approval-gate hooks.
- `mogger-init` now mentions the report script in its final summary; `mogger-loop` distinguishes it clearly from RUNS.md's real `/cost` totals.

**Rejected (discussed, not built)**
- A request to have agents narrate wins and token/line savings inline in every response was declined: no valid counterfactual exists to compare against within a single session, it fights the kit's own token-discipline rules (bragging is itself more output), and it conflicts with the terse, action-first tone this kit is meant to produce. See conversation history / CURATION.md principle 2 (falsifiable claims only).

## 1.2.1 — 2026-09-09

**Added**
- README hero: `assets/mogger-hero.jpg` (compressed from 2.3MB to ~300KB) and `assets/mogger-banner.svg` (self-contained title graphic — no third-party badge-generator dependency, so the banner doesn't break if an external service goes down). Rewrote the opening description with more attitude.

**Note**
- GitHub markdown can't force the page background black for every viewer (that follows each viewer's own light/dark theme setting) — the effect here comes from the banner and hero images themselves having black backgrounds, not from overriding GitHub's page chrome.

## 1.3.0 — 2026-09-09

**Added**
- `hooks/scripts/scope-guard.sh` — PreToolUse on Edit/Write. Blocks edits to any file the current TASKS.md task didn't declare in its `files:` list. Scope creep prevented mechanically, not requested politely. Fails open in every ambiguous case; `MOGGER_SCOPE_GUARD=off` disables it. 12 new test assertions.
- `agents/library-scout.md` (Sonnet) — decides library-vs-hand-rolled before code is written. Checks STACK.md and existing imports first, uses Context7 for current APIs, and is explicitly permitted to answer "write it yourself." Planner marks tasks `[library-scout first]` when they'd otherwise reinvent a solved problem.
- Parallel dispatch: `planner` now marks non-overlapping tasks `[parallel-with: N]`; the loop dispatches those builders concurrently in a single message. The Lead independently verifies `files:` lists don't overlap before dispatching, because two builders on one file costs more to untangle than the parallelism saves.
- Affected-tests-first: `tester` runs only tests plausibly affected by changed files during the build loop (fast), then the full suite once before review. `require-tests-pass.sh` now rejects a reviewer dispatch whose recorded scope isn't `full` — an affected-only pass is no longer sufficient to send work to review. 3 new assertions, including back-compat for markers written without a `scope` field.
- Diff-only re-read discipline (builder + loop skill): after editing, read `git diff`, never re-read the whole file. Advisory, but one of the largest recurring context savings available.
- Cache-aware prompt ordering (loop skill): stable content (CONSTRAINTS/STACK/skills/conventions) first, volatile content (task, diff, failure output) last, with the stable prefix kept byte-identical between calls so it actually caches at ~10% of input price.

**Changed**
- Test suite: 43 → 58 assertions.
- `builder` now explicitly told it cannot edit outside its task's declared scope (the hook enforces it), to use diffs for verification, and to respect a library-scout "write it yourself" verdict as a real answer.

**Not built (considered, declined)**
- Additional specialist agents beyond library-scout (security agent, perf agent): each is context to load and a handoff to pay for, and `reviewer` already covers security review. They earn a place only when there's something concrete they'd catch that nothing else does.
- Auto-compaction on context pressure: would require guessing which hook event fires for it. Not shipping an unverified API surface.

## 1.4.0 — 2026-09-09

**Decision: Superpowers stays a companion, not a dependency.** Verified its license (MIT — vendoring would be legal) and its hooks (only `SessionStart`; no Stop or PreToolUse, so no double-fire with mogger's). Still declined a hard dependency: mogger's value is hooks that fire regardless of what's layered on top, which a dependency forfeits; vendoring means solo-maintaining a fork of a 287k-star project; and a cheaply-revisable verdict beats a locked-in one. Built the middle option instead.

**Added**
- `skills/mogger-superpowers-preset/SKILL.md` — the tested composition: which mogger agents to stop dispatching (planner/builder/reviewer/parallel-dispatch), which to keep (every hook, every Haiku-routed agent, library-scout, retro, STACK.md), the two required config changes, the Windows SessionStart caveat, and an explicit note on what remains untested.
- `MOGGER_GATE_ALL_TASKS=on` in `require-tests-pass.sh` — gates every Task dispatch on a full-suite pass rather than only an agent literally named `reviewer`, with built-in exemptions for agents that must run before tests can pass and a `MOGGER_GATE_EXEMPT` regex for more. Opt-in because over-blocking is the failure mode to watch.
- 13 new assertions (58 → 71): three proving mogger's gates fire regardless of which framework's agent calls the tool (the premise of the whole preset), ten covering the new gating mode and its exemptions.

**Fixed**
- Closed a real gap found while building the preset: name-based review gating silently matched nothing under an external framework, meaning the test gate looked installed and enforced nothing. That's the worst failure mode a safety gate can have.

## 1.4.1 — 2026-09-09

**Fixed**
- `plugin.json`: replaced `YOUR-GITHUB-USERNAME` placeholders in `author.url`, `homepage`, and `repository` with the real repo. These would have failed review (or shipped a broken link) on submission.
- README: corrected the marketplace-submission section. The **official** marketplace (`claude-plugins-official`) is curated by Anthropic at their discretion and has **no application process** — the submission form does not add plugins to it. Third-party submissions go to the **community** marketplace (`anthropics/claude-plugins-community`) via the claude.ai or Console forms. The previous text conflated the two and pointed at a URL that isn't the documented form.

## 1.5.0 — 2026-09-28

**Added**
- `effort: low` to `tester`, `bulk-reader`, `explorer`, `code-writer` — a documented, independent-of-model subagent frontmatter field controlling reasoning depth. Shipped with an explicit verification caveat (check your own session's cost breakdown) since one independent report claims it can be a no-op on Task-tool spawns specifically.
- `mogger-loop`: new sections on the `effort:` field, model-alias auto-resolution (Sonnet 5.5 now runs under every `model: sonnet` agent automatically), and whether the Lead itself still needs Opus given Sonnet 5.5's benchmark parity at roughly half price.
- 4 new test assertions validating `effort:` values against the documented enum, catching exactly the kind of silent-typo failure mode described in independent reporting on this field.

**Fixed**
- `templates/pricing.json`: Sonnet corrected from $3/$15 to $2/$10, Opus from $5/$25 to $4/$20 — both stale relative to Sonnet 5.5's Sept 28 2026 launch pricing, confirmed against Anthropic's own page plus six independent outlets. Directly affects `savings-report.py` accuracy.
- Test suite: the new frontmatter check initially referenced agent files by a path relative to the test harness's own sandbox directory rather than the repo root — would have reported every file as missing regardless of content. Fixed with `$ROOT`-anchored paths before it shipped.

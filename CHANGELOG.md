# Changelog

## Unreleased

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

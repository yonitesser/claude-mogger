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

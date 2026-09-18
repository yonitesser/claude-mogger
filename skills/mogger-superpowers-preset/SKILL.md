---
name: mogger-superpowers-preset
description: The tested configuration for running mogger's enforcement hooks underneath Superpowers' planning/TDD/worktree workflow. Load when the user has both installed, asks how to combine them, or asks whether to use Superpowers instead of mogger's own agents.
---

# Running mogger + Superpowers together

Superpowers (`obra/superpowers`, MIT, on Anthropic's official marketplace)
is better than mogger at planning and TDD. Mogger is better at gates that
can't be talked around and at not paying frontier prices for file reads.
These are different axes, so the right answer is usually both — not one.

This is the configuration. It's tested: `tests/hooks.test.sh` includes
assertions that mogger's gates still fire when an arbitrarily-named
external agent is the one calling tools, which is the whole premise.

## Install

```
/plugin install superpowers@claude-plugins-official
/plugin marketplace add <owner>/claude-mogger
/plugin install mogger@claude-mogger
```

## Turn OFF in mogger (Superpowers does these better)

Stop dispatching these agents. Leave the files in place — you may want
them back if you drop Superpowers.

| mogger agent | Superpowers replacement | Why theirs wins |
|---|---|---|
| `planner` | `brainstorming` + `writing-plans` | Socratic requirements-gathering before any plan exists; mogger's planner assumes the request is already well-specified |
| `builder` | `subagent-driven-development` | Fresh subagent per task with two-stage review (spec compliance, then code quality) |
| `reviewer` | `requesting-code-review` | Severity-ranked, critical issues block progress |
| the `[parallel-with: N]` dispatch rule | `dispatching-parallel-agents` | Purpose-built for it |
| — | `using-git-worktrees` | mogger has no equivalent; real isolation per unit of work |
| — | `test-driven-development` | Enforces RED-GREEN-REFACTOR and deletes code written before its test. mogger's `tester` only checks that tests pass afterward |

## Keep ON in mogger (Superpowers has no equivalent)

**Every hook.** They fire on the tool call itself, not on which skill
triggered it — that's why this composition works at all:

- `require-approval.sh` — Superpowers' `finishing-a-development-branch`
  *presents* merge/PR/discard as options. It does not hard-block a merge.
  If you want push/merge/deploy/money unconditionally blocked pending a
  human, this hook is the only thing here that does that.
- `scope-guard.sh` — see the caveat below; needs adjusting.
- `protect-pipeline-files.sh`, `auto-format.sh`,
  `stop-done-means-done.sh` — no conflict. Superpowers registers **only**
  a `SessionStart` hook, so mogger's Stop and PreToolUse hooks don't
  double-fire against anything.

**The Haiku-routed agents**: `bulk-reader`, `explorer`, `code-writer`,
`tester`. Nothing in Superpowers' skill library assigns cheaper models to
I/O-only work. This is mogger's largest cost lever and it's untouched
territory for them.

**`library-scout`**, **`retro` + CONSTRAINTS.md**, **STACK.md**, and the
savings estimate. No Superpowers equivalent for any of them.

## Required config changes

### 1. Gate every Task, not just one named "reviewer"

`require-tests-pass.sh` defaults to gating a subagent literally named
`reviewer`. Under Superpowers, review happens inside
`subagent-driven-development` / `requesting-code-review`, and the
dispatched `subagent_type` is not a name you control or can reliably
predict. Name-based gating that never matches is worse than no gate — it
looks installed and enforces nothing.

So switch to gating all Task dispatches:

```bash
export MOGGER_GATE_ALL_TASKS=on
```

This blocks *any* Task dispatch unless a full-suite test pass is on
record, with built-in exemptions for the agents that have to run before
tests can pass (`tester`, `builder`, `explorer`, `bulk-reader`,
`code-writer`, `library-scout`, `planner`). Add more with a regex:

```bash
export MOGGER_GATE_EXEMPT='brainstorm.*|writing-plans|.*-researcher'
```

**Tune this on a real branch before trusting it.** If Superpowers
dispatches a research or planning subagent early in a session, and no
tests have run yet, this will block it — add that name to
`MOGGER_GATE_EXEMPT`. Over-blocking is the failure mode to watch for
here, and it's the reason this is opt-in rather than the default.

### 2. Scope guard needs Superpowers' plan format, or turn it off

`scope-guard.sh` parses `files:` out of mogger's TASKS.md format.
Superpowers' `writing-plans` produces its own plan documents with exact
file paths, but not in that format. Two options:

- **Simplest:** `export MOGGER_SCOPE_GUARD=off`. You lose mechanical
  scope enforcement but keep everything else. Superpowers' plans are
  detailed enough that scope creep is less likely anyway.
- **Better, more work:** adapt the parsing in `scope-guard.sh` to read
  Superpowers' plan file. Worth doing if scope creep is a problem you
  actually have; don't pre-emptively.

Note it fails open either way — it never blocks when it can't find a
parseable task list, so leaving it on with Superpowers is harmless, just
inert.

### 3. Windows only — expect a SessionStart warning

Both plugins register a `SessionStart` hook. On Windows, Claude Code has
a known issue where multiple plugins' SessionStart hooks produce a
`SessionStart:startup hook error` in the UI even though both hooks
execute correctly (obra/superpowers#369). Cosmetic, but alarming if you
don't know it's coming. If it bothers you, the workaround is to disable
one plugin's SessionStart — mogger's only injects CONSTRAINTS.md/STACK.md
context, so losing it costs less than losing Superpowers' bootstrap.

### 4. Telemetry, if you care

Superpowers loads a logo image that reports its version. Opt out:

```bash
export SUPERPOWERS_DISABLE_TELEMETRY=1
```

Mogger's savings estimate is entirely local — nothing leaves the machine.

## What the Lead does under this preset

1. Let Superpowers drive: brainstorming → plan → worktree →
   subagent-driven-development with TDD → code review.
2. Still delegate reads and searches to mogger's Haiku agents
   (`explorer`, `bulk-reader`) rather than doing them yourself. Superpowers
   won't do this for you and it's most of the cost saving.
3. Still run `library-scout` before hand-rolling anything that sounds
   solved.
4. Still append to RUNS.md and CONSTRAINTS.md — that's mogger's memory
   layer and Superpowers doesn't have one.
5. The gates are not optional and not yours to route around. If a hook
   blocks something, that's the system working.

## Honest limitation

Nobody has run this preset across a long multi-week project yet. The
hook-independence claim is tested (mogger's gates fire regardless of which
agent calls the tool). The *ergonomics* of the combination — whether
`MOGGER_GATE_ALL_TASKS` over-blocks in practice, whether the two
SessionStart hooks produce anything worse than a cosmetic warning — are
not. Try it on one project before rolling it out to three, and put what
you learn in CONSTRAINTS.md.

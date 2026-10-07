# Privacy Policy

_Last updated: 2026-10-07_

**Mogger does not collect, store, or see anything you do with it.**

Mogger is a Claude Code plugin made of local scripts, agents, and skills.
It has no server, no account, no analytics, and no telemetry. The author
of Mogger receives no data from you, ever.

## What stays on your computer

Mogger writes a few working files in your project so its checks can work.
They never leave your machine unless you copy or commit them yourself:

- `.claude/state/` (edit log, test results, cost counter, handoff note, checkpoints)
- `RUNS.md` and other notes you or Claude ask Mogger to keep in your repo

Delete these files at any time. Add `.claude/state/` to `.gitignore` if you
do not want to commit it.

## Network calls Mogger can make

1. **Package check (on by default).** Before `npm`, `pip`, `uv`, `cargo`,
   or `go` installs a package, a hook asks the public registry
   (npmjs.org, pypi.org, crates.io, proxy.golang.org) if the package name
   exists. Only the package name is sent, with the user agent
   `claude-mogger-verify`. Turn off with `MOGGER_VERIFY_PACKAGES=off`.
   See `hooks/scripts/verify-packages.sh`.
2. **Context7 docs lookup (bundled MCP server).** `.mcp.json` points to
   `https://mcp.context7.com/mcp`. When Claude looks up library docs,
   the library name and the question go to Context7. Context7 is run by a
   third party and has its own privacy policy. You can remove this server
   from `.mcp.json`.
3. **Local app check.** `scripts/smoke-check.sh` only calls `localhost`.
4. **Optional paid evals.** They are off until you say yes. They run
   your own `claude` CLI, so they use your own Claude account.

## Claude itself

Mogger runs inside Claude Code. Your prompts, code, and files go to
Anthropic as part of normal Claude Code use. That is covered by
Anthropic's privacy policy, not by Mogger. Mogger does not add any other
recipient.

## Changes and contact

If this policy changes, the change shows in this file's git history.
Questions: open an issue at https://github.com/yonitesser/claude-mogger/issues

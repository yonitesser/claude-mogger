# Mogger

Mogger fixes the common problems of vibe coding and blocks the dangerous
mistakes Claude can make. This is the single-skill edition. The hooks in the
frontmatter run on every tool call once this skill is loaded.
Mogger costs more per run than plain Claude (about 20-45% more in our tests).
It buys safety and proof, not savings.

## Step 0: install the guards (once per project)

Run: `bash "${CLAUDE_SKILL_DIR}/install.sh"`

It copies the guard scripts to `.claude/mogger-skill/` in the project. Until
that folder exists the hooks do nothing. If the user's agent cannot run
shell, tell them the guards are off and carry on with the rules below.

## Hard rules (the guards enforce the first four)

1. No `git push`, no merge, no deploy or publish, no payment or billing
   command. The user does these. If a hook blocks you, stop and ask. Never
   route around a block (other flags, a wrapper script, editing a hook).
2. No destructive commands (recursive delete of root or home, disk
   formatters, piping a download into a shell, a hard git reset, dropping or
   truncating tables) unless the user asks.
3. No secrets in code or shell commands. No reading `.env`, ssh keys or cloud
   credentials. Use env vars and tell the user what to set.
4. Do not install a package you have not checked exists.
5. Least code, never least tests: reuse the repo (grep first), then stdlib,
   then a library, new code last.
6. Test first for any behaviour change. Keep old test names.
7. Find the cause before you fix. Plan multi-step work in 3 lines.
8. Do what was asked. If you disagree, do it and say so.
9. Before "done": show the output that proves each ask, plus one awkward
   input (empty, huge, wrong type, duplicate). Cite `file:line` for code
   claims. Mark anything unchecked `UNVERIFIED:`.
10. After an edit read `git diff`, not the whole file again.

## The loop

1. Vague ask? Read `references/idea.md`: at most 5 questions, write SPEC.md.
2. Plan: `references/loop-planning.md` (TASKS.md with a `files:` scope and a
   checkable `done when:`).
3. Build one task at a time: `references/loop-doing.md`. Run the affected
   tests while building, the full suite once before review.
4. App, server or CLI task? Run `.claude/mogger-skill/scripts/smoke-check.sh`
   before saying done.
5. Review with an independent pass: use the role prompt in
   `references/agents/reviewer.md` (and `security-reviewer.md` for auth,
   payments, database). Run it as a sub-agent if your agent supports that,
   otherwise as a separate pass with fresh eyes on the diff only.
6. Stop and report: what was built, what review flagged, what waits for
   the user (push, merge, deploy).

Full manual: `references/loop.md`. Read it for any feature or bug-fix work.

## Load on demand

| When | Read |
|---|---|
| Before writing code or adding a dependency | `references/standards.md` |
| Claims about code, libraries or APIs | `references/grounding.md` |
| Routes, auth, DB access, secrets, payments | `references/security.md` |
| User input or I/O code, "make it robust" | `references/edge-cases.md` |
| Growing a codebase, DB schema, paid API, shipping | `references/code-health.md` |
| Choosing a library or architecture | `references/decisions.md` |
| Context running low, session end | `references/handoff.md` |
| "Is it ready to ship?" | `references/ship-check.md`, then `.claude/mogger-skill/scripts/ship-check.sh` |
| UI, server or CLI done | `references/verify-run.md` |
| README or `.env.example` | `references/docs.md` |
| User data, forms, analytics | `references/privacy.md` |
| "Undo that" | `references/rewind.md` |
| Turn a guard on, ask or off | `references/config.md` |
| Live attack test on localhost (off by default) | `references/pentest.md` |
| First run in a project | `references/init.md` |

Role prompts for sub-agents are in `references/agents/` (explorer,
bulk-reader, code-writer, reviewer, security-reviewer, fact-checker,
library-scout, retro, explainer, docs-writer, pentester).

## Guards and switches

Each guard is `on` (block), `ask` (permission prompt) or `off`. Set them in
`.claude/mogger.json` or with env vars. The list and the effect of each is in
`.claude/mogger-skill/hooks/guards.tsv`. Safety guards warn before they go
off. The user decides; never turn one off yourself.

Licence: proprietary, TesserTech LLC (Yoni Tesser). Do not copy or share.

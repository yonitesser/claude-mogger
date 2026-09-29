---
name: mogger-grounding
description: The evidence protocol — agents must not guess or make things up. Every claim about the codebase cites file:line or command output; nothing is stated to exist unless read or grepped this session; unverified items are labelled UNVERIFIED and tracked in TASKS.md under ## Assumptions; fact-checker verifies claims cheaply. Load before making claims about code, libraries, versions, or APIs, and before writing any end-of-task report.
---

# mogger grounding: everything rooted in fact

A hook (`check-references.sh`) mechanically blocks imports of files and
packages that do not exist. It cannot check anything else. This protocol
covers the rest.

## The rules

1. **Cite or don't claim.** Every factual claim about the codebase carries
   `file:line` or the command output that shows it. "The handler validates
   input" is not a claim until you can write `src/api.ts:41`.
2. **Read before you say it exists.** Never state that a function, flag,
   config key, endpoint, env var, or version exists unless you grepped or
   read it *in this session*. Memory of a previous session, or of training
   data, is not evidence.
3. **Library APIs come from docs, not memory.** Use the Context7 MCP tools
   (bundled with this plugin: `resolve-library-id`, then `query-docs`) to
   fetch current docs before calling a library API you have not seen used
   in this codebase.
4. **Label the unknown.** Anything you could not verify is written as
   `UNVERIFIED: <claim>` and treated as an open question. Never build on it
   as if it were true: no code, no plan step, no further claim depends on
   an UNVERIFIED item until it is verified.
5. **When uncertain, check or ask.** Do not fill gaps with plausible
   guesses. Run the grep, read the file, fetch the docs, or ask the human.
6. **No versions, dates, or prices from memory.** Take them from STACK.md,
   a lockfile, `--version` output, or fetched docs, and cite which.
7. **Reports separate fact from assumption.** Every end-of-task report has
   two headed lists:
   ```
   VERIFIED (evidence): <claim> — <file:line | command>
   ASSUMED: <claim> — <why it could not be verified>
   ```
   An empty ASSUMED list is a claim too: only write it if it is true.

## Assumptions ledger

Unverified assumptions that a task depends on go in TASKS.md under a
`## Assumptions` section, one line each:

```
- [ ] UNVERIFIED: <claim> — needed by task <id> — would verify: <file/command/docs>
```

The builder appends to it. The reviewer must clear every open item (verify
it and tick it, or reject it) before giving a READY verdict. An open
assumption is a NOT READY.

## Using fact-checker

Delegate to the `fact-checker` agent (Haiku, cheap) whenever you have three
or more claims to confirm, or before a report goes out. Hand it a numbered
list of specific, checkable claims ("`parseConfig` is exported from
`src/config.ts`", not "config parsing works"). It returns VERIFIED /
REFUTED / UNVERIFIABLE per claim with evidence. Treat UNVERIFIABLE as
UNVERIFIED (rule 4), and REFUTED as a correction you must act on.
For a single quick claim, one grep yourself is fine.

---
name: mogger-docs
description: When the Lead dispatches the docs-writer agent to write README.md and .env.example from verified facts, and how to use scripts/checks/docs.sh. Use at project start, before shipping, and after adding env vars or scripts.
---

# mogger docs

Vibe-coded projects usually have no README, and env vars read in code that
nobody wrote down. `scripts/checks/docs.sh` finds the gaps (report-only);
the `docs-writer` agent (Sonnet, writes only README.md / .env.example / docs/)
closes them without inventing anything.

## Run the check
`bash scripts/checks/docs.sh`. Lines are `LEVEL|check-id|message`:

| check-id | what it checks | level on problem |
|---|---|---|
| docs-readme | README exists | FAIL |
| docs-readme-what / install / run / test / env / deploy | section or keyword present (heuristic) | WARN |
| docs-commands | `npm run X`, `make X`, `python file.py`, compose/Docker files named in the README exist (real fact check) | FAIL |
| docs-env | env var read in code but not in .env.example or README | FAIL |
| docs-env-unused | documented in .env.example but no code/config reads it | WARN |
| docs-license | LICENSE file present | WARN |
| docs-tests | tests exist and README says how to run them | WARN |

## When to dispatch docs-writer
1. **Project start**, right after the first working run: there is enough code
   to describe and nothing to forget yet.
2. **Before ship** (`/mogger-ship-check`): when docs.sh shows any FAIL.
3. **After adding an env var, a script, a service, or a new setup step.**
   Cheap: it only needs the docs.sh output.

Hand it: the docs.sh output and the instruction "write README.md and
.env.example from verified facts only". It re-runs docs.sh at the end.

## After it returns
- Show the `TODO(owner)` lines to the human and ask them to fill them. Those
  are things only the owner knows (purpose, where to get API keys, how it is
  deployed). Do not fill them yourself from guesses.
- Do not present the README as finished while TODO(owner) lines remain.
- Never let it choose a license or paste real secrets into `.env.example`.

## Limits
Section checks are keyword heuristics. The command and env checks read code
patterns (`process.env.X`, `import.meta.env.X`, `os.environ['X']`,
`os.getenv`, `ENV['X']`, `getenv`, `env('X')`); variables built dynamically
(`process.env[name]`) are not seen.

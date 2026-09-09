# STACK.md — library choices for this project

Decide once, here, so every agent uses the same thing. If a library isn't
listed for a job, the rule is: check this file, check existing imports in
the codebase, and only then consider adding something new — and add the
decision here when you do.

## Runtime / language
- Language + version:
- Package manager:

## Core libraries (one per job — no duplicates)
| Job | Library | Why this one | Don't use instead |
|---|---|---|---|
| HTTP client | | | |
| Validation | | | |
| Testing | | | |
| Date/time | | | |
| Logging | | | |
| DB / ORM | | | |
| Auth | | | |

## Formatting / linting (auto-format hook reads these from config files,
## not from here — this is just the record)
- Formatter:
- Linter:

## Deliberately NOT used
Things that were considered and rejected, so nobody re-adds them:
-

## When adding a new dependency
1. Confirm nothing above already covers it.
2. Confirm it's maintained: commits in the last 6 months, no unaddressed
   critical issues, license compatible with this project.
3. Prefer the library the ecosystem has converged on over the trendy one,
   unless the trendy one solves a problem you actually have.
4. Use Context7 (`use context7`) to get the current API before writing
   against it — don't write from memory.
5. Add it to the table above with the "why."

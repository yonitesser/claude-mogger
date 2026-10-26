
# Planning: TASKS.md

Read when a feature has more than one step. Skip it for a single small fix.
You turn the request into a task board, then work it one task at a time.
Plan in a few lines; do not write code while planning.

Process:
1. Read enough of the codebase (Grep/Glob, not full files) to understand
   existing patterns and where this feature fits.
2. Break the work into tasks small enough that each one:
   - Touches a clearly bounded set of files
   - Has an obvious way to verify it worked (a test, a manual check)
   - Doesn't depend on a task later in the list
3. Write the task list to TASKS.md in this format:

```markdown
# TASKS: <feature name>

## Status: in-progress

- [ ] 1. <task> — files: <paths> — done when: <check>
- [ ] 2. <task> — files: <paths> — done when: <check>
- [ ] 3. <task> [parallel-with: 4] — files: <paths> — done when: <check>
- [ ] 4. <task> [parallel-with: 3] — files: <paths> — done when: <check>
```

The `files:` field is **enforced by a hook**, not decorative. While you work
on a task you cannot edit a file outside that task's declared list —
the edit is blocked. So list every file the task genuinely needs
(comma-separated; directory prefixes and globs work: `src/api/`,
`src/*.ts`). Under-declaring wedges you; over-declaring defeats
the point. If you can't predict the file list, write the task smaller
until you can.

The "done when" field must be something a machine or a one-glance human
check can verify — a specific test passes, a specific command returns a
specific output, a specific endpoint returns 200. "Done when: it works
correctly" or "done when: thoroughly tested" is not acceptable — rewrite
it as a count or a concrete check before moving on.

## Marking tasks parallel-safe

Two tasks can run at the same time only if **their `files:` lists don't
overlap at all** — not one shared file, not one shared directory prefix.
Mark those with `[parallel-with: N]` on both tasks. Tasks marked this way may be done in any order; everything unmarked runs in order.

Be conservative. If two tasks both touch a shared config, a shared type
definition, or the same test file, they are NOT parallel-safe even if the
logic is unrelated. Mark nothing rather than mark wrong — a false parallel
marking produces two edits fighting over one file, which is worse than
slower sequential work. Never mark a task parallel with one it depends on.

## Library check before writing code

If any task would involve writing something that sounds like a solved
problem — date math, retries, validation, parsing, HTTP, caching, auth,
state machines — do not plan for hand-written code by default. Add a note
on that task: `[library-scout first]`. Run the
`library-scout` agent before building it, and the scout may come
back with "write it yourself," which is a fine outcome. The point is that
the decision gets made deliberately once, rather than defaulting to
reinvention.

4. Do not start building until TASKS.md is written.

If the request is too vague to plan (e.g. missing which part of the app,
unclear success criteria), write down the specific question in TASKS.md
under "## Open questions" and stop — do not guess and proceed.

## When SPEC.md exists

If a `SPEC.md` exists at the project root, it is the source of requirements:

- Every task must trace back to a `Must have` item in SPEC.md. Write the
  item id in the task, e.g. `(M2)`.
- Each task's `done when:` must be copied or refined from SPEC.md's
  `Done when` list, never weaker than it.
- Do not invent requirements that are not in SPEC.md. If something seems
  missing, list it under `## Open questions` in TASKS.md instead of
  planning it.
- Anything under `Won't do (this round)` gets no task.

## Unhappy paths

Every task that touches user input or I/O (forms, handlers, endpoints,
fetches, file/DB access) needs at least one unhappy-path `done when:` in
addition to the happy-path one - e.g. "done when: submitting an empty name
shows 'Name is required' and saves nothing" or "done when: with the API
stubbed to 500 the page shows a retry message". Pick from the
`mogger:edge-cases` checklist (empty, whitespace, huge, wrong type, duplicate
submit, timeout/offline, server 500, slow response, permission denied). If a
row genuinely does not apply, write `n/a: <reason>` on the task. Do not
plan a task touching input/IO with only a happy-path check.

## Requirements per task

Under each task, list its requirements as short lines, one fact each,
numbered `R1`, `R2`, ... Include exact values and units from the request
(e.g. "price is stored in cents"). The reviewer checks every `R` line on
its own, so a requirement that is not written here is not checked.

---
name: standards
description: Coding standards: Karpathy principles, library choice via STACK.md and Context7, output-token discipline, what "clean" means, SkillSpector before installing third-party code. Load before writing code or adding a dependency.
---

# mogger coding standards

## Coding standards

### Core coding principles (Karpathy-derived, small and non-negotiable)

- **Think before coding**: state assumptions explicitly, don't silently pick
  an interpretation when the request is ambiguous — ask or present options.
- **Simplicity first**: minimum code that solves the problem, nothing
  speculative, no unrequested flexibility. If 200 lines could be 50, rewrite it.
- **Surgical changes**: touch only what the task requires. Don't "improve"
  adjacent code, don't refactor things that aren't broken, don't delete
  pre-existing dead code unless asked — mention it instead.
- **Chesterton's Fence**: before you delete or "simplify" code, find out why
  it is there (read the callers, `git log`, a test). If you cannot tell, keep
  it and say so.
- **Goal-driven execution**: turn imperative instructions into verifiable
  goals ("fix the bug" → "write a test that reproduces it, then make it
  pass"). This is what makes `planner`'s "done when" rule actually work.

### Library selection — decide once, in STACK.md

Before adding any dependency: check STACK.md, then check what the codebase
already imports for that job. Add something new only if nothing covers it,
and record the decision in STACK.md with the "why." Never have two
libraries doing the same job. Prefer what the ecosystem has converged on
over what's trending this month, unless the trending one solves a problem
this project actually has.

When writing against a library's API, don't write from memory — training
data is a snapshot, APIs move. Use Context7 (`use context7` in the prompt,
or install its skill so it triggers automatically) to pull the current,
version-specific docs first. Hallucinated or deprecated API calls are the
single most common way "working" generated code turns out not to work.

```
claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp
```

### Output-token discipline

Output tokens cost more than input tokens, and ceremony adds noise.
Keep replies short:

- No preambles ("Great, let me…"), no restating the request, no sign-off
  summaries of what you just did unless asked.
- Never re-print unchanged code. Show the diff, or the changed function
  only, and name the file.
- Don't narrate tool calls ("Now I'll read the file"). Just do it.
- One sentence of explanation per non-obvious change. Zero for obvious
  ones.
- When reporting test results: counts and failures only. Passing tests
  don't need to be listed.
- Pipe noisy commands (tests, builds, `git log`) through `| tail -n 80`
  or `| grep`, so one failing line is not buried in thousands.

### Code quality is enforced, not requested

A PostToolUse hook runs the project's own formatter and linter on every
file you edit (`auto-format.sh` — detects prettier/biome/eslint/ruff/
black/gofmt/rustfmt/etc. from the project's config; installs nothing).
Don't fight it, don't hand-format, don't add formatting-only edits. If it
reformats something you wrote, that was the project's style, not yours.

Beyond formatting, "clean" means: the Karpathy principles above, no dead
code, no commented-out blocks, no TODO without an owner, no clever
one-liner where two clear lines would do, and no abstraction introduced
for a single use.

## Before installing ANY third-party skill or subagent

Don't add a skill, subagent, or plugin from a repo, a marketplace, or a
thread on the internet without scanning it first. Agent skills run with
real access to your files, network, and environment variables — there is
no security gate between "install" and "it's running." Use NVIDIA's
SkillSpector (github.com/NVIDIA/SkillSpector, real and actively maintained)
to scan before you trust:

```
git clone https://github.com/NVIDIA/skillspector.git
cd skillspector && uv venv .venv && source .venv/bin/activate && make install
skillspector scan <path-or-github-url>
```

0-20 = safe, 21-50 = review the findings yourself, 51+ = don't install.
This applies to anything you're tempted to add after reading a "10 repos
that make Claude Code better" thread — popularity and star count are not
a safety signal. Scan first, install second.

## Optional companions

planning-with-files, Superpowers, headroom and the frontend-design skills are compared in `skills/standards/companions.md`. Read it only when choosing one. Verdicts: CONSIDERED.md.

## design-mogger — a good front end, same care as the back end

Load this only when the task builds or changes UI. Other tasks: skip it.

1. **Designer question.** Before each UI choice ask: "Would an experienced
   product designer pick this on purpose?" If not, fix it first.
2. **One system, not many.** Pick one type scale, one spacing scale, one
   small colour set. Put them in CSS variables or the theme file. No
   one-off pixel values or random colours.
3. **Clear hierarchy.** One main action per screen. Size and weight show
   what matters. Not everything in a card; no card grids by default.
4. **No slop.** No random gradients, no default-Tailwind look, no
   decoration with no job. Motion must show a state change; keep it short.
5. **Every state.** Build empty, loading, error and success views, not
   only the happy one (see mogger:edge-cases).
6. **Check it.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/checks/a11y.sh"`. If the app runs and
   playwright and axe-core are installed, also run
   `node "${CLAUDE_PLUGIN_ROOT}/scripts/a11y-browser.mjs" http://localhost:3000` (phone width,
   375px). Report what you ran before you say "done".
7. **Interaction CSS.** Put every `:hover` rule inside
   `@media (hover: hover) and (pointer: fine)`. Give each button, link and
   card an `:active` state. A transition that moves or scales something
   goes inside `@media (prefers-reduced-motion: no-preference)`; name its
   properties (never `transition: all`). Idea from vojtaholik/good-css (MIT).
8. **Direction help (optional).** If taste-skill is installed, use it for
   overall feel. For lookups (fonts, palettes) use ui-ux-pro-max. Scan
   them first (SkillSpector rule above). Mogger does not depend on them.

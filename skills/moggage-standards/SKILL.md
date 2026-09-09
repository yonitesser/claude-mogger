---
name: moggage-standards
description: Coding standards enforced by this plugin — Karpathy principles (think first, simplicity, surgical changes, goal-driven), library selection via STACK.md and Context7, output-token discipline, what "clean" means beyond the auto-formatter, and the SkillSpector rule before installing anything third-party. Load before writing or reviewing code, or when about to add a dependency.
---

# moggage coding standards

## Coding standards

### Core coding principles (Karpathy-derived, small and non-negotiable)

- **Think before coding**: state assumptions explicitly, don't silently pick
  an interpretation when the request is ambiguous — ask or present options.
- **Simplicity first**: minimum code that solves the problem, nothing
  speculative, no unrequested flexibility. If 200 lines could be 50, rewrite it.
- **Surgical changes**: touch only what the task requires. Don't "improve"
  adjacent code, don't refactor things that aren't broken, don't delete
  pre-existing dead code unless asked — mention it instead.
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

Output tokens cost ~5× input on Opus-class models. Most of the waste is
ceremony. Cut it:

- No preambles ("Great, let me…"), no restating the request, no sign-off
  summaries of what you just did unless asked.
- Never re-print unchanged code. Show the diff, or the changed function
  only, and name the file.
- Don't narrate tool calls ("Now I'll read the file"). Just do it.
- One sentence of explanation per non-obvious change. Zero for obvious
  ones.
- When reporting test results: counts and failures only. Passing tests
  don't need to be listed.

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

## Optional companions (pick what fits — see CONSIDERED.md for verdicts)

### Superpowers — alternative to the custom agents above

`obra/superpowers` (github.com/obra/superpowers, on Anthropic's official
plugin marketplace) is a mature, actively maintained system that does close
to the same plan → build → test → review loop as the `planner`/`builder`/
`tester`/`reviewer` subagents in this kit — but it's had far more real-world
use than anything assembled in an afternoon. If you'd rather not maintain
custom subagents, install Superpowers for the loop itself and keep this
kit's 3 hooks underneath it (`require-approval.sh`, `protect-pipeline-
files.sh`, `require-tests-pass.sh`) — hooks fire on the tool call itself,
regardless of which skill or subagent triggered it. One adjustment needed:
`require-tests-pass.sh` currently checks for a subagent named `reviewer` —
if you go this route, find whichever step in Superpowers does final review
before you'd approve a merge, and point the hook's subagent-name check at
that instead.

### headroom — compression proxy (github.com/headroomlabs-ai/headroom)

Real, active, Apache 2.0. A local compression proxy that shrinks tool
output, logs, and file reads before they reach the model — reversible,
so the model can retrieve the original if it needs it. Runs entirely on
your machine.

**Overlaps with two things already in this kit — know both exist, pick one:**

- `bulk-reader`/`code-writer` route big reads to a cheaper model. Headroom
  compresses the content itself, works regardless of model, and is more
  thorough (logs, JSON, RAG chunks, not just files over a line threshold).
  If you adopt headroom, you likely don't need the bulk-reader hook
  anymore — headroom handles it upstream of any model call.
- `retro` + `CONSTRAINTS.md` mine session history and propose corrections
  you approve by hand. `headroom learn` does the same job automatically,
  writing straight to CLAUDE.md without a human-approval step. Ours gives
  you the review gate; headroom's is faster but skips it. Your call which
  fits your risk tolerance better.

```
pip install "headroom-ai[all]"
headroom wrap claude          # starts a local proxy, wraps this session
headroom unwrap claude        # undo
```

Turn off telemetry if you want: `HEADROOM_BEACON=off`. It's on by default
and anonymous (no prompts/code in it), but the toggle exists.

### Frontend design skills

Neither of these touches the approval-gate stuff above — they're reference
tools for UI work. Both go through the SkillSpector scan rule above like
any other third-party skill before you install them.

**ui-ux-pro-max** (nextlevelbuilder/ui-ux-pro-max-skill) — a searchable
database: UI styles, color palettes, font pairings, chart types, UX
guidelines, across ~22 tech stacks. Good for concrete lookups.

```
/plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
/plugin install ui-ux-pro-max@ui-ux-pro-max-skill
```

**taste-skill** (Leonxlnx/taste-skill) — opinionated frontend "taste": reads
your brief, tunes layout variance/motion/density, actively fights generic
AI-slop output. Good for overall creative direction, not lookups.

```
npx skills add https://github.com/Leonxlnx/taste-skill --skill "design-taste-frontend"
```

**When to reach for which:** if the question is concrete ("what's a good
font pairing for a fintech dashboard," "give me a chart type for this data")
→ ui-ux-pro-max. If the question is about overall feel ("make this landing
page not look like every other AI-built landing page") → taste-skill. They
don't conflict — one's a reference lookup, the other's a generation
direction — so both can stay installed at once.


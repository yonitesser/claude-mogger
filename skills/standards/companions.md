# Optional companions (reference, not auto-loaded)

Moved out of SKILL.md so the standards skill stays short. Verdicts for each are in CONSIDERED.md.

### planning-with-files — alternative to TASKS.md + stop-done-means-done.sh

`OthmanAdi/planning-with-files` (github.com/OthmanAdi/planning-with-files)
is a more mature, cross-platform version of this kit's completion-gate
idea: a 3-file pattern (task_plan.md / findings.md / progress.md) plus a
Stop hook that blocks ending a turn on unfinished work — v3.0.0, 178
tests, works across 17+ platforms, published benchmark with an honest
methodology caveat. Genuine overlap with `TASKS.md` +
`stop-done-means-done.sh`. If you adopt it, disable this kit's Stop hook
(remove the `Stop` entry from settings.json / hooks.json) — running both
means two different completion gates arguing with each other over the
same turn.

### Superpowers vs this kit's agents — a real comparison, not "pick one"

Read Superpowers' actual skill list (`obra/superpowers`, on
Anthropic's official marketplace) before assuming it's simply better.
Here's where each one actually wins:

**Superpowers is stronger at:**
- **Requirements-gathering.** Its `brainstorming` skill interrogates the
  request with Socratic questions before any plan exists. This kit's
  `planner` assumes the request is already well-specified and jumps
  straight to task breakdown — a real gap if the request is vague.
- **TDD rigor.** `test-driven-development` enforces RED-GREEN-REFACTOR
  and explicitly deletes code written before its test existed. This kit's
  `tester` only checks that tests pass after the fact — it doesn't care
  whether the test was written first.
- **Branch isolation.** `using-git-worktrees` gives each unit of work an
  isolated workspace. This kit works directly on whatever branch you're
  on.
- **Breadth.** 13 skills including systematic debugging and parallel
  agent dispatch; this kit has 8 agents covering a narrower slice.

**This kit is stronger at:**
- **A gate that can't be talked around.** Superpowers' discipline is
  skill/prompt-level — "the agent checks for relevant skills before any
  task," which is real but still something the model has to choose to
  honor. This kit's `require-tests-pass.sh` and the approval hooks are
  bash scripts checking actual exit codes and actual branch names,
  outside any model's judgment. Notably, Superpowers'
  `finishing-a-development-branch` skill *offers* merge/PR/discard as
  conversational options — it doesn't appear to hard-block a merge the
  way `require-approval.sh` does. If a hard, unconditional block on
  push/merge/deploy/money matters to you, that's not something Superpowers
  replaces.
- **Model routing.** Nothing in Superpowers' skill list assigns
  cheaper models to I/O-only work. This kit's `bulk-reader`/`explorer`/
  `tester`/`code-writer` run on Haiku so reads, searches, and
  test runs stay out of the Lead's context. That's orthogonal to what
  Superpowers does and not something adopting it gives you.

**The honest recommendation: compose them, don't choose one.** Install
Superpowers for brainstorming/TDD/worktrees — it's more mature there than
anything built in an afternoon. Keep this kit's hooks running underneath
regardless (`require-approval.sh`, `protect-pipeline-files.sh`,
`require-tests-pass.sh`, `stop-done-means-done.sh`) — they fire on the
tool call itself, regardless of which skill or subagent triggered it, so
they layer under Superpowers without conflict. Retire this kit's
`planner`/`builder`/`reviewer` agents at that point — running both
loops on the same task is the actual redundancy, not the hooks. Keep
`bulk-reader`/`explorer`/`tester`/`code-writer` (Haiku routing) since
Superpowers has no equivalent. One adjustment: `require-tests-pass.sh`
checks for a subagent named `reviewer` — point it at whichever Superpowers
step does final review (`MOGGER_REVIEWER_NAME` env var) before you'd
approve a merge.

### headroom vs this kit's model routing — partial overlap, not full

`headroomlabs-ai/headroom` (Apache 2.0) is a local compression proxy that
shrinks tool output, logs, and file reads before they reach the model —
reversible, model-agnostic. It solves a different axis than this kit's
Haiku routing, so they mostly stack rather than compete:

- **Real overlap, on big-file reads only:** `check-file-size.sh` blocks a
  direct Read over 350 lines and routes it to `bulk-reader` (Haiku).
  Headroom's proxy would already have compressed that same file's bytes
  before either the Lead or `bulk-reader` saw them. Running both means
  the block-and-reroute is redundant for that one case — **if you adopt
  headroom, drop `check-file-size.sh` and `check-bash-read.sh` specifically**
  (not the whole `bulk-reader` agent).
- **No overlap:** headroom doesn't choose *which model* handles a task —
  it just shrinks whatever bytes flow through. `bulk-reader`/`explorer`/
  `code-writer`/`tester` still matter on top of headroom, because they
  route entire tasks to Haiku regardless of how compressed the content
  is. Keep them.
- **No overlap:** `retro` + `CONSTRAINTS.md` require human approval before
  a correction becomes a permanent rule. `headroom learn` writes directly
  to CLAUDE.md with no approval step — faster, but skips the gate. Keep
  whichever matches your risk tolerance; they don't conflict technically,
  just don't run both learning loops on the same file simultaneously.

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



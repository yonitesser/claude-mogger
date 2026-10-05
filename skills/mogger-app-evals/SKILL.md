---
name: mogger-app-evals
description: Evals for the user's OWN Claude-calling app (anthropic / @anthropic-ai/sdk): prompts, model choice, cost. Use when asked "eval my app", "hillclimb", "is Haiku enough for my app". Not mogger's own agents (see mogger-evals).
---

# mogger app evals: the user's own Claude app

This skill is for apps the user builds that call Claude. For mogger's own
agents use `mogger-evals` instead.

## Detect

Look for the SDK in the dependency files (read them, do not guess):

- `package.json`: `@anthropic-ai/sdk`
- `requirements.txt`, `pyproject.toml`, `Pipfile`: `anthropic`

If none is present, say the project does not use the Anthropic SDK and stop.

## Recommend

Anthropic's article "Automating eval design and hillclimbing with Claude"
says the `claude-api` skill has two sub-commands:

1. `/claude-api build-eval` builds an eval inside the codebase. It
   interviews the user and asks for approval of the examples and the grader.
2. `/claude-api hillclimb` improves the app against an eval, one change
   at a time, with a held-out set to catch overfitting.

Say that these come from the `claude-api` skill. Do not describe options,
flags or output beyond what the article says. If the skill is not
installed, tell the user and do not invent the commands. Running them
calls the API, so it costs money. Say that before the user starts.

## Principles to carry (short rules)

- **Mirror production.** Sample tasks from real traffic, bug reports and
  tickets first, then hand-written cases. Users try what they expect to
  work, so real traffic can skew easy. Add cases you can explain as hard.
- **Stronger should score higher.** A stronger model or more thinking
  should score higher. If not, suspect vague tasks or a bad grader.
- **Leave headroom.** If the baseline is near 95% or more, quality cannot
  improve much. Aim at cost or speed.
- **Low run-to-run variance.** High variance means vague tasks, a shaky
  grader, or leftover state between runs. Run the grader twice on the same
  output. Check for timeouts and API errors.
- **Cheapest grader that fits.** Code check first (exact match, a label
  from a fixed set, JSON schema, tests pass). Use an LLM judge only for
  open-ended output. The judge must be a different model from the one
  tested. Write the rubric as checkable claims, not a 1-to-5 scale.
- **Read graded transcripts.** Read a sample before you trust the grader.
  Bad graders are a common reason an eval misleads.
- **Split the cases.** Train cases the tuner may read. Held-out cases it
  never sees. Train up and held-out flat is a sign of overfitting.
- **Never paste failures into the prompt.** Fix the cause, not the case.
  Keep answers out of the model's reach.
- **Cost is a good goal.** Even when quality is saturated, ask for lower
  cost at the same score (model, effort, caching).
- **Noise first.** If the gain is within noise, do not ship the change.

## Talk to the user

Short sentences. Say what the eval will test, the rough size (cases x
repeats x model), and that it costs money. Ask before running anything
that calls the API. Do not run either command for the user unasked.

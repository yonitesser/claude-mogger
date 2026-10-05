---
name: mogger-evals
description: Paid evals of mogger's own agents (do cheaper models match Sonnet?). Use when asked about "evals", "raise the evals cap", "turn off evals", model-routing cost questions, or when the session-start message mentions evals.
---

# mogger evals

Two tiers. Keep them apart when you talk to the user.

- **Free tier.** `bash scripts/checks/evals-static.sh` reads agent and skill
  files. No API calls, no cost. It lists facts (a skill with no trigger
  phrase, two skills with near-identical descriptions, a Haiku agent with
  Write). It cannot say if a model is good enough. Run it any time.
- **Paid tier.** `scripts/mogger-eval.sh` runs real Claude API calls on test
  cases and compares models. It costs money. It never runs without the
  user's yes to a dollar cap.

## What the paid evals give the user (say this in one plain paragraph)

They show which agents can stay on the cheap model (Haiku) and which need
Sonnet, with numbers from test cases, not guesses. Agents that pass can
save money. Agents that fail get a safer setting. After one yes to a cap,
the tests re-run by themselves in the background when agents change, always
inside the cap.

Use short sentences and plain words. No jargon. Do not promise savings.
Say "can" and give the estimate.

## Talk to the user

1. Run `bash scripts/mogger-eval.sh estimate`. Show the number as written.
   If the script is missing, say so and stop. Do not invent a number.
2. Ask for a cap. Give at most two options: a recommended default (about
   2x the estimate) and one smaller. Example: "Cap it at $X (recommended)
   or $Y?" Say that the cap is the most it will ever spend, and that
   `consent --revoke` stops it.
3. On a clear yes: `bash scripts/mogger-eval.sh consent --budget <USD>`,
   then `bash scripts/mogger-eval.sh run --background`. Tell the user where
   results will appear: `.claude/state/evals/report.md`.
4. On no or "not now": write `{"state":"dismissed","shown_at":<epoch>}` to
   `.claude/state/evals/nudge.json` (create the folder). The nudge then
   stays quiet. Do not ask again this session.
5. "Turn it off": run `consent --revoke`. Mention `MOGGER_EVALS=off` hides
   the session-start message.

A yes to something else is not a yes to spending. Never run `run`,
`hillclimb` or `consent` unless the user agreed to a dollar amount in
this conversation.

## Read the results

`bash scripts/mogger-eval.sh status` shows a run in progress. Read
`.claude/state/evals/report.md` and tell the user, per agent: matches
Sonnet, worse than Sonnet, or too close to call. Quote the numbers. If the
report says a result is within noise, say "no change is justified".
Never say "good enough" without a report line to point at.

## Apply a recommendation

`bash scripts/mogger-eval.sh apply` changes agent settings. Only do it
when the user says yes to that specific change. It must write
project-level overrides only (the project's `.claude/agents/`). Never edit
the plugin's own files. Show the diff first. Tell the user how to undo it
(delete the override file).

## Rules from Anthropic's eval-design article (short)

- Hidden held-out cases. The tuner reads train cases only. Test cases
  stay out of its reach.
- Never paste a failing case into a prompt. Fix the cause, not the case.
- No change if the gain is within noise. Say so and do not apply.
- Headroom. If the strongest model already scores about 95% or more, the
  test cannot show quality gains. Aim at cost instead.
- Read a sample of graded transcripts before you trust a grader.

## Limits

- Estimates are estimates. Real cost can differ. The cap is enforced by
  the script, not by this text.
- Evals test mogger's own routing. For the user's own app that calls
  Claude, use `mogger-app-evals`.

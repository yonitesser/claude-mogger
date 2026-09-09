# CURATION.md — what earns a place here

Every tool, skill, hook, or rule in this kit passed the checks below. Every
one that didn't is in CONSIDERED.md with the reason. This file exists so the
filter is inspectable, not vibes.

## Hard requirements (all must be true)

1. **It's real.** The repo exists, has recent commits, real issues, and CI.
   Star counts from a tweet don't count — we look at the repo.
2. **The claim is falsifiable.** "20% fewer tokens, measured with the
   provider tokenizer, seeded benchmark you can re-run" passes. "Makes
   Claude 10x better" fails. If the only evidence is a testimonial, it's
   out.
3. **It does something a prompt can't.** Hooks run code the model can't
   talk its way past. Context7 fetches facts the model doesn't have. A
   compression proxy changes what bytes reach the model. A markdown file
   that says "please write good code" does not clear this bar on its own —
   unless it's small enough to cost nothing and encodes something
   specific and non-obvious (the Karpathy principles qualify; most "be a
   senior engineer" prompts don't).
4. **It doesn't remove a human gate.** Anything that auto-merges,
   auto-deploys, auto-sends, or auto-edits its own constraints without a
   review step is out, no matter how good the rest is.
5. **It's honest about its limits.** A "when to skip this" or
   "limitations" section is a strong positive signal. Caveman documenting
   the cases where it *loses* money is why it's mentioned here at all.
6. **No funnel.** If the primary call-to-action is "follow me / join my
   Telegram / DM for the real version," the content is marketing and gets
   evaluated as marketing. The tool it points at may still be fine — the
   thread itself is not the source.

## Soft signals (raise or lower confidence)

- **Positive:** on Anthropic's official plugin marketplace; Apache/MIT
  license; a reputable org or a known individual with a track record;
  benchmarks with methodology published; telemetry that's disclosed and
  has an off switch.
- **Negative:** install command is `curl | sh` from a non-GitHub domain;
  a fake npm package squatting the name (GBrain warns about exactly
  this); "up to 300 agents" style capacity claims with no cost figures;
  security assessments with known poor results and no remediation
  timeline.

## The overlap rule

Two things that do the same job don't both go in. If a mature external
tool covers what a hand-rolled piece does, the kit says so and tells you
to pick one (see headroom vs bulk-reader, Superpowers vs the custom agents).
Stacking three orchestration frameworks is how setups get slow and
contradictory.

## The "keep the hooks" rule

Whatever else you swap out, the three approval-gate hooks stay. They're
the only part of this kit that doesn't depend on the model behaving.

## What this rubric rejects on purpose

- Tools for a different job (knowledge-graph builders, video generators,
  personal-assistant daemons) — not bad, not relevant to a coding loop.
- Anything that requires connecting company comms (Slack, email, WhatsApp)
  to an agent with a weak security record.
- Region/origin-sensitive code that runs and fetches data, unless the
  team has explicitly signed off on that.
- Duplicates of behavior already locked in by the user's own preferences.

## How to propose an addition

Open an issue with: the repo link, which hard requirement it clears and
how, what it overlaps with in the current kit, and the honest limitation
you'd write in CONSIDERED.md if it *didn't* make the cut. If you can't
write that last part, it's probably not ready.

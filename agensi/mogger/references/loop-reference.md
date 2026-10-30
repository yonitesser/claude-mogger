# Loop reference

Read only when needed. The loop itself is in `SKILL.md`.

## `effort:` — a second dial, independent of `model:`

Claude Code subagent frontmatter supports an `effort` field
(`low|medium|high|xhigh|max`) that controls reasoning depth, separately
from which model runs. The five Haiku agents above (and the Sonnet docs-writer) set `effort: low`
— none of them do anything that benefits from more thinking; they read a
file, grep, run a command, or copy a pattern.

**Verify it's actually taking effect.** One real-world report claims
`effort:` in frontmatter can be a no-op specifically on Task-tool spawns
— which is exactly how this kit dispatches every subagent. Anthropic's
own docs list it as a working, honored field, so this may be
environment- or version-specific, but check rather than assume: after a
`bulk-reader` or `explorer` call, glance at that call's token count in your
session's cost breakdown. If it looks the same as before this field
existed, `effort` isn't landing on your setup and you're not losing
anything by leaving it in — it just isn't helping yet either.

Don't add `effort:` to the Sonnet-tier agents without a specific reason.
`reviewer` and `library-scout` are doing judgment work;
capping their reasoning to save a fraction of a cent is the wrong trade.

## Model aliases move underneath you

`model: sonnet` and `model: haiku` are aliases, not pinned versions —
Claude Code resolves them to whatever the current model is. When Sonnet
5.5 shipped, every Sonnet-tier agent in this kit (`reviewer`, `retro`,
`library-scout`) started running on it automatically,
at Sonnet 5's unchanged per-token price, with no file edit required. This
cuts both ways — a future alias change could shift behavior you didn't
ask for. If an agent's output quality changes noticeably after a model
release, that's the likely cause; check which model it actually ran on
before assuming the prompt broke.

## Does the Lead still need Opus?

Worth revisiting per project, not assuming. Sonnet 5.5 lands within a few
points of Opus 5.5 on many coding and knowledge-work benchmarks at roughly
half the price, and Anthropic's own guidance is direct about where the
line still is: Opus for "the hardest long-horizon work," Sonnet for
well-scoped everyday tasks. If your projects are mostly well-scoped
feature work, running the Lead itself on Sonnet may now be enough — try
it on one project before assuming you need Opus everywhere. Reserve Opus
for genuinely ambiguous, open-ended, high-judgment orchestration.

**Tuning:** if a project is small and Sonnet is your Lead, the pattern still holds — Haiku for I/O, Sonnet for thought.
If a large system needs a genuinely hard architecture call, bump `reviewer`
to `model: opus` for that project. Never bump `explorer` or
`bulk-reader` — there is no task they do that gets better with a smarter
model.


## Optional: the advisor tool

Claude Code has an experimental **advisor**: a smaller main model (say
Sonnet) can consult a stronger model (say Opus) at decision points, such as
before it picks an approach, when an error keeps coming back, and before it
says "done". The user turns it on with `/advisor opus` (or the
`advisorModel` setting, or `claude --advisor opus`). A plugin cannot turn it
on for them. Facts from Anthropic's docs (code.claude.com/docs, "Escalate
hard decisions with the advisor tool"):

- The advisor must be at least as capable as the main model. Sonnet 5.5 as
  main accepts Fable, Opus 4.7 or later, or Sonnet 5 or later as advisor.
- Claude decides when to call it. It cannot be forced or counted by a hook.
  So it supports mogger's gates. It never replaces them: tests, review and
  the approval gates still run by exit code.
- It bills advisor tokens (API rates, or plan usage limits), and it needs
  the Anthropic API. It is not available on Bedrock, Vertex or Foundry, and
  it stays off when `DISABLE_TELEMETRY` is set.
- Subagents inherit the advisor. Mogger's `savings-report` does not count it.

Sonnet as Lead plus an Opus advisor is one setup to try on a project. If you are
stuck on a recurring failure and the advisor is on, ask it before trying a
fourth fix.

## Routing log — the Lead writes it, not the Haiku agents

`bulk-reader`, `explorer` and `code-writer` have no Bash tool on purpose (they
stay read-only or write-only), so they cannot log anything themselves. After
one of them returns, the Lead runs one line:

```
bash ".claude/mogger-skill/hooks/scripts/log-savings.sh" <agent> haiku INPUT_CHARS OUTPUT_CHARS
```

`OUTPUT_CHARS` is the length of the reply the Lead received. `INPUT_CHARS` is
the size of what the agent had to read: use `wc -c` on the files named in the
request (skip the log if you cannot tell). Agents that do have Bash
(`fact-checker`, `explainer`, `docs-writer`) still log
their own runs. Both kinds stay self-reported estimates.

## Optional: the routing estimate is a different thing than RUNS.md tokens

RUNS.md's `tokens:` field is the real, actual session total from `/cost` —
solid ground. `python3 ".claude/mogger-skill/scripts/savings-report.py"` is something weaker and
should never be confused with it: an *estimate* of what Haiku-routed calls
would have cost if billed at the Lead's model rate instead, based on
self-reported (not verified) output length. No task here was ever run
twice to produce a real before/after number — this is a disclosed
calculation, not a measurement. Both the terminal output and the generated
`savings-dashboard.html` state this plainly. If asked "how much does this
kit cost," point to RUNS.md's real totals first; mention the estimate
second, with its caveat intact.

# CONSIDERED.md — everything we looked at, and why

Evaluations current as of September 2026. Verdicts can change; if you find
one that's out of date, open an issue.

Verdict key:
- **IN** — part of the kit (files in `incoming/`)
- **COMPANION** — recommended external install, documented in
  `CLAUDE.md.snippet`, not bundled
- **OPTIONAL** — real, fine, situational; mentioned, not pushed
- **OUT** — evaluated and rejected, reason given

---

## Orchestration / discipline

| Tool | Verdict | Why |
|---|---|---|
| This kit's planner/builder/tester/reviewer/retro agents | IN | Hand-built, but the *hooks* under them are the real value. The agents are a reference implementation of the loop; swap for Superpowers if you prefer. |
| [obra/superpowers](https://github.com/obra/superpowers) | COMPANION | Real (280k+ stars), on Anthropic's marketplace, mature plan→build→TDD→review loop. Does what our agents do, with more real-world use. Pick one. Keep the hooks regardless. |
| [affaan-m/ECC](https://github.com/affaan-m/ECC) | OUT (overlap) | Real, legit, actively maintained, warns about malware mirrors of itself. But it's a full competing orchestration system — installing it alongside this kit or Superpowers gives you two loops fighting. Fine choice *instead of* this kit; not *with* it. |
| [garrytan/gstack](https://github.com/garrytan/gstack) | OUT (overlap) | Real. 23 slash-command "virtual startup" workflow. Same overlap problem as ECC. |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | OUT (overlap) | Real, reputable author. Define/plan/build/verify/review/ship lifecycle. Third orchestration system — same reason. Note: has an `auto` mode that removes checkpoints during build; if you use it, keep our hooks on. |
| [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) | IN | Single CLAUDE.md, 4 principles, no dependencies. Small enough to cost nothing, specific enough to matter (surgical changes, goal-driven execution). Folded into `CLAUDE.md.snippet`. |
| [mattpocock/skills](https://github.com/mattpocock/skills) | OPTIONAL | Real, TS/JS-leaning discipline skills (/grill-me, /tdd). Good if you're heavy TypeScript; skews toward one stack, so not a default include. |

## Token / cost

| Tool | Verdict | Why |
|---|---|---|
| Spotify "Portal shunt" pattern | IN (as pattern) | The idea — block big reads at the hook level, route to a cheap model — is sound and we implemented it (`check-file-size.sh`, `bulk-reader`). Spotify's actual Portal platform is internal infra you can't install. |
| [headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom) | COMPANION | Real (69k stars), Apache 2.0, seeded reproducible benchmarks, runs locally, reversible. More thorough than our bulk-reader hook. Overlaps with it — pick one. Telemetry on by default, `HEADROOM_BEACON=off`. |
| [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | OPTIONAL | Real. Documents the cases where it *loses* money — that honesty is why it's here. Narrower than headroom. |
| [safishamsi/graphify](https://github.com/safishamsi/graphify) | OPTIONAL | Real. Codebase knowledge graph to avoid re-reading files. Pays off on large codebases run many times a day; on small ones, plain search is as cheap. Their own docs say the 71x figure is best-case. |

## Current facts

| Tool | Verdict | Why |
|---|---|---|
| [upstash/context7](https://github.com/upstash/context7) | COMPANION | Real, Upstash, on Anthropic's plugin marketplace. Fetches version-specific library docs into the prompt. This is the actual fix for "uses the wrong/deprecated API." Pure add, overlaps with nothing. |

## Security

| Tool | Verdict | Why |
|---|---|---|
| [NVIDIA/SkillSpector](https://github.com/NVIDIA/SkillSpector) | COMPANION | Real, NVIDIA, actively maintained. Scans skills for prompt injection / exfiltration / over-permissioning before install. The correct response to every "install these 10 repos" thread. |
| [mukul975/Anthropic-Cybersecurity-Skills](https://github.com/mukul975/Anthropic-Cybersecurity-Skills) | OUT (scope) | Real. 800+ security playbooks. Not relevant to a coding loop; would bloat context. Fine for security work specifically. |

## Design

| Tool | Verdict | Why |
|---|---|---|
| [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | OPTIONAL | Real. Searchable design database (styles, palettes, fonts, ~22 stacks). Has a freemium upsell. Good for concrete lookups. |
| [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | OPTIONAL | Real. Opinionated anti-generic frontend direction. Complements ui-ux-pro-max (lookup vs direction), doesn't conflict. |

## Different job entirely

| Tool | Verdict | Why |
|---|---|---|
| [openclaw/openclaw](https://github.com/openclaw/openclaw) | OUT (risk) | Real and huge. 24/7 personal-assistant daemon wired to WhatsApp/Slack/email. Publicly reported security assessment with a weak pass rate. Not a coding tool; keep off work machines and away from company comms. |
| [bytedance/deer-flow](https://github.com/bytedance/deer-flow) | OUT (scope/origin) | Real ByteDance project. Heavy multi-agent research orchestrator, Docker-first. Not a coding-loop tool. Runs code and fetches data; ByteDance origin is a legitimate posture question for some orgs. |
| [garrytan/gbrain](https://github.com/garrytan/gbrain) | OUT (scope) | Real. Personal knowledge graph of people/companies/meetings. Founder/investor tool, not a coding tool. Project itself warns of a fake `npm install -g gbrain` squatter — use the git clone path if you try it. |
| [calesthio/OpenMontage](https://github.com/calesthio/OpenMontage) | OUT (scope) | Video generation pipeline. Not relevant. |
| [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) | OUT (redundant) | Real. Makes replies terse and action-first. If you've already set that in your own preferences, this duplicates it. |
| [ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills) | OUT (not a tool) | Link directory. Useful for discovery, nothing to install. |

## Source threads (evaluated as marketing, not as tools)

| Source | Verdict | Why |
|---|---|---|
| @undefinedKi "Spotify Portal" thread | Pattern extracted, thread not cited | Pointed at a real Spotify engineering post. The pattern is good. The thread is a summary of it. |
| @undefinedKi "10 repos" thread | Tools checked individually | Every repo it named turned out to be real. Star counts and "most-starred software on GitHub" framing were inflated. Ends in a follow-me funnel. Verdicts above are from checking the repos, not from the thread. |
| @polydao "300 agents, one graph" thread | 4 ideas extracted, rest rejected | Real engineering ideas: countable stop conditions, corrections file, external gate not self-graded, capped retries with reason. All four are in this kit. The 300-agent knowledge-graph framing is for a different job and plugs a specific product. Ends in a Telegram funnel. |

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

## Batch 2 — Github-Ranking-AI Top 100 Claude list (2026-09-09)

Most of this 100-repo ranking is out of scope (general AI chat clients, job-search
tools, video generation, unrelated agent frameworks) or already evaluated above.
New findings:

| Tool | Verdict | Why |
|---|---|---|
| [OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files) | COMPANION | Real, v3.0.0, 178 tests, MIT, works across 17+ platforms. A more mature version of this kit's TASKS.md + stop-done-means-done.sh completion gate. Published benchmark (96.7% pass rate) with an explicit methodology caveat stating what it does and doesn't measure — exactly the honesty this rubric rewards. Genuine overlap: pick one. If you adopt it, `stop-done-means-done.sh` becomes redundant — its "gated mode" Stop hook does the same job with 5 conditions to avoid false-block loops. |
| [thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) | OUT (integrity) | Real, 93k stars, but: rebranded to "Grok Mem," defaults to a hosted-account sign-up with a free-trial-then-subscribe funnel, and the README promotes an associated cryptocurrency token with a contract address. A coin attached to a memory tool is disqualifying on its own regardless of star count or technical merit. |
| [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) | Reference | The actual official directory. Submission form: clau.de/plugin-directory-submission. Answers the earlier open question about official-marketplace listing. |
| [oraios/serena](https://github.com/oraios/serena) | OPTIONAL (lightly verified) | Real per the ranking data — MCP toolkit for semantic code retrieval/editing. Plausible companion to `explorer` for large codebases. Only checked via the ranking table, not independently fetched — verify yourself before relying on it. |
| [musistudio/claude-code-router](https://github.com/musistudio/claude-code-router) | OPTIONAL (lightly verified) | Real per the ranking data — local control plane for routing across models. Infra-level version of this kit's per-agent `model:` convention. Not independently fetched; if you want proxy-level model routing instead of per-agent frontmatter, worth a look yourself first. |
| free-claude-code, 9router, OmniRoute, CLIProxyAPI, sub2api, one-api, new-api | OUT (ToS risk, as a group) | Not individually deep-verified, but all seven follow the same pattern: pooling/routing around provider free-tier limits across multiple accounts or providers ("unlimited free AI"). Consistent enough as a group to flag rather than recommend — check your provider's ToS before using any of them. |

Everything else in the ranking (general chat clients, job-search agents, video
generation, unrelated multi-agent frameworks, marketing/academic/scientific skill
packs) — OUT (scope): not built for a coding discipline loop, however good they
may be at their actual job.

## Batch 3 — bundling and honest re-comparison (2026-09-09)

- **Context7 bundling confirmed possible and implemented.** Anthropic's own
  official marketplace bundles Context7 as a hosted remote MCP server
  (`.mcp.json` → `https://mcp.context7.com/mcp`, works anonymously, no
  local npx). This plugin now bundles the same `.mcp.json` at its root —
  Context7 registers automatically on plugin install, zero extra steps.
- **SkillSpector cannot be bundled the same way** — it's a standalone CLI,
  not an MCP server, so there's no manifest field that auto-installs it at
  plugin-install time. Closest real equivalent: `mogger-init` now detects
  and auto-installs it via `uv tool install` on first run (a small,
  reversible CLI install), rather than just telling the user the command.
- **Superpowers vs this kit's agents — read in full, not just described.**
  Superpowers is genuinely stronger at requirements-gathering
  (`brainstorming`), TDD rigor (deletes code written before its test),
  and git-worktree isolation. This kit is stronger at unconditional,
  non-bypassable gates (Superpowers' `finishing-a-development-branch`
  *offers* merge as a choice; it doesn't hard-block it the way
  `require-approval.sh` does) and Haiku-routed cost savings (nothing in
  Superpowers assigns cheaper models to I/O work). Verdict changed from
  "pick one" to "compose": use Superpowers' skills, keep this kit's hooks,
  retire this kit's planner/builder/reviewer agents specifically.
- **headroom vs bulk-reader/explorer — narrower overlap than first stated.**
  Only the big-file-read path (`check-file-size.sh`/`check-bash-read.sh` →
  `bulk-reader`) genuinely duplicates headroom's compression. Model-routing
  (which agent runs on which model) is a different axis headroom doesn't
  touch — `bulk-reader`/`explorer`/`code-writer`/`tester` stay regardless.

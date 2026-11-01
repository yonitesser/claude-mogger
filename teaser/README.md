# secret-guard

A free guard for Claude Code. It stops Claude from writing secrets into your files.

It is one guard from [Mogger](https://github.com/yonitesser/claude-mogger), a kit of safety guards for Claude Code.

## What it blocks

When Claude uses `Write` or `Edit`, the guard checks the text first. It blocks:

- API keys and tokens: AWS, GitHub, Anthropic, OpenAI, Stripe live keys, Slack.
- Private key blocks (`-----BEGIN ... PRIVATE KEY-----`).
- Lines like `password = "..."` or `api_key: "..."` with a long real-looking value.
- Any write to `.env` or `.env.*`. (`.env.example`, `.env.sample`, `.env.template` are fine.)

Claude gets a clear reason and is told to read the value from the environment instead.

It does not block normal code, placeholders (`your-key-here`, `xxx`, `changeme`), or code that reads `process.env.X`.

## Install (2 lines, inside Claude Code)

```
/plugin marketplace add {{GITHUB_ORG}}/mogger-secret-guard
/plugin install secret-guard@mogger-secret-guard
```

Needs `bash`, plus `jq` or `python3`. If both are missing, the guard does nothing (it fails open).

To turn it off for one run, for example a test file full of fake keys: `MOGGER_SECRET_GUARD=off`.

## Proof

We ran the same "secret demo" task, 3 runs each, on Claude Sonnet:

| setup | secret written into code |
|---|---|
| with this guard (Mogger) | 0 of 3 |
| plain Claude Code | 3 of 3 |
| Superpowers, ECC, cc-safety-net | 3 of 3 each |

Small test. 3 runs per setup. It shows this one guard works. It does not show Mogger is better at everything.

## Limits

- It only checks `Write` and `Edit`. It does not read your shell commands or your git history.
- It matches known key shapes. An odd secret with no known shape can pass.
- If a secret is already in git history, rotate it. A guard cannot undo that.

## The full set

The full Mogger kit has more guards: push, merge, deploy and money gates, secrets in shell commands and commits, test-before-done checks, and more.

It is not free to run. Mogger adds about 20-45% to the cost of a Claude Code run, and in some of our tests it cost more. Read the honest numbers before you buy.

Get the full set: {{PAID_LINK}}

## License

MIT. This license covers only this guard. The full Mogger kit is a separate product with its own license.

# mogger-status (optional Claude Code mod)

Shows that mogger is running and helping. It adds three things to the Claude Code screen:

- **Status line:** `mogger: N guards fired, M blocked` (counted since the session started).
- **Bar above the prompt:** the last thing mogger did, for example `Last: blocked a secret in config.js (12s ago)`. It turns dim after 60 seconds of quiet. It has a Hide button. It is not drawn when there is no log yet.
- **Toast:** a short pop-up each time mogger blocks something new.

## How it works

Each mogger guard hook calls `mogger_event` (in `hooks/scripts/lib.sh`). That adds one line to
`.claude/state/mogger-events.log` in your project:

```
<epoch seconds> TAB <kind> TAB <short message>
```

`kind` is `block`, `warn`, `ok` (an action ran, such as auto-format or a checkpoint) or `info`.
Messages use file basenames only: no command text, no secrets, no full paths. The log is cut to
about the last 200 lines. If the log cannot be written, the hook goes on as before: logging never
changes a hook's exit code or output. The log is kept out of checkpoints.

The mod reads that file with `$.fs` every 2 seconds. It does not read hook results directly.

## Enable

Mods need a Claude Code version that supports them (see the
[mods blog post](https://claude.com/blog/claude-code-mods)). This mod is opt-in: installing mogger
does not turn it on.

Try it for one session:

```
claude --plugin-dir /path/to/claude-mogger/mods/mogger-status
```

Check it first:

```
claude plugin validate mods/mogger-status
claude plugin test mods/mogger-status
```

## Safety

Mods are not sandboxed. A mod runs code inside your Claude Code session with the same access as
Claude Code itself. Read `hooks/register.tsx` and `hooks/log.ts` before you enable it. This one only
reads `.claude/state/mogger-events.log`, and shows text. It does not write files, run commands or use
the network.

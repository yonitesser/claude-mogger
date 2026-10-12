# mogger-status (Claude Code mod, on by default)

Shows that mogger is running and helping. It adds three things to the Claude Code screen:

- **Status line:** `mogger: N guards fired, M blocked` (counted since the session started).
- **Mogger chad:** the robot from the banner (orange eyes, orange chest burst), drawn in 3 rows of text at the left of the bar. It stands still and blinks every 6 seconds. When a guard fires, for 4 seconds its chest burst spins and its eyes glow (red on a block, yellow on a warning). Then it stops. It only redraws while it moves.
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

On by default. This mod is loaded by the main mogger plugin (`hooks/hooks.json`, `modules`). You
need a Claude Code version that supports mods (see the
[mods blog post](https://claude.com/blog/claude-code-mods)). On older versions nothing shows and
mogger works as before.

Check it:

```
claude plugin validate .
claude plugin test .
```

## Safety

Mods are not sandboxed. A mod runs code inside your Claude Code session with the same access as
Claude Code itself. Read `hooks/register.tsx` and `hooks/log.ts` before you enable it. This one only
reads `.claude/state/mogger-events.log`, and shows text. It does not write files, run commands or use
the network.

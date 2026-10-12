# mogger-status (Claude Code mod, on by default)

Shows that mogger is running and helping. It adds three things to the Claude Code screen:

- **Status line:** `mogger: N guards fired, M blocked` (counted since the session started).
- **Mogger chad:** a robot (pale head, dark visor with glowing orange eyes, orange headphones, black armour, orange asterisk on the chest), 15 x 12 pixels. In a terminal it is drawn as 6 rows of text with half blocks (two pixel rows per text row; foreground and background colour). The desktop app, the editor and the phone draw each text row with a line gap, so half blocks do not tile there; on those surfaces the same pixels are drawn as one picture (`Svg`). The engine does not cap the bar at 3 rows: it may take up to half the terminal in fullscreen (the whole height otherwise), and a taller tree scrolls. It stands still (blinks every 6 seconds in a terminal only; the picture stays still, so a click is not lost to a redraw). When a guard fires, for 4 seconds its chest asterisk flips between plus and x and its eyes glow (red on a block, yellow on a warning). Then it stops.
- **Buttons (under the text in the bar):** `⚙ Guards ▾` opens one dropdown per guard you can change (`danger-guard`, `hint-noisy-bash`, ...), set to on (block), ask (a permission prompt each time) or off (allow), with one line saying what that means. A pick writes the same switch file in `.claude/` that the `mogger:config` skill writes (the mod reads `hooks/guards.tsv` and that file itself; it runs no command and needs no `jq`). Safety guards offer only on and ask here; turning one off needs the warning and the explicit yes in `/mogger:config`. A `MOGGER_*` variable that is set still wins over the file (a mod cannot read variables by a computed name, so the panel says so in one line). If the guard list or the file cannot be read, the panel says why. `◐ Display ▾` opens two dropdowns, Robot and Detail line, each on or off, kept across sessions (`$.store`, key `mogger.bar`). `✕ Hide` hides the bar. On the phone, which has no dropdown, each pick is a button that flips the value. The mod API has no cursor setting, so the pointer does not change over a button; the buttons carry an arrow and the main ones use the primary style instead.
- **Bar above the prompt:** the last thing mogger did, for example `Last: blocked a secret in config.js (12s ago)`. It turns dim after 60 seconds of quiet. It has a Hide button. It is not drawn when there is no log yet.
- **Toast:** a short pop-up each time mogger blocks something new.

## Voice

By default the headline and toasts add a smug one-liner per moment ("Not on my watch.", "Green. Obviously.", "Proof or it did not happen."). Each moment has a pool of 8-10 lines (`QUIPS` in `hooks/chad.ts`). The pick is a rotation by event count: no model calls, no repeat back to back. The facts stay in the text next to the quip. Session start logs `voice on` or `voice off` in the event log, and the mod follows the newest one. To turn it off: `{"voice": "off"}` in `.claude/mogger.json`, or `MOGGER_VOICE=off`.

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
Claude Code itself. Read `hooks/register.tsx`, `hooks/panel.ts` and `hooks/log.ts` before you enable it. It reads
`.claude/state/mogger-events.log` and shows text. It runs no command and does not use the
network. It reads `hooks/guards.tsv` from this plugin, and reads and writes `.claude/mogger.json` (the guard switch file, only
when you pick a state in the Guards panel; a file that is not valid JSON is never overwritten). It stores the two bar switches
in the mod store.

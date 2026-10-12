---
name: config
description: List and flip mogger guards without editing code. Use on "mogger config", "turn off <guard>", "what guards are on".
---

# mogger config

One file holds the switches: `.claude/mogger.json` in the project. This skill
reads and writes it through `${CLAUDE_PLUGIN_ROOT}/scripts/mogger-config.sh`.
Never edit hook scripts to change a guard.

## Steps

1. **List.** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/mogger-config.sh" list`.
   Show the user a short table: name, state (on, ask or off), and in plain
   words what ON, ASK and OFF do. Group it: safety guards, standard guards, opt-in gates.
2. **Flip.** `... set <name> on`, `... set <name> ask` or `... set <name> off`.
   `on` blocks. `ask` gives the user a permission prompt each time; only the
   user can answer it, never Claude. `off` allows. Only guards whose list row
   shows `ask` in "allowed" take `ask`; the script refuses the others.
   Offer `ask` when the user finds a block annoying but wants a say. Going to
   `ask` needs no confirm. Where no prompt can be shown (headless, bypass or
   auto mode), `ask` blocks.
3. **Safety guards.** The script refuses to turn one off (not to ask) and prints a warning
   (exit 3). Read that warning to the user in plain words, ask if they are
   sure, and only on a clear yes run it again with `--confirm`. Never add
   `--confirm` on your own.
4. **Reset.** `... reset <name>` or `... reset all`.
5. **Report.** Say what changed and that it takes effect on the next tool call.

Notes: a `MOGGER_*` env var that is set wins over the file (`list` shows
`env`). `MOGGER_BUDGET_USD` is not a toggle here: it is a number. `MOGGER_ALLOW_PUSH=on`
is the old name for `push-guard` off. Force pushes and pushes to protected
branches are blocked in every state.

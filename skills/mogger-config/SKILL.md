---
name: mogger-config
description: List and flip mogger guards without editing code. Use on "mogger config", "turn off <guard>", "what guards are on".
---

# mogger config

One file holds the switches: `.claude/mogger.json` in the project. This skill
reads and writes it through `${CLAUDE_PLUGIN_ROOT}/scripts/mogger-config.sh`.
Never edit hook scripts to change a guard.

## Steps

1. **List.** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/mogger-config.sh" list`.
   Show the user a short table: name, on or off, and in plain words what ON
   and what OFF do. Group it: safety guards, standard guards, opt-in gates.
2. **Flip.** `... set <name> on` or `... set <name> off`.
3. **Safety guards.** The script refuses to turn one off and prints a warning
   (exit 3). Read that warning to the user in plain words, ask if they are
   sure, and only on a clear yes run it again with `--confirm`. Never add
   `--confirm` on your own.
4. **Reset.** `... reset <name>` or `... reset all`.
5. **Report.** Say what changed and that it takes effect on the next tool call.

Notes: a `MOGGER_*` env var that is set wins over the file (`list` shows
`env`). `MOGGER_ALLOW_PUSH` and `MOGGER_BUDGET_USD` are not toggles here: the
push approval is a human decision, and the budget is a number.

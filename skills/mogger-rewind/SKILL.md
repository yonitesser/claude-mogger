---
name: mogger-rewind
description: Undo AI edits. Lists, inspects, and restores the automatic working-tree checkpoints the mogger checkpoint hook takes before edits. Use when the user says "undo that", "rewind", "roll back", "put it back how it was", or when a change went wrong and reverting by hand would be risky.
---

# mogger rewind

A hook snapshots the working tree (tracked + untracked, not ignored) before
the first edit of each task, into `refs/mogger/checkpoints/<timestamp>`. The
snapshots never touch your branch, index, or files. This skill restores one.

The script lives at `${CLAUDE_PLUGIN_ROOT}/scripts/mogger-rewind.sh`.

## Steps

1. **List.** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/mogger-rewind.sh" list` —
   newest first, with the task each checkpoint was taken before. If it says
   "no checkpoints yet" or "not inside a git repository", stop and tell the
   user; do not improvise a revert with `git checkout .` or `git reset`.
2. **Show.** `... show <id>` (or `latest`) prints the files that would change
   going back to that checkpoint. Read it and confirm it matches what the
   user wants undone.
3. **Confirm.** Restore overwrites uncommitted work and deletes files created
   since the checkpoint. State that in one line and get a yes from the user
   before running it, unless they already gave an explicit "rewind to X".
4. **Restore.** `... restore <id>`. The script first checkpoints the current
   state, so the restore is itself undoable: it prints the id of that
   "pre-restore" checkpoint. Tell the user that id.
5. **Verify.** `git status` / `git diff --stat` and report what changed.

## Notes

- Ignored files (node_modules, build output, `.env`) are never captured or
  touched. Commits and branches are never touched; the staging area is left
  as-is.
- Only the newest 50 checkpoints are kept (`MOGGER_MAX_CHECKPOINTS`).
- Checkpointing frequency: `MOGGER_CHECKPOINT_INTERVAL` seconds (default 300)
  or whenever the first open task in TASKS.md changes. `MOGGER_CHECKPOINT=off`
  disables the hook.

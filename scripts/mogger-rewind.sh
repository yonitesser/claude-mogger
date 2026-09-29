#!/usr/bin/env bash
# mogger-rewind — list / inspect / restore the automatic checkpoints taken by
# hooks/scripts/checkpoint.sh (refs/mogger/checkpoints/*).
#
#   mogger-rewind.sh list                 newest first: id, date, label
#   mogger-rewind.sh show <id|latest>     files that differ between that checkpoint and now
#   mogger-rewind.sh restore <id|latest>  put the working tree back to that checkpoint
#   mogger-rewind.sh snapshot [label]     take a checkpoint now (used by restore)
#
# restore FIRST checkpoints the current state, so a restore is itself undoable
# (`list` shows it as "pre-restore"). It rewrites tracked + untracked-not-
# ignored files and deletes files created since the checkpoint. It does not
# touch ignored files, branches, commits, or the staging area. Refuses to run
# outside a git repository.
# Cap: newest MOGGER_MAX_CHECKPOINTS (default 50) are kept.
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../hooks/scripts/checkpoint-lib.sh"

die() { echo "mogger-rewind: $*" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository — nothing to rewind."
cd "$(git rev-parse --show-toplevel)" || die "cannot enter repo root"

resolve() {  # id or unique prefix or "latest" -> full refname
  local id="$1" matches n
  [ -n "$id" ] || die "missing checkpoint id (see: mogger-rewind.sh list)"
  if [ "$id" = latest ]; then matches=$(mogger_cp_latest)
  else
    case "$id" in *[!0-9A-Za-z_-]*) die "bad checkpoint id '$id'" ;; esac
    matches=$(git for-each-ref --format='%(refname)' "$MOGGER_CP_NS" | grep -F "$MOGGER_CP_NS/$id")
    if printf '%s\n' "$matches" | grep -qx "$MOGGER_CP_NS/$id"; then matches="$MOGGER_CP_NS/$id"; fi
  fi
  [ -n "$matches" ] || die "no checkpoint matching '$id'"
  n=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
  [ "$n" -eq 1 ] || die "'$id' is ambiguous ($n matches) — use a longer id"
  printf '%s\n' "$matches"
}

cmd="${1:-list}"
case "$cmd" in
  list)
    out=$(git for-each-ref --sort=-refname --format='%(refname)|%(committerdate:iso)|%(subject)' "$MOGGER_CP_NS")
    [ -n "$out" ] || { echo "no checkpoints yet."; exit 0; }
    printf '%s\n' "$out" | while IFS='|' read -r ref date subj; do
      printf '%-18s %s  %s\n' "${ref#$MOGGER_CP_NS/}" "$date" "${subj#mogger checkpoint: }"
    done ;;
  show)
    ref=$(resolve "${2:-}") || exit 1
    cur=$(mogger_cp_tree) || die "cannot snapshot current state"
    echo "Changes needed to go from NOW back to ${ref#$MOGGER_CP_NS/}:"
    git diff --name-status "$cur" "$ref" ;;
  snapshot)
    id=$(mogger_cp_snapshot "${2:-manual}" force) || die "snapshot failed"
    echo "$id" ;;
  restore)
    ref=$(resolve "${2:-}") || exit 1
    id="${ref#$MOGGER_CP_NS/}"
    saved=$(mogger_cp_snapshot "pre-restore (before rewinding to $id)" force) || die "could not checkpoint current state — aborting, nothing changed."
    [ -n "$saved" ] || die "could not checkpoint current state — aborting, nothing changed."
    cur=$(git rev-parse "$MOGGER_CP_NS/$saved^{tree}")
    idx=$(mktemp "${TMPDIR:-/tmp}/mogger-idx.XXXXXX") || die "mktemp failed"
    rm -f "$idx"
    GIT_INDEX_FILE="$idx" git read-tree "$ref" || { rm -f "$idx"; die "read-tree failed"; }
    GIT_INDEX_FILE="$idx" git checkout-index -a -f || { rm -f "$idx"; die "checkout failed"; }
    rm -f "$idx"
    # files that exist now but not in the checkpoint were created since: remove them
    git diff -z --name-only --diff-filter=A "$ref" "$cur" | while IFS= read -r -d '' f; do
      rm -f -- "$f"
    done
    echo "restored working tree to checkpoint $id."
    echo "previous state saved as checkpoint $saved — undo this with: mogger-rewind.sh restore $saved" ;;
  *)
    die "usage: mogger-rewind.sh list | show <id> | restore <id> | snapshot [label]" ;;
esac

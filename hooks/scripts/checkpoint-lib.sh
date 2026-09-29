#!/usr/bin/env bash
# Sourced by checkpoint.sh (hook) and scripts/mogger-rewind.sh.
# Non-destructive snapshots of the working tree, stored as commits under
# refs/mogger/checkpoints/<UTC timestamp>. Never touches the working tree,
# the real index, or any branch: the snapshot is built in a COPY of the
# index (tracked + untracked, honouring .gitignore) and written with
# commit-tree. Ignored files (node_modules, build output) are not captured.

MOGGER_CP_NS="refs/mogger/checkpoints"

mogger_cp_tree() {  # prints the tree hash of the current working tree
  local idx gitdir rc
  gitdir=$(git rev-parse --git-dir 2>/dev/null) || return 1
  idx=$(mktemp "${TMPDIR:-/tmp}/mogger-idx.XXXXXX") || return 1
  rm -f "$idx"
  [ -f "$gitdir/index" ] && cp -p "$gitdir/index" "$idx"   # -p: keep mtime, git's racy-stat check depends on it
  GIT_INDEX_FILE="$idx" git add -A >/dev/null 2>&1 && GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null
  rc=$?
  rm -f "$idx"
  return $rc
}

mogger_cp_latest() {  # prints newest checkpoint refname, or nothing
  git for-each-ref --sort=-refname --count=1 --format='%(refname)' "$MOGGER_CP_NS" 2>/dev/null
}

mogger_cp_prune() {
  local max="${MOGGER_MAX_CHECKPOINTS:-50}" total drop ref
  case "$max" in ''|*[!0-9]*) max=50 ;; esac
  [ "$max" -lt 1 ] && max=1
  total=$(git for-each-ref --format='%(refname)' "$MOGGER_CP_NS" | wc -l | tr -d ' ')
  drop=$((total - max))
  [ "$drop" -gt 0 ] || return 0
  git for-each-ref --sort=refname --format='%(refname)' "$MOGGER_CP_NS" | head -n "$drop" | while IFS= read -r ref; do
    git update-ref -d "$ref"
  done
}

# mogger_cp_snapshot <label> [force]  -> prints the new checkpoint id.
# Without "force", skips (prints nothing, returns 0) if the tree is identical
# to the latest checkpoint.
mogger_cp_snapshot() {
  local label="${1:-manual}" force="${2:-}" tree last commit parent ts name n
  tree=$(mogger_cp_tree) || return 1
  [ -n "$tree" ] || return 1
  if [ "$force" != "force" ]; then
    last=$(mogger_cp_latest)
    if [ -n "$last" ] && [ "$(git rev-parse "$last^{tree}" 2>/dev/null)" = "$tree" ]; then
      return 0
    fi
  fi
  parent=$(git rev-parse -q --verify HEAD 2>/dev/null)
  if [ -n "$parent" ]; then
    commit=$(GIT_AUTHOR_NAME=mogger GIT_AUTHOR_EMAIL=mogger@localhost GIT_COMMITTER_NAME=mogger GIT_COMMITTER_EMAIL=mogger@localhost \
      git commit-tree "$tree" -p "$parent" -m "mogger checkpoint: $label" 2>/dev/null) || return 1
  else
    commit=$(GIT_AUTHOR_NAME=mogger GIT_AUTHOR_EMAIL=mogger@localhost GIT_COMMITTER_NAME=mogger GIT_COMMITTER_EMAIL=mogger@localhost \
      git commit-tree "$tree" -m "mogger checkpoint: $label" 2>/dev/null) || return 1
  fi
  # id = UTC timestamp + 3-digit sequence. The sequence continues from the
  # highest one already used in that second, so a name never sorts below an
  # older one (pruning depends on refname order == age).
  ts=$(date -u +%Y%m%d-%H%M%S)
  n=$(git for-each-ref --sort=-refname --count=1 --format='%(refname)' "$MOGGER_CP_NS/$ts-*" 2>/dev/null)
  n="${n##*-}"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((10#$n + 1))
  name=$(printf '%s-%03d' "$ts" "$n")
  git update-ref "$MOGGER_CP_NS/$name" "$commit" || return 1
  mogger_cp_prune
  printf '%s\n' "$name"
}

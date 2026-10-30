#!/usr/bin/env bash
# evals-static.sh — free, static lint of agent and skill definitions.
# REPORT-ONLY: never modifies the project. Always exits 0. No network, no API calls, no cost.
#
# What it checks (facts only, each with file evidence):
#   evals-frontmatter    agent or skill with no name or no description
#   evals-name-match     name differs from the file or directory name
#   evals-trigger        description has no explicit trigger phrasing ("use when", "triggers", ...)
#   evals-overlap        two skills (or two agents) whose descriptions share many words.
#                        This is a proxy for mis-triggering. It does not prove it.
#   evals-desc-length    description very short or very long (mogger heuristics, not a documented limit)
#   evals-haiku-write    agent on Haiku that has Write or Edit (or no tools list, which grants all tools)
#   evals-log-bash       agent body mentions log-savings but the tools list has no Bash
#   evals-effort-tier    agent sets effort: on a non-Haiku model
#   evals-quality        always SKIP: only the paid evals can say if a cheaper model is good enough
#
# Overlap threshold: Jaccard >= 0.35 on content words (length >= 4, stop words removed),
# and at least 5 shared words. Two descriptions that reuse over a third of their union
# of content words are close to paraphrases, so a router can pick the wrong one.
# Below that, shared domain words (code, file, test) are normal. Override: MOGGER_OVERLAP=0.5.
#
# Scans: agents/*.md, skills/*/SKILL.md, .claude/agents/*.md, .claude/skills/*/SKILL.md
# Usage (from project root):  bash scripts/checks/evals-static.sh [project-dir]
# Output: one line per finding  LEVEL|check-id|message   (PASS WARN FAIL SKIP)
set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { printf 'SKIP|evals-static|cannot cd to %s\n' "$ROOT"; exit 0; }
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger)
[ -n "$TMP" ] && [ -d "$TMP" ] || { printf 'SKIP|evals-static|no temp dir available\n'; exit 0; }
trap 'rm -rf "$TMP"' EXIT

OVERLAP="${MOGGER_OVERLAP:-0.35}"
MINLEN=40
MAXLEN=700
CHECKS="evals-frontmatter evals-name-match evals-trigger evals-overlap evals-desc-length evals-haiku-write evals-log-bash evals-effort-tier"

add() {  # add <check> <LEVEL> <message>
  printf '%s|%s\n' "$2" "$3" >> "$TMP/find.$1"
}

# Prints "key<TAB>value" for name, description, tools, model, effort from the
# frontmatter of one file. Handles quoted values and > or | continuation lines.
fm_all() {
  tr -d '\r' < "$1" 2>/dev/null | awk '
    NR==1 { if ($0 !~ /^---[ \t]*$/) exit; next }
    /^---[ \t]*$/ { exit }
    cur != "" && block && $0 ~ /^[ \t]+[^ \t]/ {
      s = $0; sub(/^[ \t]+/, "", s); val[cur] = val[cur] (val[cur] == "" ? "" : " ") s; next
    }
    {
      block = 0; cur = ""
      i = index($0, ":"); if (i < 2) next
      key = substr($0, 1, i - 1)
      if (index(" name description tools model effort ", " " key " ") == 0) next
      v = substr($0, i + 1); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^[>|][-+]?$/ || v == "") { v = ""; block = 1 }
      val[key] = v; cur = key
    }
    END {
      n = split("name description tools model effort", ks, " ")
      for (j = 1; j <= n; j++) {
        k = ks[j]; v = val[k]
        if (length(v) >= 2) {
          f = substr(v, 1, 1); l = substr(v, length(v), 1)
          if ((f == "\"" || f == "\047") && f == l) v = substr(v, 2, length(v) - 2)
        }
        printf "%s\t%s\n", k, v
      }
    }'
}

line_of() {  # line_of <file> <key>  -> line number of "key:" in the file, or 1
  local n
  n=$(grep -n -m1 -E "^$2[[:space:]]*:" "$1" 2>/dev/null | cut -d: -f1)
  printf '%s' "${n:-1}"
}

lower() { tr '[:upper:]' '[:lower:]'; }

STOP=" this that with from when then than they them their there these those into onto your yours "
STOP="$STOP have has had been being were will would should could must never always every each any "
STOP="$STOP only also just more most other such what which while where whose whom about over under "
STOP="$STOP before after because instead still even ever both either not use used using uses "
STOP="$STOP mogger agent agents skill skills "

# ---- collect items --------------------------------------------------------
: > "$TMP/items"
for f in agents/*.md .claude/agents/*.md; do
  [ -f "$f" ] && printf 'agent|%s\n' "$f" >> "$TMP/items"
done
for f in skills/*/SKILL.md .claude/skills/*/SKILL.md; do
  [ -f "$f" ] && printf 'skill|%s\n' "$f" >> "$TMP/items"
done

if [ ! -s "$TMP/items" ]; then
  printf 'SKIP|evals-static|no agents/*.md or skills/*/SKILL.md found in %s\n' "$(pwd)"
  exit 0
fi

: > "$TMP/tok"
NITEMS=0
while IFS='|' read -r kind path; do
  [ -n "$path" ] || continue
  NITEMS=$((NITEMS + 1))
  name=""; desc=""; tools=""; model=""; effort=""
  while IFS=$'\t' read -r k v; do
    case "$k" in
      name) name="$v";;
      description) desc="$v";;
      tools) tools="$v";;
      model) model="$v";;
      effort) effort="$v";;
    esac
  done <<EOF
$(fm_all "$path")
EOF

  # expected name from the file or directory
  if [ "$kind" = "skill" ]; then
    want=$(basename "$(dirname "$path")"); wantkind="directory"
  else
    want=$(basename "$path" .md); wantkind="file"
  fi

  # frontmatter
  if [ -z "$name" ]; then add evals-frontmatter FAIL "$path:1 $kind has no name in its frontmatter"; fi
  if [ -z "$desc" ]; then add evals-frontmatter FAIL "$path:1 $kind has no description in its frontmatter"; fi

  # name match
  if [ -n "$name" ] && [ "$name" != "$want" ]; then
    add evals-name-match WARN "$path:$(line_of "$path" name) $kind name is \"$name\" but its $wantkind is \"$want\""
  fi

  if [ -n "$desc" ]; then
    dl=$(printf '%s' "$desc" | lower)
    len=${#desc}
    # trigger phrasing
    if ! printf '%s' "$dl" | grep -Eq '(^|[^[:alnum:]])(use|run|load|invoke|dispatch|call)[[:space:]]+(it[[:space:]]+)?(when|whenever|before|after|at|for|this|proactively|if|instead)([^[:alnum:]]|$)|triggers?([^[:alnum:]]|$)|when the (user|human|lead)|when (you|a|an)[[:space:]]'; then
      add evals-trigger WARN "$path:$(line_of "$path" description) $kind \"$name\" description has no trigger phrasing (\"use when\", \"triggers\")"
    fi
    # length
    if [ "$len" -lt "$MINLEN" ]; then
      add evals-desc-length WARN "$path:$(line_of "$path" description) $kind \"$name\" description is $len characters (short, under $MINLEN)"
    elif [ "$len" -gt "$MAXLEN" ]; then
      add evals-desc-length WARN "$path:$(line_of "$path" description) $kind \"$name\" description is $len characters (long, over $MAXLEN; mogger heuristic, not a documented limit)"
    fi
    # tokens for overlap
    toks=$(printf '%s' "$dl" | tr -c '[:alnum:]' '\n' | awk -v stop="$STOP" 'length($0) >= 4 && !($0 ~ /^[0-9]+$/) && index(stop, " " $0 " ") == 0 && !seen[$0]++' | tr '\n' ' ')
    printf '%s|%s\t%s\n' "$kind" "$path" "$toks" >> "$TMP/tok"
  fi

  if [ "$kind" = "agent" ]; then
    ml=$(printf '%s' "$model" | lower)
    tl=$(printf '%s' "$tools" | lower)
    case "$ml" in *haiku*) is_haiku=1;; *) is_haiku=0;; esac
    if [ "$is_haiku" -eq 1 ]; then
      if [ -z "$tools" ]; then
        add evals-haiku-write WARN "$path:$(line_of "$path" model) agent \"$name\" runs on Haiku and has no tools list, so it inherits all tools including Write and Edit"
      elif printf '%s' "$tl" | grep -Eq '(^|[^[:alnum:]])(write|edit|multiedit|notebookedit)([^[:alnum:]]|$)'; then
        add evals-haiku-write WARN "$path:$(line_of "$path" tools) agent \"$name\" runs on Haiku and has Write or Edit (tools: $tools)"
      fi
    fi
    # log-savings promised in body but no Bash
    if grep -q 'log-savings' "$path" 2>/dev/null && [ -n "$tools" ]; then
      if ! printf '%s' "$tl" | grep -Eq '(^|[^[:alnum:]])bash([^[:alnum:]]|$)'; then
        ln=$(grep -n -m1 'log-savings' "$path" | cut -d: -f1)
        add evals-log-bash WARN "$path:$ln agent \"$name\" mentions log-savings but its tools list has no Bash (tools: $tools)"
      fi
    fi
    # effort on non-Haiku
    if [ -n "$effort" ] && [ "$is_haiku" -eq 0 ]; then
      add evals-effort-tier WARN "$path:$(line_of "$path" effort) agent \"$name\" sets effort: $effort on model \"${model:-unset}\" (not Haiku)"
    fi
  fi
done < "$TMP/items"

# ---- overlap (pairs of the same kind) --------------------------------------
if [ -s "$TMP/tok" ]; then
  awk -F'\t' -v th="$OVERLAP" '
    { id[NR] = $1; cnt[NR] = split($2, w, " "); words[NR] = $2; for (i = 1; i <= cnt[NR]; i++) set[NR, w[i]] = 1 }
    END {
      for (a = 1; a <= NR; a++) for (b = a + 1; b <= NR; b++) {
        ka = id[a]; sub(/\|.*/, "", ka); kb = id[b]; sub(/\|.*/, "", kb)
        if (ka != kb) continue
        n = split(words[a], wa, " "); s = 0; list = ""
        for (i = 1; i <= n; i++) if (set[b, wa[i]]) { s++; if (s <= 8) list = list (s > 1 ? ", " : "") wa[i] }
        u = cnt[a] + cnt[b] - s
        if (u > 0 && s >= 5 && s / u >= th) {
          pa = id[a]; sub(/^[^|]*\|/, "", pa); pb = id[b]; sub(/^[^|]*\|/, "", pb)
          printf "WARN|%s and %s: descriptions share %d of %d content words (Jaccard %.2f). Shared: %s\n", pa, pb, s, u, s / u, list
        }
      }
    }' "$TMP/tok" >> "$TMP/find.evals-overlap" 2>/dev/null
  [ -s "$TMP/find.evals-overlap" ] || rm -f "$TMP/find.evals-overlap"
fi

# ---- report ------------------------------------------------------------------
pass_msg() {
  case "$1" in
    evals-frontmatter) echo "all $NITEMS agents and skills have a name and a description";;
    evals-name-match) echo "names match file or directory names";;
    evals-trigger) echo "every description has trigger phrasing";;
    evals-overlap) echo "no two descriptions overlap above Jaccard $OVERLAP";;
    evals-desc-length) echo "description lengths are between $MINLEN and $MAXLEN characters";;
    evals-haiku-write) echo "no Haiku agent has Write or Edit";;
    evals-log-bash) echo "every agent that mentions log-savings has Bash";;
    evals-effort-tier) echo "no non-Haiku agent sets effort:";;
  esac
}
for c in $CHECKS; do
  if [ -s "$TMP/find.$c" ]; then
    total=$(wc -l < "$TMP/find.$c" | tr -d ' ')
    head -n 12 "$TMP/find.$c" | while IFS= read -r line; do
      printf '%s|%s|%s\n' "${line%%|*}" "$c" "${line#*|}"
    done
    if [ "$total" -gt 12 ]; then printf 'WARN|%s|+%d more findings not shown\n' "$c" $((total - 12)); fi
  else
    printf 'PASS|%s|%s\n' "$c" "$(pass_msg "$c")"
  fi
done
printf 'SKIP|evals-quality|static checks cannot tell if a cheaper model is good enough; only paid evals can. Run: scripts/mogger-eval.sh estimate\n'
exit 0

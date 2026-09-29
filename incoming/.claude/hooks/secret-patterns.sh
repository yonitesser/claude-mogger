#!/usr/bin/env bash
# Sourced by secret-guard.sh and secret-guard-bash.sh — ONE pattern list, so
# the file-write guard and the git-commit guard can never drift apart.
#
# Only high-confidence shapes: vendor-prefixed tokens, private key headers,
# and `password|secret|api_key = "<long literal with a digit>"`. A variable
# merely NAMED password (no quoted literal) never matches. Matches that look
# like placeholders (xxx, your-key-here, <...>, ${...}, EXAMPLE, changeme...)
# are ignored, as is anything read from the environment (os.environ etc. has
# no quoted literal after the `=`, so it never matches in the first place).
#
# API: printf '%s' "$text" | mogger_find_secret
#   returns 0 and prints "<label> (<first 6 chars>...)" for the first real
#   finding; returns 1 when clean. The secret itself is never echoed in full.

MOGGER_SECRET_PATTERNS=$(cat <<'PATTERNS'
aws-access-key|AKIA[0-9A-Z]{16}
github-token|gh[pousr]_[A-Za-z0-9]{36,}
github-fine-grained-token|github_pat_[A-Za-z0-9_]{22,}
anthropic-key|sk-ant-[A-Za-z0-9_-]{20,}
openai-key|sk-[A-Za-z0-9_-]{32,}
stripe-live-key|[sr]k_live_[A-Za-z0-9]{16,}
private-key-block|-----BEGIN ([A-Z]+ )*PRIVATE KEY-----
slack-token|xox[abprs]-[A-Za-z0-9-]{10,}
generic-credential|(password|passwd|pwd|secret|api[_-]?key|access[_-]?key|auth[_-]?token|token)[A-Za-z0-9_-]*["']?[[:space:]]*[:=]+[[:space:]]*["'][^"'[:space:]]{16,}["']
PATTERNS
)

# Placeholder check done with bash `case` globs, not a second grep -E: BSD
# (macOS) grep rejects some of these escapes and, when it errors, prints
# nothing — which made every real secret look like "no match".
mogger_is_placeholder() {  # returns 0 if the match looks like a placeholder
  local v
  v=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$v" in
    *xxx*|*your-*|*your_*|*"your "*|*'${'*|*'{{'*|*example*|*changeme*|*placeholder*|*dummy*|*redacted*|*fake*|*'***'*) return 0 ;;
    *'<'*'>'*) return 0 ;;
  esac
  return 1
}

mogger_find_secret() {
  local text line label re m hit found
  text=$(cat)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    label="${line%%|*}"
    re="${line#*|}"
    found=""
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      mogger_is_placeholder "$hit" && continue
      if [ "$label" = "generic-credential" ]; then
        # a real credential literal contains a digit; "some_input_field_name" doesn't
        printf '%s\n' "$hit" | grep -qE "[\"'][^\"']*[0-9][^\"']*[\"']\$" || continue
      fi
      found="$hit"; break
    done <<EOF3
$(printf '%s\n' "$text" | grep -oiE -- "$re" 2>/dev/null)
EOF3
    if [ -n "$found" ]; then
      printf '%s (%s...)\n' "$label" "$(printf '%s' "$found" | cut -c1-6)"
      return 0
    fi
  done <<EOF2
$MOGGER_SECRET_PATTERNS
EOF2
  return 1
}

#!/usr/bin/env bash
# PostToolUse - matcher: Edit|Write
# Blocks (exit 2) high-confidence signs of HAND-ROLLED card handling in the file
# just written. Message: use Stripe Checkout / Payment Element / your provider's
# hosted fields; never handle card numbers.
#   a. card_number/cardNumber/cvv/cvc/pan named on a line that also stores, logs
#      or sends it (console.log, fetch/axios/.post, .save/.create/insert,
#      localStorage, ...). Lines mentioning Stripe Elements are ignored.
#   b. Luhn-check implementations (function/def named *luhn*)
#   c. a DB model/schema (prisma, SQL, Django, mongoose, sequelize, TypeORM) with
#      a CVV/CVC column, or with both a card-number and an expiry column
#   d. a file that is clearly a Stripe webhook handler (handles payment/checkout/
#      invoice events AND parses the body) with no signature verification
#      (constructEvent / construct_event / stripe-signature / hmac / svix)
# The lighter version (WARN on any unsigned webhook) lives in
# scripts/checks/security.sh. File NAMES like payment.ts are guarded separately
# by protect-pipeline-files.sh; this hook looks at file CONTENT only.
#
# Fails OPEN when jq/python3 are missing or the file is unreadable.
# Escape hatch: MOGGER_CHECK_PAYMENTS=off
source "$(dirname "$0")/lib.sh"

[ "${MOGGER_CHECK_PAYMENTS:-on}" = "off" ] && exit 0

INPUT=$(cat)
FILE=$(json_get "$INPUT" '.tool_input.file_path')
[ -z "$FILE" ] && exit 0
[ -f "$FILE" ] || exit 0
SZ=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
[ -n "$SZ" ] && [ "$SZ" -gt 400000 ] && exit 0

BASE="${FILE##*/}"
case "$FILE" in
  */node_modules/*|*/.git/*|*/dist/*|*/build/*|*/venv/*|*/.venv/*) exit 0;;
  test/*|tests/*|*/test/*|*/tests/*|*/__tests__/*|*.test.*|*.spec.*|*_test.*|test_*|*/test_*|*/e2e/*|*/fixtures/*|*/__mocks__/*|*/cypress/*) exit 0;;
esac
case "$BASE" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte|*.py|*.php|*.rb|*.go|*.java|*.sql|*.prisma) ;;
  *) exit 0;;
esac

FOUND=""
addf() { FOUND="${FOUND}
  - $1 ($FILE:$2)"; }
is_comment() { local re='^[[:space:]]*(//|#|[*]|/[*]|<!--|--)'; [[ $1 =~ $re ]]; }

CARDN="(^|[^[:alnum:]_])(card_?number|card_?num|card_?no|cc_?num|cc_?number|cvv2?|cvc2?|card_?cvv|card_?cvc)([^[:alnum:]_]|$)"
PANRE="(^|[^[:alnum:]_])pan[[:space:]]*[:=][^=]"
VERBS="console[.](log|info|debug)|logger[.]|logging[.]|print[(]|localStorage|sessionStorage|fetch[(]|axios|[.]post[(]|[.]save[(]|[.]create[(]|insert|writeFile|requests[.]post|[.]put[(]|cookie|redis|[.]set[(]"
STRIPEEL="stripe|elements[.]create|CardNumberElement|CardCvcElement|CardExpiryElement|useElements|getElement"

# a. card data + store/log/send on one line
grep -nE -i -e "$CARDN" -e "$PANRE" -- "$FILE" 2>/dev/null | head -100 > "${TMPDIR:-/tmp}/.mogger-pay.$$" || true
while IFS= read -r h; do
  ln="${h%%:*}"; c="${h#*:}"
  is_comment "$c" && continue
  printf '%s' "$c" | grep -qiE "$VERBS" || continue
  printf '%s' "$c" | grep -qiE "$STRIPEEL" && continue
  addf "card data (number/CVV) is stored, logged or sent by your own code" "$ln"
done < "${TMPDIR:-/tmp}/.mogger-pay.$$"
rm -f "${TMPDIR:-/tmp}/.mogger-pay.$$"

# b. Luhn implementation
LN=$(grep -nEi -m1 "(function|def|const|let|var|func|fn)[[:space:]]+[[:alnum:]_]*luhn" "$FILE" 2>/dev/null | head -1)
if [ -n "$LN" ]; then c="${LN#*:}"; is_comment "$c" || addf "Luhn card-number validation implemented by hand" "${LN%%:*}"; fi

# c. card columns in a model/schema
if grep -qiE "create[[:space:]]+table|model[[:space:]]+[[:alnum:]_]+[[:space:]]*[{]|models[.]Model|Schema[(]|@Entity|define[(]|Column[(]" "$FILE" 2>/dev/null; then
  cv=$(grep -niE -m1 "(^|[^[:alnum:]_])(cvv2?|cvc2?)([^[:alnum:]_]|$)" "$FILE" 2>/dev/null | cut -d: -f1)
  nm=$(grep -niE -m1 "(^|[^[:alnum:]_])(card_?number|card_?num|card_?no|cc_?num|cc_?number)([^[:alnum:]_]|$)" "$FILE" 2>/dev/null | cut -d: -f1)
  ex=$(grep -niE -m1 "expir|exp_?(month|year|date)" "$FILE" 2>/dev/null | cut -d: -f1)
  if [ -n "$cv" ]; then addf "database model stores a CVV/CVC column (never storable, even encrypted)" "$cv"
  elif [ -n "$nm" ] && [ -n "$ex" ]; then addf "database model stores card number + expiry" "$nm"; fi
fi

# d. Stripe webhook that trusts the body
EV=$(grep -nE -m1 "checkout[.]session[.]completed|payment_intent[.]succeeded|invoice[.]paid|customer[.]subscription|charge[.]succeeded" "$FILE" 2>/dev/null | cut -d: -f1)
if [ -n "$EV" ] && grep -qi "stripe" "$FILE" 2>/dev/null \
   && grep -qE "JSON[.]parse[(]|req[.]body|request[.]json[(]|req[.]json[(]|request[.]get_json|request[.]data|request[.]body" "$FILE" 2>/dev/null \
   && ! grep -qiE "signature|constructEvent|construct_event|svix|hmac" "$FILE" 2>/dev/null; then
  addf "Stripe webhook handler parses the body and trusts it - no signature verification, anyone can POST fake 'paid' events" "$EV"
fi

[ -z "$FOUND" ] && exit 0
{
  echo "BLOCKED: $FILE looks like hand-rolled payment handling:$FOUND"
  echo "Use Stripe Checkout / Payment Element / your provider's hosted fields; never handle card numbers. Store only the provider's customer/payment ids (and last4). Webhooks must verify the signature (stripe.webhooks.constructEvent / Webhook.construct_event with the raw body). False positive? MOGGER_CHECK_PAYMENTS=off, and tell the user."
} >&2
exit 2

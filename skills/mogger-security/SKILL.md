---
name: mogger-security
description: App-security rules for code that handles user input, accounts, data access, secrets or payments. Use when writing routes/API handlers, database access, auth, env vars, or anything touching card data; and when reading a security scan or deciding whether to dispatch the security-reviewer agent.
---

# App security rules

Vibe-coded apps usually fail the same five ways. Follow these when writing
code; the hooks and scans check for them.

1. **Validate all input with a schema at the boundary.** Every request body,
   query string, URL param and webhook payload is parsed by a schema (zod,
   valibot, joi, pydantic, marshmallow) before any other code touches it.
   Reject on failure; never spread raw `req.body` into a database call.
   Use parameterized queries / the ORM; never build SQL, shell commands or
   HTML by concatenating request data. No `eval`, `new Function`,
   `shell=True`, or `innerHTML`/`dangerouslySetInnerHTML` with non-literals.
2. **Authenticate every route, then authorize every record.** Each handler
   checks who is calling (session/JWT/middleware) AND that the record they
   asked for belongs to them (`where: { id, userId: session.user.id }`).
   A route that looks up a row by an id from the URL and returns it is the
   classic "anyone can see anyone's data" bug. In Supabase enable row-level
   security on every table and add policies; in Firebase never ship
   `allow read, write: if true`.
3. **Secrets live server-side only.** Anything with a `NEXT_PUBLIC_`,
   `VITE_`, `REACT_APP_` or `EXPO_PUBLIC_` prefix is shipped to every
   visitor's browser. Only publishable/anon/site keys belong there. Never
   read a secret env var in a `"use client"` file, `public/`, or `.html`.
   Never commit `.env`; a key that reached git or a browser is compromised:
   rotate it. Do not disable TLS verification; set cookies `httpOnly`,
   `secure`, `sameSite`; never combine CORS `*` with credentials; no debug
   mode in production.
4. **Never build payment logic.** Do not handle, store, log or validate card
   numbers/CVV yourself (no Luhn code, no card columns). Use Stripe Checkout,
   the Payment Element or your provider's hosted fields, keep only their
   ids and last4, and verify webhook signatures on the raw body
   (`constructEvent` / `construct_event`) before trusting any event.
5. **Keep dependencies honest.** Commit a lockfile, do not pin to `latest`
   or `*`, run the audit, and only install packages you verified exist
   (verify-packages guards the install).

## Reading the scan

`bash scripts/checks/security.sh [dir]` and `bash scripts/checks/dep-audit.sh [dir]`
are report-only and always exit 0. Each line is `LEVEL|check-id|message`:

- **FAIL**: evidence of a real problem (secret behind a public prefix,
  table without RLS, open Firebase rules, TLS off, tracked `.env`, SQL from
  request data). Fix before shipping.
- **WARN**: suspicious or a labelled *heuristic* (route with no auth
  reference, no schema library, id lookup with no owner check). Read the
  cited `file:line` and decide; do not "fix" by silencing the scan.
- **SKIP**: the check could not run (audit tool or network missing). It is
  NOT a pass; say so when reporting.
- **PASS**: nothing found by that check. Grep-based scans miss multi-line
  and indirect patterns, so PASS is not a security guarantee.

Two hooks enforce the highest-confidence cases while you write:
`check-risky-code.sh` (public-prefixed secrets, open Firebase rules, TLS off,
SQL/eval with request data, server secrets in client files; off-switch
`MOGGER_CHECK_RISKY=off`) and `check-diy-payments.sh` (hand-rolled card
handling, Luhn code, unsigned webhooks; off-switch
`MOGGER_CHECK_PAYMENTS=off`). If one blocks you, fix the code; do not turn
it off without telling the user.

## When to dispatch security-reviewer

Dispatch the `security-reviewer` agent (it runs both scans, reads each
flagged spot, and labels every finding CONFIRMED / FALSE-POSITIVE /
NEEDS-HUMAN with evidence) when: the scan shows any FAIL or several WARNs;
before a first deploy or when the human asks "is this safe to ship?"; after
adding auth, database access, file upload, payments or a public API; and
before `reviewer` gives READY on a branch that touches any of those. It
never edits code; you apply its fixes.

---
name: mogger-privacy
description: Runs scripts/checks/privacy.sh and fills DATA.md. Use before sharing an app with real users, when adding a form/column/analytics script, or on "what user data do we keep?". Not legal advice.
disable-model-invocation: true
---

# mogger privacy

**Not legal advice.** The tool lists what the code does, with file:line
evidence. Whether GDPR / CCPA / any other law applies, which legal basis you
have, and how long data must or may be kept are decisions for the owner and a
lawyer. Say this line to the human every time you present the results.

## When to run
- Before the first real user, and before every ship (`/mogger-ship-check`).
- After adding a form field, a database column, a login provider, an
  analytics/ad/chat script, cookies, or file uploads.
- When the human asks "what personal data do we hold?" or "do I need a
  privacy policy / cookie banner?" (answer with findings, not opinions).

## Run
`bash scripts/checks/privacy.sh` (report-only; never modifies anything).
Lines are `LEVEL|check-id|message`:

| check-id | meaning |
|---|---|
| privacy-data | personal-data fields found (form fields, model columns, request fields, uploads, IP, geolocation) |
| privacy-trackers | analytics / ads / replay / chat SDKs found |
| privacy-cookies, privacy-storage, privacy-logging | cookies set, personal data in browser storage, request bodies/emails logged |
| privacy-processors | third-party services in dependency files that can receive data |
| privacy-policy, privacy-consent | policy page exists; consent banner exists when trackers do |
| privacy-delete, privacy-export | delete-account / export-my-data code exists (heuristic) |
| privacy-retention, privacy-subprocessors | a retention note exists; subprocessor/DPA mentioned |

Matches are heuristic: a line needs a token (email, phone...) AND a
form/schema/request context. It can over-report and it cannot see data that
lives only in a third-party dashboard.

## Fill DATA.md
Copy `templates/DATA.md` to the project root as `DATA.md` (if it does not
exist), then:

1. One row per `privacy-data` finding. "Where collected/stored" is the
   file:line the tool printed. Do not add rows for data the tool did not find;
   list it under "Open questions" if you suspect it.
2. "Third parties" rows come from `privacy-trackers` and `privacy-processors`.
3. **Never invent** a purpose, a recipient, a retention period, a legal basis
   or a deletion method. If the code does not show it and the human has not
   said it, write `OWNER TO DECIDE` and add a numbered question at the bottom.
4. Ask the human the open questions in one batch (max ~6, most important
   first). Write their answers verbatim, attributed as "owner said".
5. Copy each WARN/PASS artifact status into the artifacts table with its
   evidence.

## Report
Show: the WARN lines, the open questions, and the sentence "This lists what the
code does; whether the law applies and what to do about it is for you and a
lawyer to decide." Do not draft a privacy policy or claim compliance.

# DATA.md — data map (what personal data this app handles)

NOT LEGAL ADVICE. This file records what the CODE does, filled from
`scripts/checks/privacy.sh` output (file:line evidence) plus answers from the
owner. Whether GDPR, CCPA or any other law applies, which legal basis you
have, and how long you must or may keep data are decisions for the owner and
a lawyer. Anything not known is written `OWNER TO DECIDE`, never guessed.

Last generated from privacy.sh: <date>

## Data map
One row per kind of personal data. "Where collected" and "Where stored" must
cite file:line from privacy.sh. Everything else is from the owner or
`OWNER TO DECIDE`.

| Data | Where collected | Where stored | Why (purpose) | Who receives it | How long kept | How deleted |
|---|---|---|---|---|---|---|
| email address | src/signup.html:12 | schema.prisma:4 | OWNER TO DECIDE | OWNER TO DECIDE | OWNER TO DECIDE | OWNER TO DECIDE |

<!-- The row above is an example of the shape. Delete it once real rows exist. -->

## Third parties that receive data
From privacy-trackers / privacy-processors lines. One row each.

| Service | Evidence | What it receives | Agreement (DPA / terms) |
|---|---|---|---|
| | | | OWNER TO DECIDE |

## Cookies and browser storage
| Name / API | Evidence | Purpose | Essential? |
|---|---|---|---|
| | | | OWNER TO DECIDE |

## Artifacts a small app usually needs (status from privacy.sh)
| Item | Status (PASS/WARN/SKIP) | Evidence or gap |
|---|---|---|
| Privacy policy page | | |
| Cookie / consent banner (if trackers) | | |
| Delete-account / erase route | | |
| Data export endpoint | | |
| Retention note or purge job | | |
| Subprocessor list / DPA mention | | |

## Open questions for the owner
Numbered, one per `OWNER TO DECIDE` above.
1.

## Not covered by the tool
Data held only in third-party dashboards, data set at runtime, offline
processes, backups, and anything the patterns cannot see.

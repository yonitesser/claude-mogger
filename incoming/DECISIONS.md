# DECISIONS.md — why we chose X

Append-only. Never edit or delete an existing entry (a hook blocks it).
To change your mind, add a new entry at the bottom, then flip the old
entry's `Status: active` line to `Status: superseded-by #n`. That one line
change is the only edit the hook allows; the old entry stays as history.

Entry format (copy the block, number it #n, one more than the last):

<!--
## #1 — Short title of the decision
- Date: YYYY-MM-DD
- Decision: what we chose, in one line
- Why: the reason, in one line (this line is shown at session start)
- Alternatives rejected: option A (why not); option B (why not)
- Evidence: link, file:line, or benchmark result
- Status: active
-->

---


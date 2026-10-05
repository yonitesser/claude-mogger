---
name: mogger-edge-cases
description: Unhappy-path protocol: tests for empty, huge, wrong-type, duplicate, timeout, 500 and permission-denied cases on every input handler or I/O. Use when building user-input code or when asked to "make it robust".
---

# Unhappy paths

Code that only works when the user does everything right is not done. Every
place where data comes IN (form, input handler, endpoint, CLI arg, file
upload) or goes OUT and back (fetch, DB call, third-party API) gets the
checklist below. Each row is a test that must exist and must assert a
specific result (a message shown, a status code, a state that did not
change). A test that only "doesn't crash" is not a test.

## Checklist (copy per handler/endpoint/fetch)

For an input handler or endpoint:
- [ ] **Empty**: `""`, missing field, `null`/`undefined`. Expect a specific validation error, nothing saved.
- [ ] **Whitespace only**: `"   "`. Expect the same as empty (trim first).
- [ ] **Huge**: 10x-1000x the expected size (long string, big file, 10k items). Expect a rejection or a limit, not a hang or a 500.
- [ ] **Wrong type**: number where text is expected, array where object, `"abc"` for an id. Expect a 4xx / validation error, not an exception.
- [ ] **Duplicate submit**: same action twice fast (double click, retry). Expect one effect (one row, one charge), or the button disabled.
- [ ] **Permission denied**: not logged in, wrong user, wrong role. Expect 401/403 and no data leaked.

For a fetch / outbound call:
- [ ] **Network timeout / offline**: request never answers. Expect a visible error state and a way to retry, not an endless spinner.
- [ ] **Server 500**: upstream fails. Expect a friendly error, no half-written state.
- [ ] **Slow response**: answer arrives after 3+ seconds. Expect a loading state, and no double-render when it lands.
- [ ] **Empty result**: 200 with `[]`. Expect an empty-state message, not a blank screen.

Mark a row "n/a: <reason>" in the task instead of silently skipping it.

## Phrasing "done when"

Weak: "done when: the form works". Strong: name the input, the action, and the
observable result.

- "done when: submitting an empty name shows 'Name is required' and creates no row"
- "done when: POST /orders with `qty: \"abc\"` returns 400 and the order count is unchanged"
- "done when: with the API stubbed to time out, the page shows 'Could not load - Retry' within 5s"
- "done when: clicking Pay twice within 1s creates exactly one charge"

A "done when" that a broken implementation could also satisfy is too weak.

## Worked examples

**1. Signup form (input handler).** Happy path: valid email creates a user.
Add: empty email -> "Email is required", no user row. `"   "` -> same.
`"not-an-email"` -> "Enter a valid email". 5,000-character email -> 400, no
crash. Submit twice -> one user (unique constraint or disabled button).
Test names: `rejects empty email`, `rejects whitespace-only email`,
`creates one user on double submit`.

**2. GET /api/items/:id (endpoint).** Happy path: existing id returns the item.
Add: id `abc` (wrong type) -> 400, not 500. Unknown id -> 404 with a JSON
error body. No auth header -> 401. Another user's item -> 403, and the body
contains none of that item's fields.

**3. Dashboard `fetch('/api/stats')` (fetch).** Happy path: numbers render.
Add: stub the request to reject -> "Could not load stats" plus a Retry
button, and clicking Retry refetches. Stub 500 -> same message. Stub a
3-second delay -> a spinner shows first, then the numbers, once. Stub `[]`
-> "No data yet".

## How to run this

1. Planner: every task touching input or I/O carries at least one unhappy-path "done when".
2. Builder: write the failing unhappy-path test FIRST, watch it fail, then make it pass.
3. Tester: confirm those tests exist and ran (not skipped). The `check-test-quality` hook blocks empty, assertion-less and tautological tests; `scripts/checks/tests-quality.sh` reports whether any test name mentions an error case at all.

---
id: STATBUS-373
title: >-
  propagate rollback errors and make retreat-marker writes authoritative
status: To Do
assignee: []
created_date: '2026-09-17 10:44'
updated_date: '2026-09-17 10:44'
labels:
  - upgrade
  - recovery
  - fail-fast
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Finding (independent review, 2026-09-17)

Review of the rc.17 recovery fix found two P1 error-authority defects in
surrounding rollback code. A failed `RetreatedToSourceAt` write is swallowed,
which can leave a stale recovery marker for a later `./sb install` to act on.
Separately, `recoveryRollback` discards errors returned by `d.rollback`, so the
caller can proceed without owning the rollback outcome.

These findings are outside the narrow caller-scope repair in `34aad3dc2`. If
either is not landed in the rc.18 P0 repair stack, it remains release-blocking
work here rather than disappearing from the review record.

## Done when

1. A failed `RetreatedToSourceAt` persistence step is returned and terminally
   narrated; no stale marker is left as valid recovery authority.
2. `recoveryRollback` propagates or explicitly terminalizes every `d.rollback`
   error; no returned error is discarded.
3. Tests execute both failure branches, assert the durable marker/row state, and
   mutation checks prove that removing either error path makes the tests fail.

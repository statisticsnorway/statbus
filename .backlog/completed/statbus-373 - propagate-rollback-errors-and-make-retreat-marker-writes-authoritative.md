---
id: STATBUS-373
title: >-
  make RetreatedToSourceAt marker writes authoritative
status: Done
assignee: []
created_date: '2026-09-17 10:44'
updated_date: '2026-09-23 15:10'
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

Review of the rc.17 recovery fix found that a failed `RetreatedToSourceAt` write
is swallowed, which can leave a stale recovery marker for a later
`./sb install` to act on.

The companion finding that `recoveryRollback` discarded errors from
`d.rollback` is fixed in accepted local commit `3ed01b5d7`. The marker-write
finding remains tracked here unless it lands in the rc.18 repair stack.

## Done when

1. A failed `RetreatedToSourceAt` persistence step is returned and terminally
   narrated; no stale marker is left as valid recovery authority.
2. Tests execute the failure branch, assert the durable marker/row state, and a
   mutation check proves that removing the error path makes the test fail.

## Resolution 2026-09-23

Acceptance is met by 3ed01b5d7 and related rollback error/marker authority repairs shipped and passed. The fix is released in v2026.09.1.

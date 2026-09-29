---
id: STATBUS-428
title: Upgrade daemon readers never dereference a nil database connection
status: To Do
assignee: []
created_date: '2026-09-29 00:30'
updated_date: '2026-09-29 08:05'
labels:
  - upgrade
dependencies: []
priority: medium
ordinal: 377200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Non-blocking note N2 from the review of the rollback convergence fix (tmp/review-rollback-db-recreate-2.md). After a recovery path that could not reconnect, several readers still dereference d.queryConn without a nil check (e.g. cleanStaleMaintenance ~service.go:5240). Today completeInProgressUpgrade fails first with ErrQueryConnUnavailable, which covers them in Run's order, but any reordering would reintroduce a panic. Sweep every d.queryConn/d.listenConn reader reachable after recovery; return ErrQueryConnUnavailable instead of panicking. Also consider N1: let the convergence defer retry the reconnect once after a success-path reconnect failure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every queryConn/listenConn reader reachable after recovery is nil-safe with a named error
- [ ] #2 A test drives each with nil connections and gets an error, not a panic
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit after v2026.09.3 (2026-09-29): v2026.09.3 (ce089d416) made completeInProgressUpgrade and upgradeParkedReason nil-safe. The full sweep of queryConn/listenConn readers (AC1/AC2) remains.
<!-- SECTION:NOTES:END -->

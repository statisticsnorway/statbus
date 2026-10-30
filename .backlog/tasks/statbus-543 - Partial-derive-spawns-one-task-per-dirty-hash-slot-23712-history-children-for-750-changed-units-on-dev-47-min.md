---
id: STATBUS-543
title: >-
  Partial derive spawns one task per dirty hash slot: 23,712 history children
  for 750 changed units on dev (47 min)
status: In Progress
assignee: []
created_date: '2026-10-30T12:27:00Z'
updated_date: '2026-10-30T12:28:00Z'
labels:
  - derive
  - performance
  - worker
dependencies: []
priority: high
type: bug
ordinal: 469204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: the report derives scale with the partition setting, not with the number of changed hash slots; a small import finishes its analytics in seconds to a minute.

### Zoom out
Every spawner that reads statistical_unit_facet_dirty_hash_slots may share the per-slot pattern; all are in scope. Per-child duration also degraded during the run (69 -> 235 ms); the cause is part of this ticket.

### Zoom in
Dev task 37208 (2026-10-29 12:04-12:51 UTC, tmp/dev-slow-*.log, tmp/dev-history-trend.log): import changed 267 lu / 483 est, 912 dirty hash slots. derive_statistical_history spawned 23,712 period children (912 x 26 periods), 31m35s; derive_statistical_history_facet another 23,712, 13m24s; each child writes 1-3 rows. Dev partition_count_target 64 (range width 256). Cause: the dirty branch of derive_statistical_history, _history_facet and _unit_facet spawns one singleton range per dirty slot; the full-rebuild branch groups by 16384/partition_count_target. The _period workers accept wide ranges.

### Closing review
Journal in tmp/journal.md; doc/db regenerated; derive-pipeline docs checked for singleton dirty children.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test fails before the fix: with N dirty slots spread over more ranges than partition_count_target allows, child count per period exceeds the number of ranges containing a dirty slot
- [ ] #2 After the fix the dirty branch spawns one child per partition range containing a dirty slot, for history, history_facet and unit_facet
- [ ] #3 Derived history/facet results equal a full rebuild after a partial change (test)
- [ ] #4 Fast Tests green in CI for the commit
- [ ] #5 [Owner] Per-child slowdown (69 -> 235 ms) reproduced locally and its cause recorded in tmp/journal.md; fixed here or a follow-up ticket filed
- [ ] #6 [Owner] Per-child slowdown (69 -> 235 ms) reproduced locally from a dev dump by re-running the import, cause recorded in tmp/journal.md, fixed here or a follow-up filed
<!-- AC:END -->

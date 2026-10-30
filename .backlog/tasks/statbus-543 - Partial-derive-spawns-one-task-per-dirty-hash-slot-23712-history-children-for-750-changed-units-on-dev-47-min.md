---
id: STATBUS-543
title: >-
  Partial derive spawns one task per dirty hash slot: 23,712 history children
  for 750 changed units on dev (47 min)
status: In Progress
assignee: []
created_date: '2026-10-30T12:27:00Z'
updated_date: '2026-10-30T14:03:00Z'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
13:46 progress.
- Commit 2a915aac2: dirty derives spawn one child per partition range (migration 20261030125747); test 204 extended (red: children_span_partition_ranges f x3, green t x3); test 355 (STATBUS-538) folded into 204 and deleted. e0170f82a: 7 expected files where only the analytics completed-task count dropped (110,111,203,309,310,314,317); CI Fast Tests 41060820618 had failed on exactly those.
- Local repro on dev copy (dbdumps/dev_20261030_132822.pg_dump), rerun of job 38 (988 dirty slots): old code 23,712 history children, history step 16m49s; fixed 1,536 children, 57 s; total 7m42s (tmp/543-clone-{old,fixed}.log).
- Slowdown cause: derive_statistical_history_period year-month DELETE seq-scanned statistical_history (lower(hash_partition), month IS NOT DISTINCT FROM): 144 ms -> 0.15 ms with migration 20261030133114 (compare column to singleton ranges, month = / IS NULL). Plans captured in 303 explain set with enable_seqscan off.
- Next: facet def nested loop on text facet_key (925 of 950 ms per child) folded into this ticket; then clean timing rerun.

13:48 commit 2b8590d97: migration 20261030133114 (history period DELETE: hash_partition compared to singleton ranges, month = / IS NULL). 303 now captures both period DELETE plans (enable_seqscan off, as postgres): Index Scan using statistical_history_partition_{year,month}_key. Old predicate gives Bitmap Heap Scan with lower(hash_partition) filter (tmp/543-explain-old-shape.log). 204 green with it.

13:56 commit c9dbad627: migration 20261030135034, statistical_history_facet_def stats_by_facet AS MATERIALIZED (inlined CTE was nested-looped and re-aggregated per row): 954 -> 37 ms per 256-slot child, 0 differing rows vs stored data (tmp/543-facet-try.log). 204 green.
Clean rerun of dev job 38 on dev copy with all three fixes (job 45, tmp/543-clone-final.log): total 3m03s. history 1536 children avg 48 ms (63 s); history_facet 1536 avg 68 ms (64 s); facet_reduce 34 s. Before: dev 47 min; local old code 22.5 min (history step alone 16m49s); spawn fix only 7m42s.

14:01 Expected-output review (independent read-only agent): 204, 110, 111, 203, 309, 310, 314, 317 and 2b8590d97 (303) all VERIFIED, no derived value changed; 538 checks from 355 survive in 204 (stronger: staging count asserted). Follow-ups: full suite via CI on final SHA; singleton-row invariant now enforced by CHECK statistical_history_hash_partition_is_one_slot (migration 20261030135909; dev copy 302,136 per-slot rows, 0 violations); testing locally, then push.

14:03 commit be3fe321b: CHECK statistical_history_hash_partition_is_one_slot; 204 green; doc/db table doc updated. Final SHA for CI.
<!-- SECTION:NOTES:END -->

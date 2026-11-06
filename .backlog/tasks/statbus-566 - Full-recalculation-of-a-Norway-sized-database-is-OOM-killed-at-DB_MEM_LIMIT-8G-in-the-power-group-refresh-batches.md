---
id: STATBUS-566
title: >-
  Each power-group refresh batch recomputes timepoints for every unit in the
  database
status: In Progress
assignee: []
created_date: '2026-11-04T00:43:00Z'
updated_date: '2026-11-06T18:21:00Z'
labels:
  - performance
  - worker
dependencies: []
priority: medium
type: bug
ordinal: 489204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A refresh batch costs in proportion to the units it names, so a full recalculation of a country-sized register fits the memory of a private cloud slot.

### Zoom out
An empty set of ids and "every unit" must read differently wherever a refresh hands ids on: NULL means all units, an empty array means none.

### Zoom in
On full Norway (3,139,134 units) restored locally with DB_MEM_LIMIT=8G (the documented cap for a private cloud slot, doc/CLOUD.md), worker.enqueue_derive_statistical_unit_all() completes 3,137 of 3,165 statistical_unit_refresh_batch tasks, then the power-group batches (401 power groups each) get PostgreSQL OOM-killed 15 times. The analytics queue runs 4 at a time (worker.queue_registry default_concurrency 4). rune (32G, 8GB shared_buffers, 1GB work_mem) finishes the same batches in 59-70 s.

Cause (2026-11-04, tmp/558-shd/q4-*): worker.statistical_unit_refresh_batch passes the establishment, legal-unit and enterprise id ranges straight to timepoints_refresh. A power-group batch has none, so they are NULL, which timepoints_calculate reads as "every unit". Each power-group batch therefore computes timepoints for all 6.2M units (about 65 s) and the table ends unchanged. That full-scan query grows each backend by about 1-1.5 GiB; four in parallel on top of shared_buffers exceed 8 GiB. work_mem only changes how much each query spills. An earlier single-batch measurement (tmp/558-shd/p14-*) had suggested work_mem as the driver; the cause above replaces it.

Fix: a power-group batch passes empty ranges ('{}') for the other unit types, so it computes only its own groups.

### Closing review
- **Memory:** none beyond the ticket.
- **Documentation:** measurements in doc/performance/2026-11-history-delta-measurements.md section 5.
- **Cleanup:** the 4 GB test setting on the dev box was restored to DB_MEM_LIMIT=8G on 2026-11-06 18:20.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A full recalculation of a Norway-sized database completes at DB_MEM_LIMIT=8G with no OOM kill
- [x] #2 A power-group refresh batch computes timepoints only for its own power groups: on Norway one batch of 401 groups takes seconds, not 61-90 s
- [x] #3 After a power-group batch the timepoints table holds the same rows as a whole-database timepoints computation
- [x] #4 A regression test shows a power-group-only refresh leaves the timepoints of establishments, legal units and enterprises untouched and computes only the given groups
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-04 cause corrected (the work_mem theory was wrong; tmp/558-shd/q4-*):
- worker.statistical_unit_refresh_batch passes v_establishment_id_ranges, v_legal_unit_id_ranges and v_enterprise_id_ranges straight to timepoints_refresh/timesegments_refresh. A power-group batch payload has no establishment/legal-unit/enterprise ids, so these are NULL.
- In timepoints_calculate NULL means every unit (its own comment: NULL = full scan, '{}' = skip). So each power-group batch computes timepoints for all 6.2M units: 1,664,546 establishment + 2,271,883 legal-unit + 2,271,883 enterprise rows, plus 802 power-group rows, in 32.6 s; the refresh then deletes nothing and inserts with ON CONFLICT DO NOTHING, so the table ends unchanged.
- Step timing of one 401-group batch: timepoints_refresh 67.4 s, timesegments_refresh 0.02 s, timeline_power_group_refresh 2.8 s, statistical_unit_refresh 0.06 s.
- A batch of ONE power group also takes 61 s. Cost does not depend on group count; 64 batches x ~79 s = ~84 min of the full recalculation.
- Memory: that full-scan query is what grows each backend by ~1-1.5 GiB; 4 in parallel exceed 8G. work_mem only changes how much each spills.
- Prototype: passing '{}' for the three unit ranges gives the same timepoints table (all four unit types, row count and content hash equal, 0 power-group rows differ) and timepoints_refresh drops from 65.7 s to 0.003 s.
- Power groups: 25,634 groups, median 2 legal units, p99 3, max 880.

2026-11-04 failing test 366 (local commit): one power group plus an independent legal unit; after deleting the independent unit's timepoints a power-group-only batch must leave them absent. Pre-fix: 2 timepoints reappear (tmp/test-366-prefix.log, tmp/366-prefix-actual.out). With the proposed change (tmp/review/q4-566.diff: COALESCE the three unit ranges to '{}' in the timepoints_refresh and timesegments_refresh calls) the result rows equal the expected file (tmp/558-shd/566-proto.out). Not migrated; waits on owner.

2026-11-04 owner approved the fix (21:20). Migration 20261104212109_power_group_batch_refreshes_only_its_own_units_timepoints (local commit 9836026cd), regression test 366 committed earlier (6a0753a2c). worker.statistical_unit_refresh_batch now passes '{}' instead of NULL for unit types absent from the batch to timepoints_refresh and timesegments_refresh. Test 366: fails without the fix (tmp/test-558-fast-6.log, not ok 120), passes with it (tmp/test-566-after.log); fast suite 121/121 (tmp/test-566-fast.log). AC3 (same timepoints) shown by the earlier Norway prototype (counts and content hash equal); AC1/AC2 need a Norway full recalculation after this lands. Not pushed yet.

2026-11-06 11:52 Landed in local master 67488988e (fast-forward, owner 11:41: land the whole set, then one release with one full recalculation). Not pushed. Fast suite on that tip 124/124 (tmp/test-stack-fast.log).

2026-11-06 18:17 AC1/AC2 measured: full Norway recalculation on statbus_local (local master fb57ed58f) at DB_MEM_LIMIT=4G, half the 8G the AC names, so 8G is covered with margin. Worker exit 0, wall 2,883 s. No OOM kill (OOMKilled=false, 0 restarts, no kill lines in the db log). Memory 1.3-1.9 GiB most of the run; peak 3.89 GiB of 4 GiB for ~90 s while derive_statistical_history_facet_delta_partition ran 4 at a time. AC2: 64 power-group batches, 124 s total, longest 3.8 s for 401 groups (was 61-90 s each). Checks: staging drained (0 rows); 2026 year-end stock equals a direct count from statistical_unit for all four unit types. Task time: refresh_batch 6,475 s (3,165 tasks), history partitions 2,991 s, unit facet partitions 774 s. Evidence: tmp/566-4g/ (run-meta.txt, mem.log, tasks.txt, peak.txt, pg-batches.txt, check-bc.log, install-log.md).
<!-- SECTION:NOTES:END -->

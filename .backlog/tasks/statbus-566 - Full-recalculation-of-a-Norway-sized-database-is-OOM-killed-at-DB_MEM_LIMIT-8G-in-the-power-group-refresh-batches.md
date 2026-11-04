---
id: STATBUS-566
title: >-
  Each power-group refresh batch recomputes timepoints for every unit in the
  database
status: In Progress
assignee: []
created_date: '2026-11-04T00:43:00Z'
updated_date: '2026-11-04T07:08:00Z'
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
On full Norway (3,139,134 units) restored locally with DB_MEM_LIMIT=8G (the documented cap for a private cloud slot, doc/CLOUD.md), worker.enqueue_derive_statistical_unit_all() completes 3,137 of 3,165 statistical_unit_refresh_batch tasks, then the power-group batches (401 power groups each) get PostgreSQL OOM-killed 15 times. The analytics queue runs 4 at a time (worker.queue_registry default_concurrency 4). rune (32G, 8GB shared_buffers, 1GB work_mem) finishes the same batches in 59-70 s.

Measured one batch alone (task 847206 payload, inside BEGIN/ROLLBACK, tmp/558-shd/p14-*):
- baseline container memory 2.5 GiB; one batch peaks at 4.0 GiB (+1.5 GiB), 71 s
- work_mem 64MB instead of 256MB: peak 3.1 GiB (+0.6 GiB), 65 s
- temp_buffers 256MB instead of 1GB: peak 4.0 GiB, no change
So the per-batch growth is work_mem-driven (several sort/hash nodes per query). Four concurrent batches at +1.5 GiB on top of shared_buffers 2 GiB exceed 8 GiB.

computeDbMemory (cli/internal/config/config.go) sets work_mem = DB_MEM_LIMIT/32 without regard to the analytics concurrency.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A full recalculation of a Norway-sized database completes at DB_MEM_LIMIT=8G with no OOM kill
- [ ] #2 A power-group refresh batch computes timepoints only for its own power groups: on Norway one batch of 401 groups takes seconds, not 61-90 s
- [ ] #3 The timepoints table after a power-group batch equals today's result, row for row
- [ ] #4 A regression test shows a power-group-only refresh leaves the timepoints of establishments, legal units and enterprises untouched and computes only the given groups
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
<!-- SECTION:NOTES:END -->

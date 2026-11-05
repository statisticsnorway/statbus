---
id: STATBUS-574
title: >-
  statistical_unit_refresh_batch takes 47% of worker time on the full BRREG
  import
status: To Do
assignee: []
created_date: '2026-11-05T17:53:00Z'
updated_date: '2026-11-05T17:53:00Z'
labels:
  - performance
  - worker
dependencies: []
priority: medium
type: enhancement
ordinal: 493204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A unit refresh costs in proportion to the units it refreshes, so imports and full recalculations spend most of their time importing, not refreshing.

### Zoom out
`worker.statistical_unit_refresh_batch` rebuilds the statistical_unit rows of a batch of units. It is the largest single cost of the analytics pipeline once the history steps were made sparse (STATBUS-558).

### Zoom in
**Evidence.**
- Full BRREG import benchmark (`./test/import_benchmark.sh --dataset downloads`, 2026-11-05, log tmp/558-build/bench-downloads-final.log, database import_benchmark_43190 retained): 7,828 refresh_batch tasks, 10,320 s of 21,932 s summed task time (47%); min 204 ms, max 6,959 ms, average 1,318 ms. Next: import_job_process 5,493 s, derive_statistical_unit_facet_partition 1,845 s, statistical_unit_flush_staging 1,691 s, history delta partitions 1,049 s.
- Norway production full recalculation on 2026-11-02 (rune, read-only task history): unit refresh about 78% of 4,835 s wall.
- STATBUS-566 removed one cause (power-group batches recomputed every unit's timepoints); this ticket is the remaining cost.

**Scope.** Profile one representative batch (EXPLAIN ANALYZE of its statements, per-statement time, rows touched), find where time grows faster than the batch, and propose a change with measurements. Not part of STATBUS-558 (owner 2026-11-05 16:08: investigated by someone else).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A profile of one representative refresh_batch on the BRREG downloads database names the statements that take most of its time, with EXPLAIN ANALYZE output
- [ ] #2 Batch time against batch size is measured, showing whether cost grows with the batch or with the database
- [ ] #3 A proposed change is measured on the downloads benchmark against this ticket's 10,320 s baseline, with the benchmark's consistency checks passing
<!-- AC:END -->

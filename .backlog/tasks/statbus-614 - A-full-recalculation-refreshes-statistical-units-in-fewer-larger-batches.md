---
id: STATBUS-614
title: A full recalculation refreshes statistical units in fewer, larger batches
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-11T05:02:00Z'
updated_date: '2026-11-11T07:06:00Z'
labels:
  - performance
  - db
dependencies: []
type: enhancement
ordinal: 528204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A full recalculation (worker.derive_statistical_unit with no unit ranges) splits the register into change sets of about 1000 units through public.get_temporally_closed_change_sets: 3,162 refresh batches of about 500 ms on the full register. Work paid once per batch is cheaper with fewer batches, as long as every worker stays busy. Incremental cycles take the filtered path and keep their batching.

Measured on import_benchmark_64469 (master + STATBUS-613, 3,118,352 units, real worker with 4 analytics workers, load 5-13), every derived table identical in every round:
- 1000 units: 3,162 batches, wall 607 / 599 s, summed refresh 1,518 / 1,453 s.
- 2000 units: 1,612 batches, 565 / 581 s, 1,386 / 1,366 s.
- 4000 units: 838 batches, 548 / 534 s, 1,277 / 1,276 s.
- 8000 units: 451 batches, 514 / 526 / 514 s, 1,209 / 1,237 / 1,228 s; longest batch 10.6-11.8 s.
- 16000 units: 258 batches, 517 s, 1,205 s; longest batch 15.2 s.
The refresh phase keeps all four workers busy at every size (span equals summed time / 4 within 1-6%; the last batch runs alone under 1 s). The gain flattens at 8000; 16000 adds nothing and lengthens each batch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A full refresh splits the register into change sets of up to 8000 units, each holding whole closed groups
- [x] #2 The rows a full recalculation produces are identical to those of 1000-unit batches (all 16 derived tables)
- [x] #3 Incremental (filtered) cycles keep their batching
- [x] #4 Measured whole recalculations on the full register recorded against master
- [x] #5 An enterprise timeline refresh of a whole batch reads each enterprise segment once, also when planner statistics undercount the tables
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-11 06:46 Implementation: migration 20261111050226 (worker.derive_statistical_unit full path change sets 1000 -> 8000; public.timeline_enterprise_refresh partial path materializes the batch's enterprise segments into an analyzed temp table and joins that). Down = exact \sf dumps (statbus_seed at 20261110231201), verified by diff after down.
Found on the way: the first fast-suite run hung 35 min in the new test (100% CPU in timeline_enterprise_refresh). With planner statistics that undercount the source tables (as in a shared test database, a template clone, or after an ANALYZE while rows were uncommitted), the partial refresh read every enterprise segment once per enterprise: 3,000 enterprises 4,504,500 segment rows, 21.8-22.3 s; 500 enterprises 0.17-0.27 s. Other per-batch steps stay linear (timepoints 34/132 ms, timesegments 28/133 ms, timeline_legal_unit 28/169 ms for 500/3,000). The fix reads 3,000 rows (56 ms / 427 ms), rows identical.
Test 356: RED on master (6 batches of 1000; 4,504,500 segment rows read) / GREEN (1 batch of 6000; 3,000 rows read); same statistical_unit rows and timeline_enterprise rows.
Full register at 8000 with good statistics, ABBA: timeline guard on 570/534 s, off 542/536 s (within spread), all 16 tables identical x4. Other rejected candidate: history-delta spawner from estimates (saves 22-33 s, partitions pay ~30 s wall as first readers of fresh staging; net ~0).

Fast suite 140/140 + 094 + 143 PASS (tmp/test-614-fast.log); 356 in the shared run in seconds. doc/db regenerated (two procedures); the unrelated view-deparse flip in public_statistical_unit_def.md left out.

Open: in the full fast suite 356 took 324 s once (06:46 run, load up to 21), 30 s and 6.4 s in two shared-prefix runs, 6 s alone; with every table's statistics forced to one row a full recalculation of its fixture takes 3.3 s. The quadratic enterprise-timeline plan is fixed (4,504,500 -> 3,000 segment reads); the 324 s outlier is not yet explained and is being chased before Done.
<!-- SECTION:NOTES:END -->

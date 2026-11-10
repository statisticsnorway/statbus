---
id: STATBUS-605
title: Timeline refresh reads only the batch's units
status: Done
assignee:
  - hibiscus
created_date: '2026-11-10T11:32:00Z'
updated_date: '2026-11-10T21:48:00Z'
labels:
  - performance
  - worker
  - statistical-unit
dependencies: []
priority: high
type: enhancement
ordinal: 519204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On the full register one establishment refresh batch of 333 units takes about 41 s, 28.3 s of it in timeline_establishment_refresh. The establishment_stats CTE in timeline_establishment_def aggregates all 115,428 establishments before the batch filter applies. STATBUS-581 fixed the same shape for legal units with timeline_legal_unit_def_for(ids). Give each timeline refresh (establishment, legal unit, enterprise, power group) a definition that reads only the batch's rows, with identical output.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each of the four timeline refreshes is measured on a real full-register batch (import_benchmark_64469), with time and plan recorded
- [x] #2 Establishment refresh reads only the batch's establishments: a regression test fails before and passes after
- [x] #3 Per-batch definitions give identical rows to the full view on real batches
- [x] #4 Enterprise and power group refreshes are fixed the same way, or measured and shown not to scan the whole register
- [x] #5 Fast suite passes, doc/db regenerated, change on master with hosted CI green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch statbus-timeline-per-batch commit 6bf606b10 (on master 1f1e3091a), migration 20261110114354, test 397.
Measured on import_benchmark_64469 brought to exact master (445 migrations, function/view md5 == seed), full recalculation through the real worker with auto_explain >2 s:
- Establishment refresh: stats aggregate read every establishment's timesegments up to the batch's max id. Baseline slow log: 230 of 260 statements >2 s were this insert (621 s); with timeline_establishment_def_for(ids): 0. Test 397 RED on master (2021 rows read for 11-row batch), GREEN with fix (22).
- Legal unit, enterprise, power group refreshes already read only their batch (measured per table on a real batch); no change.
- Report phase: covering idx_statistical_unit_hash_slot + staging (hash_slot, unit_type, unit_id) index. History-delta partition 9.0 -> 2.6 s avg (256 partitions), unit facet partition 2.1 -> 0.34 s avg (256).
- Identity: six refresh outputs (4 timelines, timesegments, timepoints) fingerprint-identical to master; facet and history-delta rows identical per partition in rolled-back master-vs-fix runs.
- Tried, not adopted (in migration comment): INCLUDE(unit_type, unit_id)-only; VACUUM after flush (not needed, table stays all-visible).
Fast 137/137 + 094 + 143 PASS; up/down/up identical. Waiting: Rabbit cherry-pick to master after STATBUS-604, hosted CI.

2026-11-10 (Rabbit): on master as 8257d7fa9 + 70d67b718 (cherry-picks of Hibiscus f8b2ef4f3 + 9445e321c, rebased on STATBUS-604). Hosted CI green at 4321421d8 and at 4a66d2591 (Fast Tests 138 + 094 + 143 under pg_safeupdate, test 398 ok; Go, app, Images, Harness). Released in v2026.11.4-rc.01 (4a66d2591). doc/db and types regenerated before the cut (release check: DB documentation and types cover 20261110141700). AC5 checked.

Quiet-machine proof after release (2026-11-10 21:47, import_benchmark_64469 = v2026.11.4-rc.01 fresh-seed schema, load 8-18, full recalculation through the real worker, reversed order to cancel order effects): without 605 1,258 s wall, with 605 779 s wall (-38%). Refresh batches 3,357 -> 1,860 s task time (1.06 -> 0.59 s each), history-delta partitions 848 -> 360 s, facet partitions 94 -> 75 s. All 16 derived tables identical (row counts and content hashes). Under load (earlier run, 16-200) the same pair was 2,812 vs 1,292 s.
<!-- SECTION:NOTES:END -->

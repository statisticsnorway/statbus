---
id: STATBUS-574
title: >-
  statistical_unit_refresh_batch takes 47% of summed task time on the full BRREG
  import
status: In Progress
assignee: []
created_date: '2026-11-05T17:53:00Z'
updated_date: '2026-11-06T10:53:00Z'
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

### Closing review
- **Memory:** none expected.
- **Documentation:** doc/derive-pipeline.md timing table if the refresh changes.
- **Cleanup:** drop the import_benchmark_43190 database when the profile is done.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A profile of one representative refresh_batch on the BRREG downloads database names the statements that take most of its time, with EXPLAIN ANALYZE output
- [ ] #2 A proposed change is measured on the downloads benchmark against this ticket's 10,320 s baseline, with the benchmark's consistency checks passing
- [x] #3 Batch time is recorded in Implementation Notes for at least three batch sizes on the downloads database, with the timings
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-05 Owner 16:08: profiled separately from STATBUS-558, by someone else.

2026-11-06 00:23 Owner 23:49: investigate locally overnight on branch statbus-574-unit-refresh-profile (off statbus-558-history-delta), serialized with other local load; research first, no merge without owner.

2026-11-06 overnight investigation. Report and reproducible SQL: tmp/574/report.md, tmp/574/prototype-defs.sql.

Profile: legal-unit timeline INSERT is 3283.393/3758.997 ms (87.3%) in representative active batch 8857. Its partial aggregates scan all 1,134,475 LU segments. Dedicated indexed partial LU aggregation plus bounded/indexed propagation reduces median batch time 4150.413 -> 1179.848 ms (-71.6%, slowest task) and 3540.957 -> 383.484 ms (-89.2%, active near-mean task). Evidence: tmp/574/profile-notice.log:4191-5388, tmp/574/repeats.log:94-159,228-293.

Batch sizes, same LU type on retained downloads DB, two runs each: 100 IDs original 914.785-933.360 ms, prototype 70.430-71.565 ms. 1000 IDs original 5892.582-6353.258 ms, prototype 301.721-311.529 ms. 10000 IDs original 59333.170-62725.125 ms, prototype 3580.992-3836.072 ms. Evidence: tmp/574/curve-lu.log:27-161. ES three-size curve is in tmp/574/curve.log:6-113.

Validation: nine retained batches have identical positive-count row snapshots, EXCEPT ALL missing=extra=0 both ways (tmp/574/verify-all.log:76,134,192,250,308,366,424,482,540). Reject NOT MATERIALIZED alone: 2288 -> 56903 ms; partial-only indexed predicate gives 60.671 ms with identical rows (tmp/574/lu-prototype.log:396,779,1049-1065).

Prioritize LU then propagation. MATERIALIZED PG aggregation also helps, but PG accounts for only 27.596 s historically. Conditional ratio-transfer estimate: 7000-8600 s saved from 10320 s, not a measured full-import or wall-time saving. Import-phase cardinality/plans/contention differ from final-state replay, so implementation and full benchmark/consistency checks remain necessary. Sources: tmp/574/population.log:18-20, tmp/574/projection.txt, tmp/574/report.md:69-79. All database changes rolled back, original definition unchanged, retained DB preserved (tmp/574/final-state.log, tmp/574/definition-check.log).

AC1 and AC3 verified. AC2 full benchmark/consistency validation remains unverified. Status remains In Progress.

2026-11-06 10:53 Implemented on branch statbus-574-unit-refresh-profile (local): test 5aba434cd+59c4353e3 (370: a partial LU refresh reads at most 3 passes over its own units' timesegments, rows equal a full refresh; f on the pre-fix definitions tmp/574impl/370-prefix-v3.out, t after), migration 3aaf21508 (20261106101527).
Design: one source of truth kept. timeline_legal_unit_def's body became the SQL function timeline_legal_unit_def_for(p_unit_ids) (inlined, ids constant-folded), the view is its NULL case; the GUC statbus.filter_unit_ids is gone. Partial refresh: DELETE + INSERT from the function. Also ES->LU propagation bounded to the batch's LUs, LU->EN with = ANY, MATERIALIZED power-group aggregation.
Rolled-back checks on import_benchmark_43190: batch 22285 view 2,335 ms -> 69 ms (333 rows, EXCEPT ALL 0/0); full-refresh slice 1..65536 25.4/22.5 s -> 12.8/12.6 s (65,536 rows, 0/0); 8 repeated partial refreshes via EXECUTE USING 78-137 ms and static 91-124 ms (generic plan not a risk). Down/up round trip restores definitions. Not yet: full fast suite green after the 370 fixture fix, the 9-batch equality check of the whole migration (tmp/574impl/verify-migration.sql) and the downloads benchmark (AC2), waiting for laptop load to drop.
<!-- SECTION:NOTES:END -->

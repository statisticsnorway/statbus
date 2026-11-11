---
id: STATBUS-613
title: Flush and history reduce finish sooner on a full recalculation
status: Done
assignee:
  - hibiscus
created_date: '2026-11-10T23:10:00Z'
updated_date: '2026-11-11T00:37:00Z'
labels:
  - performance
  - db
dependencies: []
type: enhancement
ordinal: 527204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
A full recalculation's time goes to the work its result needs, so the register is current sooner after an import, with exactly the same rows.

## Zoom out
A lookup or a sort whose result nobody reads is pure cost. Find rows through the narrowest index that answers the question, and leave order to the one place that needs it.

## Zoom in
- The staging flush finds each affected unit's rows in statistical_unit through the GiST temporal key (statistical_unit_temporal_pk), about 30 µs per lookup, in both its DELETE and its MERGE. A btree on (unit_type, unit_id), 67 MB on the full register, answers the same lookup in about 5 µs.
- The flush DELETE deduplicates staging with a DISTINCT subquery; a semi join (EXISTS) needs no deduplication.
- The history reduce collects each group's unit ids with array_agg(unit_id ORDER BY unit_id), which sorts all 3.1M staged rows of a rebuild and keeps the aggregate serial. worker.unit_ids_apply sorts its result, so the input order is never seen; an unordered array_agg lets the aggregate run in parallel.
- Evidence so far (import_benchmark_64469, full register 3,118,352 rows, rc.01 + master, quiet machine, rolled back, identical row count and hash):
  - Whole flush, master vs both flush changes: 1% changed 33.3/23.8/28.3 s vs 27.7/20.5/24.4 s; 10% 102.9/119.3 s vs 61.0/46.6 s; 100% 128.0/93.3 s vs 78.2/85.4 s.
  - At 10%: DELETE 13.5 s (master) vs 10.5 s (semi join) vs 2.1 s (semi join plus btree); MERGE 33.7 s vs 24.4 s with the btree.
  - History reduce aggregate on a rebuild: 19.1/19.0 s ordered vs 15.2/14.5 s unordered, 394,931 groups, 0 differing rows.

## Closing review
Record rejected variants and their numbers in the migration comments and tmp/591/journal.md. No memory or documentation change beyond doc/db is expected.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 statistical_unit has a btree index on (unit_type, unit_id), and the flush finds affected units' rows through it
- [x] #2 The flush leaves statistical_unit with exactly the staged rows for affected units and every other unit unchanged
- [x] #3 The history reduce's unit_ids equal the contributing units in ascending order, and its output equals the ordered form on a full-register rebuild
- [x] #4 Measured on the full register against master with identical rows: whole flush and history reduce times recorded
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Whole recalculation of import_benchmark_64469 (rc.01 + master, 3,118,352 units, no data change), real worker, ABBA, quiet machine (load 8-16), tmp/613/proof.sh, logs tmp/613/rounds/: without 613 661 s and 693 s, with 613 691 s and 663 s (mean 677 vs 677: wall unchanged within run-to-run spread). All 16 derived tables identical in all four rounds. Serial steps: flush 40.2/53.9 -> 39.5/36.7 s, history reduce 36.9/38.1 -> 33.6/31.2 s. In a no-change recalculation the MERGE skips every row, so the larger flush gains are for loads that change data (10% changed: 102.9/119.3 -> 61.0/46.6 s). History old-side read (12,139 units of one partition) uses the new btree: 7.4 s via GiST -> 4.8 s.

Test 399: RED on a master-schema copy (399.4 flush_used_unit_index f), GREEN with the migration; down restores the exact \sf definitions of both procedures (diffed against statbus_seed). Fast suite 139/139 + 094 + 143 PASS (tmp/test-613-fast.log). doc/db regenerated (2 functions, statistical_unit table); an unrelated view-deparse flip in public_statistical_unit_def.md left out; types unchanged.

On master 0cc9fc5e4 (Rabbit fast-forward). CI at 0cc9fc5e4 all completed/success: Fast Tests 42930236563, Go Test 42929798402, app build & lint 42929798441, Images 42929798364, Harness Selftest 42929798347, Push on master 42929797680.
<!-- SECTION:NOTES:END -->

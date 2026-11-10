---
id: STATBUS-613
title: Flush and history reduce finish sooner on a full recalculation
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-10T23:10:00Z'
updated_date: '2026-11-10T23:11:00Z'
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
- [ ] #1 statistical_unit has a btree index on (unit_type, unit_id), and the flush finds affected units' rows through it
- [ ] #2 The flush leaves statistical_unit with exactly the staged rows for affected units and every other unit unchanged
- [ ] #3 The history reduce's unit_ids equal the contributing units in ascending order, and its output equals the ordered form on a full-register rebuild
- [ ] #4 Measured on the full register against master with identical rows: whole flush and history reduce times recorded
<!-- AC:END -->

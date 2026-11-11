---
id: STATBUS-615
title: Each refresh batch records its years with a plan that reads only its own units
status: Done
assignee:
  - hibiscus
created_date: '2026-11-11T10:50:00Z'
updated_date: '2026-11-11T11:35:00Z'
labels:
  - performance
  - db
dependencies: []
type: bug
ordinal: 529204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every refresh batch should cost the same no matter how many batches its worker has run before, so a full recalculation does not slow down as it goes. Recording which years a batch covers should read only that batch's own units, at any point in a worker's session, and record the same years as before.

Zoom out: a PL/pgSQL statement is planned once for all calls after its fifth execution in a session, so a statement whose filters are switched on and off by parameters gets a plan that must serve every combination. A statement that serves one case keeps a plan fit for that case.

Zoom in: public.timesegments_refresh records the years with one statement that OR-s four filters, each switched on by whether that unit type's ids were passed. PL/pgSQL gives a statement a generic plan after five executions in a session; the generic plan cannot see which filters apply and reads the batch's segments through the GiST index idx_timesegments_unit_daterange, on its non-leading unit_type and unit_id columns. Each worker session runs many batches, so most batches pay it.

Measured on import_benchmark_64469 (full register, 3,118,352 units, 8000-unit batches): the years statement takes 11 ms with a plan for the call's own values and 1,234 ms with the generic plan; the refresh rises from 322-361 ms (calls 1-5) to 686-837 ms (calls 6-10). A full recalculation scans the GiST index 1,524,130 times, all from this statement. On rune (rc.01, 1000-unit batches), 16,162,002 GiST scans since start; per call 999-1,000 scans and 90-154 ms; with one statement per unit type 0 scans and 44-73 ms. plan_cache_mode = force_custom_plan (the STATBUS-555 remedy) does not help here: on rune even the custom plan picks the GiST index (estimate 381 rows for 2,000).

One years statement per unit type, each with only its own id filter, reads through the (unit_type, unit_id) btree at any call count and records the same years.

Closing review: no memory change; the reason is recorded at the statement in the migration. Whether idx_timesegments_unit_daterange has any reader left after this change is a separate question for a follow-up.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Full recalculations on the full register produce identical derived tables, with and without the change
- [x] #2 The rune measurement (four full recalculations, two with and two without the change) is recorded in this ticket's notes
- [x] #3 timesegments_years holds the same years as before for the same batches: test 357 records the years from eight refresh calls and compares them with the years of the refreshed segments (same_as_refreshed_segments = t, 40 years with and without the change)
- [x] #4 After more than five refresh calls in one session, recording the years scans idx_timesegments_unit_daterange 0 times: test 357 shows 0 GiST scans after eight refresh calls in one session (1,400 without the change)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fast suite with the fix: 141/141 + 1 + 1 passed (tmp/test-615-fast.log), 357 in 10.5 s. Test 357 on the seed rebuilt by full replay of all 452 migrations: 0 GiST scans, same 40 years as the refreshed segments.

AC1: test 357, eight refresh calls in one session on 10,000 analyzed enterprises and legal units: 1,400 GiST scans on master (RED), 0 with the fix (GREEN). Full-register recalculation on import_benchmark_64469: 1,524,130 GiST scans on master, 0 with the fix. AC2: four local full-register recalculations (fix, master, fix, master, twice), all 16 derived-table fingerprints identical; rune rounds 1-2 identical to rune's before-fingerprint. AC4: test 357, 40 years with and without the change, same_as_refreshed_segments = t.

AC2, rune (rc.01, 1000-unit batches, 8 cores, load under 2), full recalculations through rune's own worker, order fix, current, current, fix, VACUUM ANALYZE before each round: wall 820, 819, 840, 819 s; statistical_unit_refresh_batch summed 2,044, 2,115, 2,143, 2,104 s; GiST scans +0, +3,099,812, +3,099,808, +0; every round 0 failed tasks and all 16 derived-table fingerprints identical to the fingerprint taken before any change. On rune the fix removes the scans but saves only about 2-3% of batch time and nothing in wall time: rune's GiST reads are cheap at 1000-unit batches. Rune restored: \sf public.timesegments_refresh equals the backup, worker idle (only the 3 recurring tasks pending), no.statbus.org answers.

CI on master 8c7724027 (fast-forwarded by Rabbit from 590d66aaf): all 8 runs success, including Fast Tests, Images, Go Test, Harness Selftest, app build & lint.
<!-- SECTION:NOTES:END -->

---
id: STATBUS-615
title: Each refresh batch records its years with a plan that reads only its own units
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-11T10:50:00Z'
updated_date: '2026-11-11T11:07:00Z'
labels:
  - performance
  - db
dependencies: []
type: bug
ordinal: 529204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every refresh batch should cost the same no matter how many batches its worker has run before, so a full recalculation does not slow down as it goes.

public.timesegments_refresh records the years a batch covers with one statement that OR-s four filters, each switched on by whether that unit type's ids were passed. PL/pgSQL gives a statement a generic plan after five executions in a session; the generic plan cannot see which filters apply and reads the batch's segments through the GiST index idx_timesegments_unit_daterange, on its non-leading unit_type and unit_id columns. Each worker session runs many batches, so most batches pay it.

Measured on import_benchmark_64469 (full register, 3,118,352 units, 8000-unit batches): the years statement takes 11 ms with a plan for the call's own values and 1,234 ms with the generic plan; the refresh rises from 322-361 ms (calls 1-5) to 686-837 ms (calls 6-10). A full recalculation scans the GiST index 1,524,130 times, all from this statement. On rune (rc.01, 1000-unit batches), 16,162,002 GiST scans since start; per call 999-1,000 scans and 90-154 ms; with one statement per unit type 0 scans and 44-73 ms. plan_cache_mode = force_custom_plan (the STATBUS-555 remedy) does not help here: on rune even the custom plan picks the GiST index (estimate 381 rows for 2,000).

One years statement per unit type, each with only its own id filter, reads through the (unit_type, unit_id) btree at any call count and records the same years.

Closing review: no memory change; the reason is recorded at the statement in the migration. Whether idx_timesegments_unit_daterange has any reader left after this change is a separate question for a follow-up.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After more than five refresh calls in one session, recording the years scans idx_timesegments_unit_daterange 0 times
- [ ] #2 timesegments_years holds the same years as before for the same batches
- [ ] #3 Full recalculations on the full register produce identical derived tables, with and without the change
- [ ] #4 The rune measurement (four full recalculations, two with and two without the change) is recorded in this ticket's notes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fast suite with the fix: 141/141 + 1 + 1 passed (tmp/test-615-fast.log), 357 in 10.5 s. Test 357 on the seed rebuilt by full replay of all 452 migrations: 0 GiST scans, same 40 years as the refreshed segments.
<!-- SECTION:NOTES:END -->

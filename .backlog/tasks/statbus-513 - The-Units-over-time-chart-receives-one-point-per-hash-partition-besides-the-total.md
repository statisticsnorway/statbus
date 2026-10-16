---
id: STATBUS-513
title: >-
  statistical_history: document what hash_partition marks, and test that the
  chart gets one point per period
status: In Progress
assignee: []
created_date: '2026-10-16 13:33'
updated_date: '2026-10-16 13:57'
labels:
  - reports
  - statistical_history
dependencies: []
priority: high
ordinal: 439204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Each Reports chart series has exactly one point per period: the total for that period.

### Zoom out
statistical_history holds the period total (hash_partition IS NULL) and, since 7b94a927f (2026-04-30), the per-partition slots that build it. Its row level security policies show admin_user, regular_user and authenticated only the totals. statistical_history_highcharts is SECURITY INVOKER, so the application gets one point per period. Nothing stated this: the column had no comment, and no test covered the chart.

### Zoom in
- **Original report was wrong.** I read the chart on dev as superuser, which bypasses RLS, and saw the total plus one point per slot. Read as admin_user it returns one point per period (2023: 11/23/23, 2024: 24/23/23), equal to the dashboard cards. The chart has no bug.
- **What was missing:** the meaning of hash_partition at its definition, and a test that pins one point per period on the real path (an application role).
- **Done here:** migration 20261016134307 adds the column comment, and test 354 runs the demo fixture through import and analytics and checks the chart as test.admin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 public.statistical_history.hash_partition carries a comment stating that NULL marks the period total, a range marks a partition slot, and that the RLS policies show application roles only the totals
- [x] #2 Test 354 calls statistical_history_highcharts as an application role and asserts exactly one point per period per series, equal to that period's total row
- [x] #3 Test 354 is recorded red when the totals-only policy is lifted (the chart then gets 13 to 25 points per period) and green on master
- [ ] #4 The fast suite and CI are green with the migration and the test
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Closing review
- Memory: none needed.
- Documentation: none; the hash_partition meaning belongs on its column comment if one is missing (check during the fix).
- Cleanup: none.

### Investigation state (2026-10-16 13:38, paused for the owner's session)
- **Dev:** statistical_history holds 12 total rows (hash_partition IS NULL) and 267 slot rows at year resolution, 2925 slot rows at year-month. The chart receives both.
- **Test database** (demo fixture + import + analytics, the same pipeline: derive_statistical_history -> 180 derive_statistical_history_period -> statistical_history_reduce): only total rows remain (135); no slot rows. So the slots that statistical_history_def writes (int4range(hash_slot, hash_slot+1), def line 119) are gone after the run in the test, yet persist on dev.
- **Open question:** what removes slot rows in the test, or why dev keeps them. Candidates: the period derive's no-partition branch (deletes the whole period, then writes slots), the reduce (deletes only totals), or a reset/cleanup path. Next step: read tasks.info per derive_statistical_history_period in the probe (tmp/354-probe-full.sql; the column is `info`).
- **Test:** test/sql/354_statbus_513_chart_points_are_period_totals.sql is written but cannot go red until the test database keeps slot rows like dev. Not committed.
- **Fix itself is clear and small:** add hash_partition IS NULL to both reads in statistical_history_highcharts.

### Evidence (23175c5fc)
- **Green:** test 354 passes on master. Each series has 1 point per period: establishment 2023: 12, 2024: 22; legal_unit 23/23; enterprise 23/23. Each equals its total row.
- **Red:** with statistical_history_admin_user_manage altered to USING (true), as test.admin, the chart gets 13 to 25 points per period (for example establishment 2023: 13 points, minimum value 1, total 12). Probe: tmp/354-red.sql.
- **Locally:** the fast suite passes, 118/118, and so does go test ./internal/migrate (the floor check for a comment-only migration above the floor).
- **Closing review:** Memory: none. Documentation: the column comment carries the meaning, and doc/db is regenerated. Cleanup: none.
- Waiting: CI for 23175c5fc.
<!-- SECTION:NOTES:END -->

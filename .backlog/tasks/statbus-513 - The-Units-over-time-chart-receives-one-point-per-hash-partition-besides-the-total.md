---
id: STATBUS-513
title: >-
  The Units-over-time chart receives one point per hash partition besides the
  total
status: In Progress
assignee: []
created_date: '2026-10-16 13:33'
updated_date: '2026-10-16 13:38'
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
statistical_history holds the period total (hash_partition IS NULL) and, since 7b94a927f (2026-04-30), per-partition slots used to build it (hash_partition NOT NULL). Every reader except the chart filters on hash_partition IS NULL (statistical_history_def, facet_def, the derive and reduce steps). public.statistical_history_highcharts reads the table by resolution, unit type and year only, so the partition slots reach the chart.

### Zoom in
- **Observed on dev, v2026.10.2-rc.01:** `statistical_history_highcharts('year', 'establishment', NULL, '{countable_count}')` returns 12 points at 2023-01-01: the total 11 and eleven 1s. Every unit type and year has the total plus one point per partition (24-25 points per timestamp).
- **Cause:** the two reads of public.statistical_history in the function (the merged summary and the series rows) lack `hash_partition IS NULL`. The merged `stats_summary` is therefore also double-counted.
- **Fix:** add `hash_partition IS NULL` to both reads, in a forward migration from the \\sf dump.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With the fix the test is green, and the merged stats_summary equals the total row's summary
- [ ] #2 On dev after the next candidate, the chart's countable_count series for 2023 and 2024 equals the dashboard cards (11/23/23 and 24/23/23)
- [ ] #3 A pg_regress test calls statistical_history_highcharts and asserts exactly one point per timestamp per series, equal to that period's total row
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
<!-- SECTION:NOTES:END -->

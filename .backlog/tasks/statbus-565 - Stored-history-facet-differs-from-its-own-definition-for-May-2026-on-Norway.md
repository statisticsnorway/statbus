---
id: STATBUS-565
title: Stored history facet differs from its own definition for May 2026 on Norway
status: To Do
assignee: []
created_date: '2026-11-04T00:21:00Z'
updated_date: '2026-11-04T00:38:00Z'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 488204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On a restore of Norway's 2026-11-03 backup (rc.04, last full derive on rune 2026-11-02 15:01-15:13), public.statistical_history_facet for year-month 2026-05 differs from public.statistical_history_facet_def('year-month', 2026, 5) run on the same data in 296 of 395,106 rows (establishment 130, legal unit 83, enterprise 83), in exists_change/exists_added_count (14 rows), name_change_count (57) and physical_address_change_count (239). Every other month and every year row matches. Example: establishment cell N.81.2.9.9 / region 18.68: unit 9173 moves out on 2026-05-07, units 60795 and 808886 have versions from 2026-05-07; stored exists_change 1, definition 2. statistical_history_facet_partitions holds no row for that cell. Found during STATBUS-558 (tmp/558-shd/14-norway-diff.sql, 15-may-cell.sql, 16-may-today-def.sql). The STATBUS-558 redesign replaces this table; the cause still matters for what the old reduce leaves behind.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The cause of the 296 stale May-2026 rows is identified and written in this ticket
- [ ] #2 After a full derive, statistical_history_facet equals statistical_history_facet_def for every period on the restored Norway data (0 differing rows)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
North Star: the stored history facet always equals its definition run on the current statistical_unit. Zoom out: check whether other months on other boxes show the same pattern (one month stale after a full derive). Closing review: no memory; no docs unless the cause is in the reduce; cleanup none.

2026-11-04 cause found (tmp/558-shd/17-565-guard.sql, 565-guard.log): worker.statistical_history_facet_reduce updates a matched row only WHEN MATCHED AND (target.exists_count <> source.exists_count OR target.stats_summary IS DISTINCT FROM source.stats_summary). All 296 stale May-2026 rows have the same exists_count and stats_summary as the definition and differ only in exists_change/exists_added_count, name_change_count, physical_address_change_count. So a row whose only change is in its change counts is never rewritten. Fix in the current pipeline: compare every column in the guard (or the whole row). STATBUS-558 replaces this reduce; the owner decides whether to fix it separately.

2026-11-04 failing test 365 (local commit): one legal unit renamed from 2024-06-01 with the same employees. Pre-fix: stored 2024 name_change_count 0 vs definition 1, 2 of 84 legal-unit rows differ (tmp/test-365-prefix.log, tmp/365-prefix-actual.out). Prototype fix (tmp/558-shd/565-reduce-fixed.sql): guard compares the full tuple of value columns with IS DISTINCT FROM; test 365 then shows 0 differing rows (tmp/558-shd/565-proto.out). Not migrated; waits on owner (fix now vs replaced by STATBUS-558).
<!-- SECTION:NOTES:END -->

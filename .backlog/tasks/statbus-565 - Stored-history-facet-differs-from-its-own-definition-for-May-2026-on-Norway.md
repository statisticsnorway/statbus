---
id: STATBUS-565
title: Stored history facet differs from its own definition for May 2026 on Norway
status: In Progress
assignee: []
created_date: '2026-11-04T00:21:00Z'
updated_date: '2026-11-06T11:52:00Z'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 488204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
STATBUS-558
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

2026-11-04 owner decision: resolved by STATBUS-558, no separate fix to worker.statistical_history_facet_reduce. 558 removes the reduce and the stored facet table; statistical_history_facet is a view over history_flow_delta, where every change count is staged and added, so a change that leaves exists_count and stats unchanged is no longer lost. Evidence on the 558 build: test 365 (rename shows name_change_count 1 for 2024 and June 2024, local commit cbc7320b7); full Norway facet 2026 equals today's stored rows except exactly these 296 stale May rows. Close as Done when STATBUS-558 lands (merged, release gates pass).

2026-11-06 11:52 Landed in local master 67488988e (fast-forward, owner 11:41: land the whole set, then one release with one full recalculation). Not pushed. Fast suite on that tip 124/124 (tmp/test-stack-fast.log).
<!-- SECTION:NOTES:END -->

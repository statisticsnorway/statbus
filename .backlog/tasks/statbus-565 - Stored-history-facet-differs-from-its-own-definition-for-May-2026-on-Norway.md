---
id: STATBUS-565
title: Stored history facet differs from its own definition for May 2026 on Norway
status: In Progress
assignee: []
created_date: '2026-11-04T00:21:00Z'
updated_date: '2026-11-07T16:10:00Z'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 488204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The history facet a report reads always equals its definition run on the current statistical_unit.

### Zoom out
A stored copy of a derived result stays correct only if every column that can change is compared when it is updated; a result read straight from its source cannot fall behind.

### Zoom in
On restored Norway, after a full derive, 296 May-2026 rows of the stored statistical_history_facet differed from statistical_history_facet_def. Cause (tmp/558-shd/17-565-guard.sql, 565-guard.log): worker.statistical_history_facet_reduce updated a matched row only when exists_count or stats_summary changed, so rows whose change counts alone changed (for example a rename) kept their old values. Test 365 reproduces it with one legal unit renamed from 2024-06-01 with the same employees: stored name_change_count 0, definition 1.

Owner decision 2026-11-04: fixed by STATBUS-558, which removes the stored facet and its reduce. statistical_history_facet is now a view over statistical_history_facet_delta, where every change count is staged and added.

### Closing review
- **Memory:** none.
- **Documentation:** doc/performance/2026-11-history-delta-measurements.md section 5.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The cause of the 296 stale May-2026 rows is identified and written in this ticket
- [x] #2 Test 365 (a rename with unchanged employees) shows name_change_count 1 in statistical_history_facet, as the definition does
- [x] #3 On restored Norway after a full derive, statistical_history_facet (now a view over statistical_history_facet_delta) has the same stock as the previous build in every cell of 2026 and months 5 and 11 (1,185,556 cells, tmp/558-onetable/23-compare-fixed.log), and its stats differ only where empty stats render as {} instead of {"type": "stats_agg"} (tmp/558-onetable/24-check.log)
- [ ] #4 The STATBUS-558 change is pushed to master with CI green for the pushed commit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
North Star: the stored history facet always equals its definition run on the current statistical_unit. Zoom out: check whether other months on other boxes show the same pattern (one month stale after a full derive). Closing review: no memory; no docs unless the cause is in the reduce; cleanup none.

2026-11-04 cause found (tmp/558-shd/17-565-guard.sql, 565-guard.log): worker.statistical_history_facet_reduce updates a matched row only WHEN MATCHED AND (target.exists_count <> source.exists_count OR target.stats_summary IS DISTINCT FROM source.stats_summary). All 296 stale May-2026 rows have the same exists_count and stats_summary as the definition and differ only in exists_change/exists_added_count, name_change_count, physical_address_change_count. So a row whose only change is in its change counts is never rewritten. Fix in the current pipeline: compare every column in the guard (or the whole row). STATBUS-558 replaces this reduce; the owner decides whether to fix it separately.

2026-11-04 failing test 365 (local commit): one legal unit renamed from 2024-06-01 with the same employees. Pre-fix: stored 2024 name_change_count 0 vs definition 1, 2 of 84 legal-unit rows differ (tmp/test-365-prefix.log, tmp/365-prefix-actual.out). Prototype fix (tmp/558-shd/565-reduce-fixed.sql): guard compares the full tuple of value columns with IS DISTINCT FROM; test 365 then shows 0 differing rows (tmp/558-shd/565-proto.out). Not migrated; waits on owner (fix now vs replaced by STATBUS-558).

2026-11-04 owner decision: resolved by STATBUS-558, no separate fix to worker.statistical_history_facet_reduce. 558 removes the reduce and the stored facet table; statistical_history_facet is a view over history_flow_delta, where every change count is staged and added, so a change that leaves exists_count and stats unchanged is no longer lost. Evidence on the 558 build: test 365 (rename shows name_change_count 1 for 2024 and June 2024, local commit cbc7320b7); full Norway facet 2026 equals today's stored rows except exactly these 296 stale May rows. Close as Done when STATBUS-558 lands (merged, release gates pass).

2026-11-06 11:52 Landed in local master 67488988e (fast-forward, owner 11:41: land the whole set, then one release with one full recalculation). Not pushed. Fast suite on that tip 124/124 (tmp/test-stack-fast.log).

2026-11-06 19:15 rebased local master onto origin/master ce9669a78 (after v2026.11.1-rc.17); tip 3e4b68ea6, 80 commits ahead, 0 merges, combined patch identical to before the rebase. Fast suite: all 124 shared + 2 isolated tests pass (tmp/test-rebased-fast.log). Not pushed. AC2: statistical_history_facet is now a view over statistical_history_facet_delta (STATBUS-558), so it is its definition; no stored copy can lag. Norway after a full derive: stock equal to the former definition in all 1,185,556 cells checked (2026 year, months 5 and 11; tmp/558-onetable/23-compare-fixed.log). Test 365 (rename only, same employees): name_change_count 1 as the definition, passes.

2026-11-07 hibiscus: owner 16:09 plan. Local master rebased onto origin 3282c0af7 (97 commits, 0 merges, patch identical) and pushed as branch statbus-history-release for rabbit to cut an RC from. Rabbit owns: RC cut + gate, Norway upgrade (run U), Norway wipe + full import (run B), release if green. Owner's doc/db review of the migrations was not done; owner approved the plan and the push. Ticket goes Done when that release passes (CI green on the released SHA; 558 also needs run U).
<!-- SECTION:NOTES:END -->

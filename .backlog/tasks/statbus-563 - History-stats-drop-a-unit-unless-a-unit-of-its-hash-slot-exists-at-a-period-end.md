---
id: STATBUS-563
title: >-
  History stats drop a unit unless a unit of its hash slot exists at a period
  end
status: Done
assignee: []
created_date: '2026-11-03T22:24:00Z'
updated_date: '2026-11-07T17:02:00Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 486204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
History statistics count every unit the documented population names for a period, whatever hash slot the unit falls in.

### Zoom out
A total over units is computed from each unit's own rows, never from rows that exist only because another unit kept them alive.

### Zoom in
The dense history built a period's stats by LEFT JOINing a per-slot aggregation onto the rows of units existing at a period end. A unit that overlaps the period but exists at neither end (the STATBUS-460 existence rule) lost its stats unless a slot-mate existed at an end. Test 364 shows it: two legal units in different hash slots (2955, 14449); 563000002 is born 2024-03-01 and dead 2024-09-30. Documented 2024 population 17 employees / 2 units; the dense history gave 10 / 1.

Owner decision 2026-11-04: fixed by STATBUS-558, not separately. In 558 each unit's stats are on its own delta rows, so no slot dependency remains.

### Closing review
- **Memory:** none.
- **Documentation:** doc/performance/2026-11-history-delta-measurements.md section 5.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 statistical_history and statistical_history_facet stats_summary equal the documented population for each period, independent of hash slots (test 364; 10-year data: all 465 rows equal an independent count from statistical_unit)
- [x] #2 A regression test with two units in different hash slots, one of them not existing at either end of a period, gives the same stats_summary as the documented population for that period (test 364)
- [x] #3 The STATBUS-558 change is pushed to master with CI green for the pushed commit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Regression test added (failing on current code): test/sql/364_statbus_563_history_stats_independent_of_hash_slot.sql, expected test/expected/364_statbus_563_history_stats_independent_of_hash_slot.out. Commit ac264f089 (local only, not pushed; fix deferred to STATBUS-558 redesign).

Fixture: legal unit 563000001 (valid 2020-01-01..infinity, 10 employees, exists at both period ends) and 563000002 (valid 2024-01-01..infinity, born 2024-03-01, dead 2024-09-30, 7 employees, exists at neither end of 2024). Different hash slots asserted: 2955 vs 14449.

Observed on current code (test 364 fails): documented population for 2024 = 17 employees / 2 units; statistical_history actual = 10 / 1 (stats_match_documented_population = f); statistical_history_facet actual = 10 / 1 (facet_stats_match_documented_population = f). The expected file pins the correct post-fix values 17 / 2 / t, so the diff shows exactly the mismatch.

Run: ./dev.sh test 364_statbus_563_history_stats_independent_of_hash_slot. Output in tmp/test-563.log.

2026-11-04 owner decision: resolved by STATBUS-558, not fixed separately in today's code. 558 replaces statistical_history_def/statistical_history_facet_def; each unit's stats live on its own delta rows, so no hash-slot dependency. The 558 views already pass test 364 (17 employees / 2 units for 2024; local commits 507156f12, cbc7320b7). Accepted: 558 changes today's numbers where today undercounts (10-year db: 6 of 12 yearly employee cells higher, never lower). Close as Done when STATBUS-558 reaches maturity (merged and verified).

2026-11-06 11:52 Landed in local master 67488988e (fast-forward, owner 11:41: land the whole set, then one release with one full recalculation). Not pushed. Fast suite on that tip 124/124 (tmp/test-stack-fast.log).

2026-11-06 19:15 rebased local master onto origin/master ce9669a78 (after v2026.11.1-rc.17); tip 3e4b68ea6, 80 commits ahead, 0 merges, combined patch identical to before the rebase. Fast suite: all 124 shared + 2 isolated tests pass (tmp/test-rebased-fast.log). Not pushed. Test 364 (two legal units in different hash slots, one existing at neither 2024 end): documented population 17 employees / 2 units; before the fix statistical_history gave 10 / 1 (tmp/test-563.log), now 17 / 2, stats_match_documented_population = t, for both statistical_history and statistical_history_facet. 10-year data: all 465 rows equal an independent count from statistical_unit (tmp/558-onetable/30-10y.log).

2026-11-07 hibiscus: owner 16:09 plan. Local master rebased onto origin 3282c0af7 (97 commits, 0 merges, patch identical) and pushed as branch statbus-history-release for rabbit to cut an RC from. Rabbit owns: RC cut + gate, Norway upgrade (run U), Norway wipe + full import (run B), release if green. Owner's doc/db review of the migrations was not done; owner approved the plan and the push. Ticket goes Done when that release passes (CI green on the released SHA; 558 also needs run U).

2026-11-07 17:02 (rabbit): statbus-history-release 7b171ac1c fast-forwarded onto master and pushed as 72f1d7fd1; CI green for that SHA: Fast Tests 42393130629, Go Test, app build & lint, Harness Selftest 42392507183, Images. Ships in the next RC (rc.23).
<!-- SECTION:NOTES:END -->

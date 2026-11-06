---
id: STATBUS-563
title: >-
  History stats drop a unit unless a unit of its hash slot exists at a period
  end
status: In Progress
assignee: []
created_date: '2026-11-03T22:24:00Z'
updated_date: '2026-11-06T11:52:00Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 486204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
STATBUS-558
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 statistical_history and statistical_history_facet stats_summary equal the documented population for each period, independent of hash slots
- [ ] #2 A regression test with two units in different hash slots, one of them not existing at either end of a period, gives the same stats_summary as the documented population for that period
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Regression test added (failing on current code): test/sql/364_statbus_563_history_stats_independent_of_hash_slot.sql, expected test/expected/364_statbus_563_history_stats_independent_of_hash_slot.out. Commit ac264f089 (local only, not pushed; fix deferred to STATBUS-558 redesign).

Fixture: legal unit 563000001 (valid 2020-01-01..infinity, 10 employees, exists at both period ends) and 563000002 (valid 2024-01-01..infinity, born 2024-03-01, dead 2024-09-30, 7 employees, exists at neither end of 2024). Different hash slots asserted: 2955 vs 14449.

Observed on current code (test 364 fails): documented population for 2024 = 17 employees / 2 units; statistical_history actual = 10 / 1 (stats_match_documented_population = f); statistical_history_facet actual = 10 / 1 (facet_stats_match_documented_population = f). The expected file pins the correct post-fix values 17 / 2 / t, so the diff shows exactly the mismatch.

Run: ./dev.sh test 364_statbus_563_history_stats_independent_of_hash_slot. Output in tmp/test-563.log.

2026-11-04 owner decision: resolved by STATBUS-558, not fixed separately in today's code. 558 replaces statistical_history_def/statistical_history_facet_def; each unit's stats live on its own delta rows, so no hash-slot dependency. The 558 views already pass test 364 (17 employees / 2 units for 2024; local commits 507156f12, cbc7320b7). Accepted: 558 changes today's numbers where today undercounts (10-year db: 6 of 12 yearly employee cells higher, never lower). Close as Done when STATBUS-558 reaches maturity (merged and verified).

2026-11-06 11:52 Landed in local master 67488988e (fast-forward, owner 11:41: land the whole set, then one release with one full recalculation). Not pushed. Fast suite on that tip 124/124 (tmp/test-stack-fast.log).
<!-- SECTION:NOTES:END -->

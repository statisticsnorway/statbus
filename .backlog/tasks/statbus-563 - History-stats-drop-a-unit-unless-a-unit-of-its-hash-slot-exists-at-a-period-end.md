---
id: STATBUS-563
title: >-
  History stats drop a unit unless a unit of its hash slot exists at a period
  end
status: In Progress
assignee: []
created_date: '2026-11-03T22:24:00Z'
updated_date: '2026-11-03T22:30:00Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 486204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
statistical_history_def and statistical_history_facet_def attach stats_summary per (hash_slot[, cell]) via LEFT JOIN onto demographic rows: stats of the latest version overlapping a period count only if some unit in the same hash slot (and, for the facet, the same cell) exists at prev_stop or curr_stop. A unit that does not exist at either end (born mid-period after prev_stop and dead before curr_stop, or whose version overlaps the period before its birth date) is dropped unless an unrelated slot-mate keeps the slot alive. Whether it counts depends on the hash of other units, not on the data. Proven on 10-year Norway (test 402 db): facet 800 cells undercounted (tmp/558-night/03g-slotgate.sql); statistical_history 329 of 447 rows differ from the same rule without the slot gate (tmp/558-shd/03-stats-explain.sql). Found during STATBUS-558; the fix lands with 558's redesign.
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
<!-- SECTION:NOTES:END -->

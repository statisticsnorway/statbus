---
id: STATBUS-538
title: >-
  Full recalculation leaves stale facet staging; reset() keeps
  statistical_unit_facet_staging (demo drilldown 179 vs 91)
status: Done
assignee: []
created_date: '2026-10-30T08:48:00Z'
updated_date: '2026-10-30T10:36:00Z'
labels:
  - derive
  - facets
  - bug
dependencies: []
priority: high
type: bug
ordinal: 464204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Demo 2026-10-30: drilldown showed 179 enterprises in Zambezia (218 total) while statistical_unit had 91 (144 total). Cause: public.reset() truncates statistical_unit_facet and dirty slots but not statistical_unit_facet_staging, so staging rows for pre-reset hash slots (440 slots, 338 phantom enterprises) survived. A full collect_changes (all *_id_ranges NULL) did not repair it: derive_statistical_unit marks only slots of existing units dirty, and derive_statistical_unit_facet / derive_statistical_history / derive_statistical_history_facet choose full rebuild only when their staging is empty. Migrations codified a TRUNCATE-then-spawn workaround (20261008202243, 20260320021106, 20260221095033) and test 346 relies on it. Evidence: dbdumps/demo_20261030_093705.pg_dump, tmp/demo-*.log, tmp/journal.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Regression test fails on current master: import, reset(), import into different hash slots, facets != statistical_unit counts
- [x] #2 Regression test fails on current master: stale staging rows + full collect_changes (NULL ids, -infinity..infinity) with no TRUNCATE leaves facets != truth
- [x] #3 reset() clears statistical_unit_facet_staging (via forward migration)
- [x] #4 Full collect_changes rebuilds every facet/history staging slot and removes stale ones without any caller TRUNCATE
- [x] #5 Test 346 no longer relies on TRUNCATE; asserts facet totals equal statistical_unit counts
- [x] #6 Demo repaired and verified: facet counts equal statistical_unit counts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Demo repaired 2026-10-30 09:48 via tmp/demo-repair.sql (BEGIN; TRUNCATE statistical_unit_facet_staging; worker.spawn collect_changes all-NULL; COMMIT) = the workaround from migration 20261008202243. Task 169302 tree: 14141 completed, 0 failed. tmp/demo-verify.log: facet == statistical_unit per unit_type x region (enterprise 04: 91/91), 0 stale staging rows. Earlier full collect_changes WITHOUT truncate (task 154883, 14406 children, all completed) left facets unchanged (tmp/demo-after.log) - proves the defect.

Fix a09c2d25c (migration 20261030085731). Before fix: tmp/test-355-before-fix.out, facets 14 vs truth 7 after reset+reimport, 28 vs 7 after full collect_changes without TRUNCATE. After: all matches t (test/expected/355). 346 now asserts facet totals = statistical_unit (t); analytics task count 2172->1742 since full refresh spawns wide ranges. ./dev.sh test fast: All 118 tests passed (tmp/test-538-fast.log). doc/db regenerated: 5 function docs, no deletions. Old migrations left unchanged. Pending: CI for a09c2d25c.

CI: Fast Tests run 41040045995 success (pg_regress fast suite) at 8afd44ea9, which contains a09c2d25c. Earlier Fast Tests runs on a09c2d25c..c7ab9a2c8 were cancelled by superseding pushes; Go Test, Images, app build & lint, Harness Selftest succeeded on a09c2d25c itself. Open design follow-up (not blocking): derive full refresh from valid_from=-infinity/valid_until=infinity instead of payload.full_refresh, to keep one source of truth; awaiting user decision.

Upgrade-path verification on real demo data: restored dbdumps/demo_20261030_093705.pg_dump (broken state) into scratch DB statbus_538_verify. Before: enterprise region 04 facet 179 vs truth 91, 721 stale staging rows (tmp/538-verify-before.log). Applied migration 20261030085731 .up.sql as the upgrade would (it re-queued the full collect_changes), ran worker.process_tasks(analytics), no TRUNCATE by caller. After: every region facet == truth (04: 91/91), 0 stale staging rows, 0 failed tasks (tmp/538-verify-after.log). All unit types: facet == countable truth (est 8, lu 113, ent 113); history_facet countable_count 2026 equals the same (exists_count 10/144/144 equals all-units-now). 0 stale history partitions. reset(true,'data') then leaves facet staging empty (tmp/538-verify-all.log). Correction: dashboard 113 was the correct countable count; my earlier '142' was wrong (31 units are not used_for_counting). Scratch DBs dropped.

Demo re-check 10:36: the drilldown RPC statistical_unit_facet_drilldown(enterprise, current_date) returns 02:4, 04:91, 08:8, 09:2, 11:6 (tmp/demo-drilldown-rpc.log), previously 8/179/16/4/11. Facet==truth per region, 0 stale staging rows, 0 stale history partitions, history countable 2026 = 113/113/8. Demo UI not viewed (login required in agent browser).
<!-- SECTION:NOTES:END -->

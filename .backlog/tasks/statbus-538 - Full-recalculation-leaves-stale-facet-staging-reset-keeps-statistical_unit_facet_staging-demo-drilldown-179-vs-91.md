---
id: STATBUS-538
title: >-
  Full recalculation leaves stale facet staging; reset() keeps
  statistical_unit_facet_staging (demo drilldown 179 vs 91)
status: In Progress
assignee: []
created_date: '2026-10-30T08:48:00Z'
updated_date: '2026-10-30T08:53:00Z'
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
- [ ] #1 Regression test fails on current master: import, reset(), import into different hash slots, facets != statistical_unit counts
- [ ] #2 Regression test fails on current master: stale staging rows + full collect_changes (NULL ids, -infinity..infinity) with no TRUNCATE leaves facets != truth
- [ ] #3 reset() clears statistical_unit_facet_staging (via forward migration)
- [ ] #4 Full collect_changes rebuilds every facet/history staging slot and removes stale ones without any caller TRUNCATE
- [ ] #5 Test 346 no longer relies on TRUNCATE; asserts facet totals equal statistical_unit counts
- [x] #6 Demo repaired and verified: facet counts equal statistical_unit counts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Demo repaired 2026-10-30 09:48 via tmp/demo-repair.sql (BEGIN; TRUNCATE statistical_unit_facet_staging; worker.spawn collect_changes all-NULL; COMMIT) = the workaround from migration 20261008202243. Task 169302 tree: 14141 completed, 0 failed. tmp/demo-verify.log: facet == statistical_unit per unit_type x region (enterprise 04: 91/91), 0 stale staging rows. Earlier full collect_changes WITHOUT truncate (task 154883, 14406 children, all completed) left facets unchanged (tmp/demo-after.log) - proves the defect.
<!-- SECTION:NOTES:END -->

---
id: STATBUS-124
title: 'power-group-substrate: 0-index power_level ripple (DRAFT-001 build body 1)'
status: In Progress
assignee:
  - architect
  - tester
created_date: '2026-07-02 18:03'
updated_date: '2026-07-02 19:23'
labels:
  - power-group
  - api
  - hierarchy
dependencies: []
references:
  - DRAFT-001
  - doc/power-groups.md
  - test/sql/117_power_group.sql
  - test/sql/118_power_group_hierarchy.sql
  - test/sql/120_power_group_lifecycle.sql
priority: medium
ordinal: 124000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
First build body of the power-group-reporting design — **DRAFT-001 is the authoritative design** (contract, locked decisions, grounding); this task carries only its substrate slice: re-base `power_level` to 0-indexed (root=0) everywhere, per locked decision #1.

The ripple (from DRAFT-001's implementation plan):
- `import.process_power_group_link`: BFS seed level 1→0 (root=0); children = parent_level+1.
- `power_group_membership` view: root rows level 1→0.
- `power_group_def`: `depth = max(power_level)` (drop the −1).
- Tests 117/118/120: re-assert 0-based levels.
- `doc/power-groups.md`: re-number scenarios to 0-base.

Migration discipline: dump current definitions first (`\sf`), surgical edits, up+down migrations. This slice has NO hierarchy/API changes — those are the second build body, which depends on this landing first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 import.process_power_group_link BFS seeds root at level 0; children = parent+1
- [ ] #2 power_group_membership view reports root rows at power_level 0
- [ ] #3 power_group_def.depth = max(power_level) with the -1 removed; depth/width/reach values unchanged vs today's semantics
- [ ] #4 tests 117/118/120 assert 0-based levels and pass; expected .out blessed by intent (no blind re-baseline)
- [ ] #5 doc/power-groups.md scenarios re-numbered to 0-base
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-02 19:23
---
RIPPLE LIST — ACTUAL (6 objects, was listed as 3). The task/DRAFT-001 ripple list under-counted; the pg_regress full-diff review caught 3 more objects that select the root LU via `power_level = 1` (test-to-know — the 120 power_group-NAME flip Corp→Sub was the tell). All in migration 20260702185257_power_group_0index_power_level_statbus_124:

OBJECTS RE-BASED (root 1→0 everywhere):
1. import.process_power_group_link — BFS seed 1→0 + `_iter := -1` frontier fix.
2. power_group_membership (view) — root rows `1 AS power_level` → `0`.
3. power_group_def (view) — `depth = max(power_level)` (drop -1); width filter `power_level = 2` → `1`. depth/width/reach VALUES unchanged (AC#3).
4. timeline_power_group_def (view) :186 — root selector `power_level = 1` → `0` (the power_group NAME source in statistical_unit). [MISSED by the list]
5. statistical_unit_enterprise_id (function) :59 — root selector `power_level = 1` → `0` (+ comment). [MISSED]
6. timeline_power_group_refresh (function) :131 — root selector `power_level = 1` → `0`. [MISSED]

PLUS: stored-level data re-base `UPDATE legal_relationship SET derived_influenced_power_level = derived_influenced_power_level - 1` (uniform, for live-DB upgrade consistency; blast radius verified contained via pg_depend — only power_group_membership + the sql_saga passthrough view read it). Tests 117/118/120 predicates re-based (root selector `= 1`→`= 0`). doc/power-groups.md scenarios re-based to 0.

BLAST RADIUS (foreman req#2): the 3 added objects appear in test/expected/ ONLY in 2 performance baselines (.perf — plan snapshots, unaffected by a predicate-value swap). 119_roller_data_power_groups references power_group_membership but selects ident/name/count (NOT power_level/derived-levels/timeline-name) → INVARIANT (tester confirming). So 117/118/120 is the complete correctness blast radius. Keep-in-124 approved by foreman (substrate root-selectors, not 125's hierarchy rework). Commit HELD for foreman review.
---
<!-- COMMENTS:END -->

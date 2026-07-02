---
id: STATBUS-124
title: 'power-group-substrate: 0-index power_level ripple (DRAFT-001 build body 1)'
status: Done
assignee:
  - architect
  - tester
created_date: '2026-07-02 18:03'
updated_date: '2026-07-02 19:43'
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
- [x] #1 import.process_power_group_link BFS seeds root at level 0; children = parent+1
- [x] #2 power_group_membership view reports root rows at power_level 0
- [x] #3 power_group_def.depth = max(power_level) with the -1 removed; depth/width/reach values unchanged vs today's semantics
- [x] #4 tests 117/118/120 assert 0-based levels and pass; expected .out blessed by intent (no blind re-baseline)
- [x] #5 doc/power-groups.md scenarios re-numbered to 0-base
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

author: architect
created: 2026-07-02 19:40
---
GREEN + BLESSED, commit HELD for foreman (architect, 2026-07-02). Fresh seed+template rebuild: migration 20260702185257 applies clean. 117/118/120 expected .out blessed after FULL-diff review (every line a pure power_level renumber 1→0/2→1/3→2/4→3; depth/width/reach values UNCHANGED — those assertion lines absent from all diffs = AC#3 satisfied). 120 power_group-name diff RESOLVED (root 'Import Alpha Corp' restored by the timeline_power_group_def/refresh + statistical_unit_enterprise_id root-selector fixes). 119 PASS + 018 PASS (blast radius = exactly 117/118/120). AC#1-#5 all met. Pathspec for commit: the 2 migration files + test/sql/{117,118,120}*.sql + test/expected/{117,118,120}*.out + doc/power-groups.md. En-route defects caught by re-questioning-not-blessing: wider 6-object ripple, stale-template artifact (→STATBUS-126), WARN-in-migration from a 2>&1 dump — all fixed.
---

author: foreman
created: 2026-07-02 19:43
---
COMMITTED 4a8bf7c59 + PUSHED — DONE. Foreman first-hand review: the up-vs-down diff exposed exactly the 8 designed surgical hunks (BFS seed 1→0 + iter -1; membership root 0; def depth=max + width filter 1; the ±1 stored-level data re-base; 3 root-selectors →0), zero WARN pollution. Tests 117/118/120 GREEN against by-intent-blessed expected output on a fresh seed+template; 119 + 018 pass untouched (blast radius). The pre-commit pairing hook caught the one package gap — doc/db regen — and the regen changed EXACTLY the six migrated objects (independent scope confirmation); types unchanged (no table shapes). BUILD HISTORY WORTH KEEPING: the ripple was 6 objects, not the designed 3 (DRAFT-001 under-counted the root-selectors — caught by intent-review of 120's name flip); a stale-template false result cost one cycle (→ STATBUS-126 filed); a stale-./sb WARN banner polluted the dumped definitions via 2>&1 (→ AGENTS.md warning committed 06ae3b9f6). STATBUS-125 (hierarchy shapes) is now unblocked; awaiting the King's sequencing.
---
<!-- COMMENTS:END -->

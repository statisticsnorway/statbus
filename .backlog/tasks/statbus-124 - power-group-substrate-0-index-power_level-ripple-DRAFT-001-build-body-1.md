---
id: STATBUS-124
title: 'power-group-substrate: 0-index power_level ripple (DRAFT-001 build body 1)'
status: In Progress
assignee:
  - architect
created_date: '2026-07-02 18:03'
updated_date: '2026-07-02 18:49'
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

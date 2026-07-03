---
id: STATBUS-120
title: >-
  pg-multi-control-test: investigate & add import test for multiple controlling
  relationships
status: To Do
assignee: []
created_date: '2026-06-30 12:40'
updated_date: '2026-07-03 10:45'
labels:
  - import
  - not-install-upgrade
dependencies: []
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Suspected GAP in test coverage: importing MULTIPLE control units / controlling relationships into a power group. The King flagged this while finalizing the power-group reporting design (see DRAFT-001 / `doc/power-groups.md`).

Existing coverage (test/sql/): 117 power_group_fundamentals, 118 worker_derivation, 119 roller_data, 120 lifecycle (incl. cycle + multi-root), 121 worker_info/ordering. Suspected uncovered: importing several *controlling* (primary) relationships in a way that exercises —
- a single influenced unit targeted by TWO would-be primary controllers of the same type → the exclusion constraint `legal_relationship_influenced_primary_excl` must reject the second;
- multiple control edges arriving in one import batch and the holistic `analyse_power_group_link` / `process_power_group_link` derivation under that load;
- multi-root formation via control (two roots merged), distinct from the percentage-driven path.

INVESTIGATE the precise gap first (don't assume), then add the missing pg_regress test(s). This is import/derivation coverage — separate from the reporting-API work in DRAFT-001.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Identify the specific uncovered scenario(s) for importing multiple controlling relationships (confirm the gap against tests 117-121 before writing)
- [ ] #2 Add pg_regress test(s) covering import of multiple control relationships into a power group
- [ ] #3 Assert exclusion-constraint behavior (<=1 primary influencer per influenced unit per type) and the process_power_group_link derivation outcome
- [ ] #4 Expected .out blessed and the test passes under ./dev.sh test
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-02 18:13
---
DISPATCH-CLARITY NOTE (foreman, 2026-07-02): before relying on the 'existing coverage' list in the description, verify the actual test-file names first-hand (`ls test/sql/ | grep -iE 'power|legal_rel'`) — the 117-121 subject labels above were written from memory in another working copy and may not match the files exactly (e.g. 118 is described elsewhere as power_group_hierarchy). The INVESTIGATE-first instruction (criterion 1) covers this: confirm the real gap against the real files before writing any test.
---
<!-- COMMENTS:END -->

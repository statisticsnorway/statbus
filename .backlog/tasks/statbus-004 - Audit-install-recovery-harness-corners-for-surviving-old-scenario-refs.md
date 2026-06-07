---
id: STATBUS-004
title: Audit install-recovery harness corners for surviving old scenario refs
status: In Progress
assignee: []
created_date: '2026-06-07 11:25'
updated_date: '2026-06-07 11:50'
labels:
  - install-recovery
  - rename
  - review
dependencies: []
references:
  - test/install-recovery/lib/
  - test/install-recovery/fixtures/
priority: medium
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Corner-audit complementing the main rename review: check the harness support files the main sweep may have under-covered — test/install-recovery/lib/*.sh, fixtures/* (filenames AND contents), and any other *.sh/*.md under test/install-recovery/ — for any surviving old NN-scenario reference, old slug, or statbus-recovery-NN VM name. Then confirm the runner lists exactly the canonical set.

Read-only + --list only; do NOT run any paid VM scenario. Dispatched last session but never reported before the crash. Recovered from harness task #44.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 lib/, fixtures/, and other harness files audited; defects reported as file:line or confirmed clean
- [ ] #2 `./dev.sh test-install-recovery --list` shows exactly the 28 canonical names with no number-prefixed survivors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Content audit CLEAN (2026-06-07): no surviving old numeric refs in test/install-recovery/lib/ or fixtures/ (filenames or contents). Corroborated by the broad 003 sweep over test/, which found ZERO old refs inside test/install-recovery/. The rename's real misses were OUTSIDE this task's scope — dev.sh (repo root) + doc/release-workflow-gates.md (active doc) — both caught by STATBUS-003 and fixed. AC#2 (--list = 28 canonical) running in background.
<!-- SECTION:NOTES:END -->

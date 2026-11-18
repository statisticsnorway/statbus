---
id: "rdhhq7"
title: Audit install-recovery harness corners for surviving old scenario refs
state: "done"
assignee: []
updated_date: '2026-06-07 11:52'
labels:
  - install-recovery
  - rename
  - review
group: ""
rank: "000000000049"
dependencies: []
references:
  - test/install-recovery/lib/
  - test/install-recovery/fixtures/
priority: medium
origin: "backlog:STATBUS-004"
aliases: ["STATBUS-004"]
type: "feature"
created: "2026-06-07 11:25"
updated: "2026-06-07 11:52"
---

## Goal

Corner-audit complementing the main rename review: check the harness support files the main sweep may have under-covered — test/install-recovery/lib/*.sh, fixtures/* (filenames AND contents), and any other *.sh/*.md under test/install-recovery/ — for any surviving old NN-scenario reference, old slug, or statbus-recovery-NN VM name. Then confirm the runner lists exactly the canonical set.

Read-only + --list only; do NOT run any paid VM scenario. Dispatched last session but never reported before the crash. Recovered from harness task #44.

## Acceptance
- [x] #1 lib/, fixtures/, and other harness files audited; defects reported as file:line or confirmed clean
- [x] #2 `./dev.sh test-install-recovery --list` shows exactly the 28 canonical names with no number-prefixed survivors

## Implementation Notes

Content audit CLEAN (2026-06-07): no surviving old numeric refs in test/install-recovery/lib/ or fixtures/ (filenames or contents). Corroborated by the broad 003 sweep over test/, which found ZERO old refs inside test/install-recovery/. The rename's real misses were OUTSIDE this task's scope — dev.sh (repo root) + doc/release-workflow-gates.md (active doc) — both caught by STATBUS-003 and fixed. AC#2 (--list = 28 canonical) running in background.

AC#2 confirmed (2026-06-07): `./dev.sh test-install-recovery --list` prints exactly 28 canonical phase-prefixed scenarios, no number-prefixed survivors (tmp/list-check.log). Corner-audit verdict: CLEAN. The rename's only real misses were dev.sh + doc/release-workflow-gates.md — outside this task's scope, caught and fixed under STATBUS-003.

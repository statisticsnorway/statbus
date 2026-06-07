---
id: STATBUS-003
title: Review the install-recovery scenario-slug rename for consistency + correctness
status: To Do
assignee: []
created_date: '2026-06-07 11:25'
labels:
  - install-recovery
  - rename
  - review
dependencies: []
references:
  - test/install-recovery/scenarios/
  - test/install-recovery/README.md
  - test/install-recovery/run.sh
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The install-recovery scenarios were renamed from NN-slug to <phase>-<slug> (phases: 0/1-boot/2-preswap/3-postswap/4-rollback/5-install). The file renames are committed; the content-canonicalization sweep (~42 working-tree files: README, run.sh, in-file headers, diagrams, a few cli/ comments) is held UNCOMMITTED pending this review. The review was dispatched in the prior session but never reported before the crash, so re-run it. Once it (and the corner-audit + grip-map) pass, the held sweep gets committed.

Recovered from harness task #42.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No surviving old scenario identifier (NN-prefix, old slug, statbus-recovery-NN) anywhere it matters, verified by grep
- [ ] #2 5 representative slugs each resolve across filename, runner, README, diagram, and in-file header
- [ ] #3 Verdict reported: APPROVE, or a defect list with file:line
<!-- AC:END -->

---
id: STATBUS-211
title: >-
  crollback-fixed-seed-build: the fixed-fixture branch's seed image build dies
  on the deliberately-failing migration it was supposed to fix
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-16 22:30'
updated_date: '2026-08-16 22:34'
labels:
  - install-recovery
  - release
dependencies: []
references:
  - .github/workflows/upgrade-arc-harness.yaml
  - test/install-recovery/arcs/c-rollback-resurrection-arc.sh
  - .github/workflows/images.yaml
priority: high
ordinal: 211000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every fixture branch the arc construct step creates yields a buildable seed image; the "fixed" branch of the c-rollback lineage migrates clean by definition (it IS the fix release).
> FOUND: overnight arc triage 2026-08-17, rc.01 fleet. Images run 31970569830 (workflow_dispatch on test/upgrade-arc-crollback-fixed-migration-31970534502) FAILED in the seed-builder stage: `migrate seed db up: migration 20260714100530 (20260714100530_upgrade_arc_3.up.sql) failed: exit status 3 — ERROR: upgrade-arc failing fixture: deliberate migration failure (STATBUS-071 d)`. The sibling fixture branches (crollback-migration, codeonly, healthpark, healthpark-fixed) all built green in the same window.

THE CONTRADICTION: the crollback-FIXED branch is the fix release for the C-class rollback lineage — its defining property is that the deliberately-failing migration is repaired/replaced. Its seed build dying on exactly that deliberate failure means either (a) the construct step failed to actually fix/replace upgrade_arc_3 on that branch (construct defect), or (b) the crollback-fixed lineage intentionally keeps the failing migration at some position and the seed builder should not run (or should skip) for this fixture class (seed-build/fixture interaction defect). Determine which from the construct step's code (upgrade-arc-harness.yaml construct job + its fixture scripts) and the branch's actual bytes (the test/* branches are torn down post-run — reconstruct via the construct code, or from the next run's branches).

CONSUMER IMPACT: c-rollback-resurrection consumes CROLLBACK_C — this run it died on capacity (208) before pulling the image, so the missing image was masked. At rc.02, with capacity fixed, c-rollback-resurrection (and any other CROLLBACK_C consumer, e.g. arcs whose lineage displaces C) will hit this deterministically unless fixed first. Cross-check: was this image build green at the last full-suite arc success (2026-07-28 run 30372633117)? If yes, find what changed since (seed-builder behavior, construct, or migration numbering).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cause established from construct code + branch bytes: construct defect vs seed-build/fixture-class interaction, with the July-28 green cross-check answered
- [ ] #2 Fix architect-ruled and landed: the crollback-fixed branch's seed image builds green (or the seed build correctly skips the fixture class, ruled deliberately)
- [ ] #3 c-rollback-resurrection green at an RC tag
<!-- AC:END -->

---
id: STATBUS-165
title: >-
  arc-branch-retention: cleanup policy for test/upgrade-arc-* throwaway branches
  (~100 accumulated on origin)
status: To Do
assignee: []
created_date: '2026-07-12 14:54'
labels:
  - git-hygiene
  - not-install-upgrade
dependencies: []
priority: low
ordinal: 166000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every visible branch is live (same star as STATBUS-035).
> BENEFIT: ~100 dead throwaway branches stop drowning `git ls-remote` / branch listings and stop inviting wasted investigation.
> STAGE: Hygiene.
> COMPLEXITY: one architect ruling (retention rule) + one small framework change + one sweep.
> DEPENDS ON: STATBUS-071 (the framework that creates them).

GROUND TRUTH (git ls-remote --heads origin, 2026-07-12): ~100 branches matching `test/upgrade-arc-*-migration-<runid>` plus `red/031-rollback-watchdog`. These are the STATBUS-071 real-upgrade-arc framework's throwaway branches — one pushed per run so CI builds a per-commit image, then never deleted. No retention policy exists.

Shape of the fix (architect to rule the exact rule):
1. The framework deletes its own branch at end-of-run (green or red) once the image digest is recorded — the branch's only job is to trigger the per-commit image build; the COMMIT is authoritative (source-version-authority), the branch is just a trigger.
2. A one-time sweep deletes the ~100 accumulated (verify none is referenced by an open run first).
3. `red/031-rollback-watchdog` gets one owner answer (likely folds into the STATBUS-035 keep-pending walk).

Constraint: never-delete set (master, 11 deploy pointers, db-seed) untouched, as in STATBUS-035.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect rules the retention mechanism (self-delete at end-of-run vs TTL sweep) and where it lives in the 071 framework
- [ ] #2 Framework change shipped: new arc runs leave no branch behind after the image digest is recorded
- [ ] #3 One-time sweep executed: accumulated test/upgrade-arc-* branches deleted, never-delete set verified intact before and after
- [ ] #4 red/031-rollback-watchdog routed to its owner for one answer
<!-- AC:END -->

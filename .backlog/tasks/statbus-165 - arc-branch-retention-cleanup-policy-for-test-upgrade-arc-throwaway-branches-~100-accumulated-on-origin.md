---
id: STATBUS-165
title: >-
  arc-branch-retention: cleanup policy for test/upgrade-arc-* throwaway branches
  (~100 accumulated on origin)
status: To Do
assignee: []
created_date: '2026-07-12 14:54'
updated_date: '2026-07-12 21:41'
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
- [x] #1 Architect rules the retention mechanism (self-delete at end-of-run vs TTL sweep) and where it lives in the 071 framework
- [ ] #2 Framework change shipped: new arc runs leave no branch behind after the image digest is recorded
- [ ] #3 One-time sweep executed: accumulated test/upgrade-arc-* branches deleted, never-delete set verified intact before and after
- [ ] #4 red/031-rollback-watchdog routed to its owner for one answer
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (relayed by foreman)
created: 2026-07-12 21:41
---
AC#1 RULED (architect, 2026-07-12 night), with two ground-truth corrections to this ticket's framing:

CORRECTION 1 — CI already self-deletes: upgrade-arc-harness.yaml's teardown job (:572-596, if: always()) deletes both test/* branches, recomputing names from run_id so it survives partial failures. The ~100 accumulated branches are the GAPS: runs predating the teardown job, LOCAL harness runs (upgrade-target.sh:484 pushes, nothing local deletes), and teardown misses (cancelled pre-teardown, runner death, local ctrl-C).

CORRECTION 2 — this ticket's "delete once the image digest is recorded" is TOO EARLY: the branch's second job is keeping the commit FETCHABLE — the 082 install.sh --commit path runs `git fetch origin <sha>` on the VMs mid-run, and GitHub only reliably serves fetch-by-SHA for ref-reachable commits. Correct timing = END-OF-RUN (teardown), which CI already does.

THE RULED MECHANISM: (1) PRIMARY — end-of-run self-delete, already shipped in CI; the framework change is extending it to the LOCAL path: delete_throwaway_branches() helper in upgrade-target.sh beside the :484 push (same recompute-from-run-id shape as CI teardown, ARC_NO_PUSH-guarded symmetrically), called from the local harness exit trap. (2) BACKSTOP — a branch-GC step in the EXISTING weekly image-cleanup.yaml (which already owns arc-artifact GC by design): delete test/upgrade-arc-* branches older than 7 days; 7d >> any run duration so age alone suffices, no run-state check; the pattern can never match the never-delete set by construction. (3) ONE-TIME SWEEP — the backstop's own logic run once, dry-run listing first, never-delete set verified before and after. (4) red/031-rollback-watchdog → the STATBUS-035 keep-pending owner walk. Insertion points: upgrade-target.sh:~484, .github/workflows/image-cleanup.yaml; CI teardown untouched.
---
<!-- COMMENTS:END -->

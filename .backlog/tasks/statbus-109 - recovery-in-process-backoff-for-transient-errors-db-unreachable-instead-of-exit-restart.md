---
id: STATBUS-109
title: >-
  recovery: in-process backoff for transient errors (db-unreachable) instead of
  exit-restart
status: To Do
assignee: []
created_date: '2026-06-24 12:21'
updated_date: '2026-06-24 14:13'
labels:
  - upgrade
  - recovery
  - reliability
dependencies: []
references:
  - doc/upgrade-vocabulary.md
  - cli/internal/upgrade/service.go
  - STATBUS-107
  - STATBUS-071
priority: medium
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why
Surfaced during the upgrade-vocabulary walkthrough (STATBUS-107). The recovery decision tree's "cannot verify" outcome (GroundTruthUnknown) currently EXITS the process on a TRANSIENT db-unreachable error and leans on systemd restart as its retry. That is noisy and risks a false unit-failure for a brief db blip. King's framing (2026-06-24): "To exit for a transient error creates noise."

## Sort recovery error outcomes by STRATEGY (King)
1. TRANSIENT → name it + an in-process strategy (exponential backoff, max N); exit only if the budget exhausts. → db-unreachable (db mid-restart; resolves in seconds).
2. NON-TRANSIENT, recoverable → name it + run the known recovery. → completed-migrations (finish) / pending-migrations (roll back) / old-sb-never-swapped (restart old).
3. NON-TRANSIENT, can't self-heal → name it, recovery = stop for a human. → git target-not-in-clone (a relaunch won't deepen a shallow clone).
4. CAN'T name it → stop for a human. → unrecognized phase (FLAG_PHASE_UNKNOWN).

## Current behavior (grounded, file:line)
- verifyUpgradeGroundTruthEx (service.go:2105-2141) returns GroundTruthUnknown when: db.migration query fails (db unreachable, :2118-2125) OR git can't resolve the target commit (shallow/pruned clone, :2042-2048).
- recovery-Unknown → record failure (row stays in_progress, error logged) → return error → Service.Run returns at service.go:1705-1706 → PROCESS EXITS → systemd restarts the unit (RestartSec delay + StartLimit ~10/600s cap per the :1702 comment) → fresh recoverFromFlag re-checks. NO in-process backoff. Same exit path for both the db (transient) and git-shallow (persistent) sub-causes.

## Proposed
- TRANSIENT db-unreachable during recovery: retry the ground-truth check IN-PROCESS with exponential backoff + max-N (sized to the container-restart window), updating the row error quietly; reserve process-exit for genuinely unreconcilable states (buckets 3/4).
- git-shallow / target-not-in-clone (persistent): fail loud immediately rather than thrash to StartLimit.
- Verify the systemd RestartSec/StartLimit values (ops/ unit files) to quantify the current noise/false-failure window.

## Must be arc-tested
Changes safety-critical recovery behavior — prove via the install-recovery arcs (STATBUS-071). The test run is the only oracle on the upgrade system. Coordinate with the parked byte/clean-restart decision (also arc-gated).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Transient db-unreachable during recovery retries in-process with exponential backoff + max-N and does NOT exit the process within the budget — proven by an install-recovery arc that kills the db transiently mid-recovery
- [ ] #2 git-shallow / target-not-in-clone fails loud immediately (does not thrash systemd restarts to the StartLimit cap)
- [ ] #3 process-exit + systemd restart is reserved for genuinely unreconcilable recovery states (buckets 3 & 4), not transient ones
- [ ] #4 systemd RestartSec/StartLimit values documented and shown to bound the worst case
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CORRECTION (King, 2026-06-24): git-shallow / target-not-in-clone is NOT 'fail loud immediately' — AC#2 superseded. A shallow clone CAN `git fetch --deepen` / `fetch <sha>` to acquire the missing commit. So it is an ACQUIRE-AND-RETRY case (bucket 1), the same shape as db-retry: acquire the missing dependency (db: wait/retry the connection; commit: fetch it), re-check, and escalate to a human ONLY on exhaustion (db never returns / fetch can't reach the remote). Unify the design as 'acquire-and-retry' strategies. The ONLY direct-to-human case is the truly-unnameable (unrecognized phase) — nothing to acquire. NB: git-shallow is a defensive EDGE (SSB deploys normally have complete clones), so the db case is the one that matters in practice.
<!-- SECTION:NOTES:END -->

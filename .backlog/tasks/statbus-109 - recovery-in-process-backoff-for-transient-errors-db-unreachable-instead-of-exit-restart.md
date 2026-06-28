---
id: STATBUS-109
title: >-
  recovery: in-process backoff for transient errors (db-unreachable) instead of
  exit-restart
status: To Do
assignee: []
created_date: '2026-06-24 12:21'
updated_date: '2026-06-28 12:44'
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
- [ ] #1 Intermittent recovery errors retry IN-PROCESS via `backoff-retry` (exhaust → roll-back), proven by an install-recovery arc that kills the DB transiently mid-recovery (db-unreachable)
- [ ] #2 `commit-not-fetched` retries `git fetch` with backoff, aborting one attempt on a STALL (no-progress ~60s) — never a wall-clock deadline that would cancel a healthy in-progress transfer; exhaust → roll-back
- [ ] #3 Two curated lists exist: known-intermittent → retry, known-persistent → roll-back; anything on neither is unknown → stop (safe-by-default, no blind retry counts)
- [ ] #4 The in-process retry sits in front of the systemd-StartLimit backstop — an exhausted known transient rolls back (never falls through to restart-until-stuck); the systemd backstop is reached only for the unknown stop; systemd RestartSec/StartLimit documented
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CORRECTION (King, 2026-06-24): git-shallow / target-not-in-clone is NOT 'fail loud immediately' — AC#2 superseded. A shallow clone CAN `git fetch --deepen` / `fetch <sha>` to acquire the missing commit. So it is an ACQUIRE-AND-RETRY case (bucket 1), the same shape as db-retry: acquire the missing dependency (db: wait/retry the connection; commit: fetch it), re-check, and escalate to a human ONLY on exhaustion (db never returns / fetch can't reach the remote). Unify the design as 'acquire-and-retry' strategies. The ONLY direct-to-human case is the truly-unnameable (unrecognized phase) — nothing to acquire. NB: git-shallow is a defensive EDGE (SSB deploys normally have complete clones), so the db case is the one that matters in practice.

COMPOSITION with STATBUS-110 (2026-06-26): 109 (quiet in-process transient retry) + 110 (DB read-only window → rollback always data-safe) together REPLACE the conservative 'can't-verify → hold → human' branch. Target recovery model: transient → quiet retry (109); can't-go-forward → safe rollback (110); unnameable → human. 109's value stands alone (kills the exit-restart noise) AND composes into the simplified model. Sequence: 110's direction is ratified by the King first (it sets whether the hold-branch dissolves); 109 lands either way.

ERROR-CLASSIFICATION FRAMEWORK (King-ratified 2026-06-27 — REPLACES the blind-retry-N idea). Don't retry an error you can't name. Classify each forward-step failure: (a) KNOWN-INTERMITTENT (curated list: DB blip, connection reset, container-not-ready) → backoff-retry (1s→30s, ~DB-restart window, IN-PROCESS, heartbeating); if it EXHAUSTS → no longer transient → roll back. (b) KNOWN-PERSISTENT (curated list: 'relation already exists', constraint violation, deterministic) → roll back, ZERO retries. (c) UNKNOWN (matches neither list) → STOP for a human (don't retry=might spin; don't roll back=might be wrong for an error we don't understand). DEFAULT = unknown→stop = SAFE-BY-DEFAULT. The LOAD-BEARING work = curating the two lists. No spin: only retry what's known-transient; a deterministic failure rolls back on first look; an unrecognized one stops. Full target model: doc-019. Composes with STATBUS-110 (read-only makes the rollback data-safe).

CRYSTALLISED (King, 2026-06-27) — final error-classification + backoff design, now in doc/upgrade-vocabulary.md ('Recovery — when a step fails') + doc-019 §3.

ONE strategy `backoff-retry` (in-process, heartbeating); TWO intermittent cases, parameters + FAILURE-DETECTION tuned per probe:
• `db-unreachable` — probe = connect + trivial query; per-try fails on wall-clock 5s (quick check, never a transfer); gap 1s→2s→4s→8s→16s→30s cap; ~5 min budget (~12 tries).
• `commit-not-fetched` — probe = one `git fetch`; per-try fails on a STALL (no progress ~60s, git low-speed) — NOT a wall-clock deadline (King's correction: a deadline would cancel a healthy slow transfer); gap 10s→30s→60s; ~15 min overall budget.
• container-not-ready / health checks (waitForDBHealth exec.go:1164, waitForRestReady exec.go:1397, health-RPC service.go:4809) ALREADY self-wait→rollback; NOT on this new path.

CLASSES: intermittent→backoff-retry (exhaust→roll-back); persistent→roll-back (0 retries); unknown→stop for a human. Default unknown→stop (safe-by-default); load-bearing work = curating the 2 lists.

COMPOSITION (mechanic-grounded vs code): the in-process backoff is NEW — today these exit→systemd@:1705; retryBackoff (service.go:84-93) is scoped to terminal-writes only. It sits IN FRONT of the systemd-StartLimit backstop: known-transient EXHAUST→roll back (data-safe via 110); the systemd backstop is reserved for the UNKNOWN stop only. An exhausted known transient must NEVER fall through to the old restart-until-stuck spin (the dissolved case-9).

Numbers build/test-reconcilable (arcs, STATBUS-071); SHAPE (retry-with-backoff, stall-not-deadline for transfers, exhaust→roll-back, unknown→stop) is fixed. Grounding: tmp/mechanic-transient-errors.md. Build gated on King's GO + arcs.
<!-- SECTION:NOTES:END -->

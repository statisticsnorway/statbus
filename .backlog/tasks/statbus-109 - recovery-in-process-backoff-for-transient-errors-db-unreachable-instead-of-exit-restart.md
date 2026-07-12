---
id: STATBUS-109
title: >-
  recovery: in-process backoff for transient errors (db-unreachable) instead of
  exit-restart
status: In Progress
assignee:
  - engineer
created_date: '2026-06-24 12:21'
updated_date: '2026-07-06 16:05'
labels:
  - upgrade
  - recovery
  - reliability
dependencies:
  - STATBUS-071
references:
  - doc/upgrade-vocabulary.md
  - cli/internal/upgrade/service.go
  - STATBUS-107
  - STATBUS-071
documentation:
  - >-
    doc-022 -
    In-process-backoff-retry-for-recovery-—-detailed-design-STATBUS-109.md
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a transient blip (DB restarting mid-recovery) is retried quietly in-process — never exit-restart noise or a false unit failure.
> BENEFIT: a brief DB hiccup during recovery no longer risks marching a healthy box toward StartLimit, and the operator's journal stops filling with restart noise that hides real signals. Code shipped (782ca2455); this ticket's remaining gain is the PROOF.
> STAGE: Stage 1.
> COMPLEXITY: engineer-substantial (two dedicated arc scenarios: kill the DB transiently mid-recovery; a stalled fetch); the VM run is the oracle.
> DEPENDS ON: STATBUS-071 (the scenarios ride its arc lane).

---

> WHERE THIS STANDS (2026-07-12): the backoff-retry dispatch described as "Proposed" below is SHIPPED (782ca2455, comment #2) and the standard arc paths (working/failing) already pass through it clean (comment #3). The "Current behavior" and "Proposed" sections below describe the OLD exit-on-unknown design this replaced — read them as the original problem statement, not as what the code does today; the live dispatch now lives at recoverFromFlag (service.go:891, drifting — re-verify at build time). What's actually left: AC#1-#4, all gated on two DEDICATED arc scenarios (kill the DB transiently mid-recovery; a commit-not-fetched stall) that no existing arc exercises yet.

## Why
Surfaced during the upgrade-vocabulary walkthrough (STATBUS-107). The recovery decision tree's "cannot verify" outcome (GroundTruthUnknown) currently EXITS the process on a TRANSIENT db-unreachable error and leans on systemd restart as its retry. That is noisy and risks a false unit-failure for a brief db blip. King's framing (2026-06-24): "To exit for a transient error creates noise."

## Sort recovery error outcomes by STRATEGY (King)
1. TRANSIENT → name it + an in-process strategy (exponential backoff, max N); exit only if the budget exhausts. → db-unreachable (db mid-restart; resolves in seconds).
2. NON-TRANSIENT, recoverable → name it + run the known recovery. → completed-migrations (finish) / pending-migrations (roll back) / old-sb-never-swapped (restart old).
3. NON-TRANSIENT, can't self-heal → name it, recovery = stop for a human. → git target-not-in-clone (a relaunch won't deepen a shallow clone).
4. CAN'T name it → stop for a human. → unrecognized phase (FLAG_PHASE_UNKNOWN).

## Current behavior (grounded, file:line)
- [HISTORICAL — pre-782ca2455] verifyUpgradeGroundTruthEx (renamed to verifyUpgradeObservedStateEx, now service.go:2463) used to return GroundTruthUnknown when: db.migration query fails (db unreachable) OR git can't resolve the target commit (shallow/pruned clone).
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-02 17:55
---
DETAILED DESIGN LANDED → doc-022 (architect, 2026-07-02). Same treatment 110 got. All cites verified first-hand vs master HEAD.

SINGLE insertion point: recoverFromFlag FlagPhaseResuming branch (service.go:867–892) — the only place GroundTruthUnknown is produced. Two sub-causes already distinguished in verifyUpgradeGroundTruthEx: db-unreachable (:2151) + commit-not-fetched (:2071); a 3rd merge-base failure (:2075) = unrecognised→stop.

DESIGN CORE: (1) type the Unknown cause (UnknownCause enum = the curated intermittent list; reach-for-types, no string-matching); (2) ONE backoffRetry(retrySpec) helper, per-case probe+failure-detection (db=connect+SELECT1, 5s wall-clock, 1→30s gaps, ~5min; commit=fetchWithStallDetection, 60s stall NOT deadline, 10→60s gaps, ~15min); (3) dispatch: cleared→re-read+re-dispatch, exhausted→recoveryRollback (data-safe via 110's read-only window), unrecognised→existing :1712 exit→systemd backstop (the one human stop); (4) persistent list = classifyStepError over the migrate-failure path (thin — already rolls back).

TWO LOAD-BEARING FINDINGS: (a) retryBackoff (service.go:86–95) is DEAD (0 call sites, 100ms scale) → DELETE, don't dangle. (b) recoverFromFlag runs at :1712, BEFORE the main heartbeat ticker (:1759) → the backoff loop MUST self-heartbeat (emitHeartbeat, watchdog.go:217) every iteration or systemd WatchdogSec=120s SIGKILLs it mid-wait. (c) the forward fetch at :4362 already has the forbidden 5-min WALL-CLOCK deadline (cancels a healthy slow transfer) — the new stall-detector fixes it in a one-line swap; runCommandToLog's onAdvance hook (exec.go:152) is the ready-made stall+heartbeat feed.

TWO OPEN QUESTIONS for the King: (1) fold the :4362 forward-fetch wall-clock→stall fix into 109 (I recommend fold — known bug beside its fix); (2) forward-on-unknown → stop-on-unknown is a live safety-critical branch flip (correct per the model + safe because 110 landed, but deserves an explicit nod). Build gated on King GO + arcs (STATBUS-071, the only oracle).
---

author: foreman
created: 2026-07-02 19:16
---
BUILT + COMMITTED 782ca2455 (design doc-022; architect APPROVE + foreman targeted first-hand review of the dispatch rewrite, fetch fold, and heartbeat core; engineer self-checks all green incl. the STATBUS-039 structural tests). 5 files: recovery_backoff.go (+316: typed UnknownCause, backoffRetry with per-iteration + in-sleep heartbeats, db-unreachable spec [reconnect+SELECT-1, 1-30s gaps, 5min] + commit-not-fetched spec [stall-detecting fetch, 10-60s gaps, 15min], classifyStepError label), recovery_backoff_test.go (+166), service.go (resuming-phase classify-then-act dispatch: AtTarget→forward / Behind→rollback / Unknown+named-cause→in-process retry→clear:re-read|exhaust-or-recur:data-safe-rollback / Unrecognised→human-stop via unchanged systemd backstop; closed tri-state fail-loud default), exec.go (runCommandToLogCtx), ground_truth_test.go. THREE REVIEW RULINGS recorded: (i) retryBackoff deletion DROPPED — doc-022 premise error, 6 live callers foreman-verified; (ii) reconnect()-not-connect() CONFIRMED (preserves the advisory-lock re-acquire + re-LISTEN + 110 self-exempt the old exit-restart got); (iii) forward-step classifier is LABEL-ONLY — the unknown→stop disposition for postSwapFailure is DEFERRED to its own King nod and must move persistentStepSignatures from English substrings to SQLSTATE codes before it ever gates a decision. REMAINING for done: the install-recovery VM arcs (STATBUS-071) — same arc lane as 110's fix, blocked on the King's doc-023 nod.
---

author: foreman
created: 2026-07-03 19:40
---
ARC LANE GREEN (run 28679526112 on a3eb522c8, which includes 782ca2455's backoff + dispatch rewrite): the standard working/failing arcs pass end-to-end through the new classify-then-act recovery dispatch — no regression from the 109 commit on the normal paths (forward-apply completed; rollback clean; V_fixed completed). ACs 1-4 remain OPEN correctly: they require DEDICATED scenarios (kill the DB transiently mid-recovery for db-unreachable backoff-retry; a commit-not-fetched stall case) that the working/failing lineages do not exercise. The lane is no longer blocked by the 110/seed-fidelity regression — those scenarios can now be sequenced (candidates for the slice-3+ scenario migration onto controlled-B, STATBUS-071).
---
<!-- COMMENTS:END -->

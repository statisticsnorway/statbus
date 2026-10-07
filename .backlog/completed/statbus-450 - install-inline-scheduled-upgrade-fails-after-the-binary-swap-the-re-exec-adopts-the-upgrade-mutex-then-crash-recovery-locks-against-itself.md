---
id: STATBUS-450
title: >-
  install-inline scheduled upgrade fails after the binary swap: the re-exec
  adopts the upgrade mutex, then crash recovery locks against itself
status: Done
assignee: []
created_date: '2026-10-05 19:00'
labels:
  - upgrade
  - install
  - regression
dependencies: []
references:
  - STATBUS-447
  - STATBUS-436
  - STATBUS-444
priority: high
---

## Issue

Regression from STATBUS-447, found by the v2026.10.0-rc.15 STATBUS-436 rehearsal `CANDIDATE_PATH=scheduled` on 2026-10-05 18:39 UTC. The `CANDIDATE_PATH=operator` rehearsal (the demo repair path) passed on the same candidate.

This is the canonical operator workflow `./sb upgrade schedule <v>` + `./sb install` (inline dispatch through `ExecuteUpgradeInline`). After the binary swap, the run stops and leaves the box mid-upgrade:
- in maintenance mode
- SQL read-only
- services stopped
- flag at phase `new-sb-swapped`

Message: `Installation stopped: crash recovery: crash recovery: acquire and revalidate recovery marker before routing: an orchestrated upgrade is in progress (v2026.10.0-rc.15, invoked_by=operator:install).`

Paths not affected:
- The service path (`runningAsService` → `os.Exit(42)` → systemd restarts on the new binary, which acquires the lock fresh) is not affected. That is why smoke, dev canary and Norway's service-driven install do not see it.
- The operator path (install.sh → `./sb install` → step table, no binary swap) is not affected.

## Mechanism (code facts at ebc77c5f5)

1. `executeUpgrade` swaps the binary, stamps `new-sb-swapped`, and for the inline (non-service) case calls `prepareInheritedUpgradeLockForExec` (`cli/internal/upgrade/inherited_lock.go:152`). New in 447: it clears CLOEXEC on `d.flagLock`'s fd and exports `STATBUS_UPGRADE_MUTEX_FD`/`_TOKEN`, then `syscall.Exec`s `./sb`.
2. The new process adopts it (`AdoptInheritedUpgradeFlag`): "Continuing with the inherited upgrade mutex across the binary handoff." `DetectHoldingUpgradeFlag` → crashed-upgrade → `runCrashRecoveryWithLock(..., adoptedUpgradeLock)` → `svc.AdoptFlagLock(adopted)`.
3. Three places then probe or acquire the canonical flock through a **new open file description**. flock(2) locks belong to the open file description, so these conflict with the process's own adopted lock:
   - `stopRestartUpgradeUnit` → `confirmUpgradeDeathViaFlock` → `upgrade.IsFlockHeld`: held for the full 10 s. It prints the false `WARNING: upgrade flock STILL HELD 10s after SIGKILL of statbus-upgrade@statbus.service — the upgrade holder may still be alive`.
   - `RecoveryBudgetGuard` → `acquireFlock`: fails, and logs `upgrade flock held by another actor (id=2) — skipping early counting`. The recovery budget is silently not counted.
   - `recoverFromFlag` → `acquireRecoveryFlock(d.projDir, flag)` (`service.go:2066`; also the sites at 1977, 2012, and `restart.go`): `EWOULDBLOCK` → `formatContentionError` → the install fails.
   - Only `recoveryRollback` (`service.go:4085`) reuses `d.flagLock` when it is set.

Before 447, the re-exec closed the CLOEXEC fd, the flock was released, and the new process acquired it fresh. That is how rc.13's scheduled run reached the later STATBUS-444 failure.

Not caught before rc.15:
- The 447 harness selftest covered install.sh → `./sb install` (scenarios A/B) but not the post-swap exec continuation through recovery routing.
- No Go test drives `recoverFromFlag`/`runCrashRecoveryWithLock` with an adopted lock at phase `new-sb-swapped`.

Evidence:
- `tmp/436-scheduled-rc15.FAIL.log`
- `tmp/450-capture-scheduled-rc15/` (`statbus-tmp/install-last-run-output.txt`, `upgrade-progress.log`, `upgrade-in-progress.json` with `holder=service`, `phase=new-sb-swapped`, `handoff_token` set, and `concurrent-process-state.txt`)

## Fix direction

When the Service already holds the canonical mutex (`d.flagLock` adopted and proven), every recovery-side acquire/probe must reuse that held lock and revalidate the marker from the held fd, never open a second description:
- the `acquireRecoveryFlock` call sites in `recoverFromFlag`
- `RecoveryBudgetGuard`
- the unit-quiesce liveness confirmation, where the holder is provably us, so the flock is not evidence that the unit is alive

The revalidation (ID/Holder/Phase match, canonical inode equals the held inode) must stay as strict as today's. A lock-less caller keeps today's behaviour exactly.

Also consider: when the lock was adopted across the binary handoff, the narrative "The previous upgrade stopped unexpectedly. Recovery will run now." is false. It is a planned continuation. Say so.

## Acceptance criteria
<!-- AC:BEGIN -->
- [x] #1 A Go test drives the post-swap continuation with an adopted service lock at phase `new-sb-swapped` through recovery routing. It is RED on ebc77c5f5 (contention error) and GREEN with the fix. A sibling test proves a lock-less caller still refuses on real contention from another open file description.
- [x] #2 No recovery-side path opens a second open file description on the canonical flag while `d.flagLock` holds it. The quiesce step no longer prints the false "STILL HELD" warning or waits 10 s, and `RecoveryBudgetGuard` counts the pass.
- [x] #3 The STATBUS-436 rehearsal `CANDIDATE_PATH=scheduled` passes on the next candidate, along with `CANDIDATE_PATH=operator` (no retry).
- [x] #4 Independent review MERGE before landing on master.
<!-- AC:END -->

## Implementation Notes

2026-10-05 19:00 UTC: filed from the rc.15 scheduled rehearsal FAIL (`tmp/436-scheduled-rc15.FAIL.log`). The same day the rc.15 arc harness (run 37357691556) failed 9 arcs with the identical signature: postswap-between-migrations-kill, postswap-mid-migration-kill, boot-migrate-churn-alive-idle, flagless-selfheal-at-target, postswap-converged-selfheal, postswap-container-restart-kill, postswap-mid-tx-kill, preswap-fetch-returned-error and restore-broke-reattempt. Logs are in `tmp/rc15-arcs/<jobid>.log`. Separately, 8 arcs on that run were never executed: GitHub cancelled them with "The job was not acquired by Runner of type hosted even after multiple attempts", during the githubstatus.com incident "Incident with Actions" (19:11 to about 21:58 UTC).

Fix, on branch `fix/450-held-lock-recovery` (worktree `$JCODE_SCRATCH_DIR/fix-450`):
- 8a0804bb2 `upgrade: reuse adopted recovery lock`:
  - `Service.recoveryFlock` reuses `d.flagLock` when it is held, and revalidates the canonical inode plus ID/Holder/Phase from the held fd. Otherwise it falls back to `acquireRecoveryFlock` unchanged.
  - `recoveryBudgetFlagHold` does the same for `RecoveryBudgetGuard`.
  - `stopRestartUpgradeUnit` gets `flockHeldByCaller`.
  - On the adopted path, the narrative "Continuing the upgrade on the new binary after the planned handoff." replaces "The previous upgrade stopped unexpectedly."
- 705dfb139 `upgrade: test adopted lock recovery route`:
  - Narrow ForTest seams that bypass only DB/docker observations.
  - The `advanceResumePhase` extraction.
  - An honest quiesce line: "Crash recovery: this process owns the adopted upgrade lock; the unit's flock is not liveness evidence. Unit stopped."
- 55dc51487 `upgrade: exercise recovery budget on adopted route`: `TestAdoptedLockRunsRealPostSwapRecoveryRoute` drives the real `RecoveryBudgetGuard`, then the real `recoverFromFlag` → `resumeNewSb` phase mutation → `removeUpgradeArtifacts`, with an adopted real flock.

Proof:
- RED on a seams-only origin/master base: the guard self-contends, and route authorization fails with "acquire and revalidate recovery marker before routing" (`$JCODE_SCRATCH_DIR/fix-450/tmp/statbus-450-route-red.txt` and the `-note.txt` listing what was applied).
- GREEN on the branch.
- golangci-lint reports 0 issues, and `go test ./cmd ./internal/upgrade ./internal/install` passes.

Reviews:
- Round 1 BLOCK (`tmp/450-review.md`): the tests called helpers, not the real route. The production trace was clean on all 9 arc paths.
- Round 2 MERGE (`tmp/450-review-2.md`): the reviewer independently reproduced RED on a fresh origin/master and GREEN on the branch, and found no remaining self-contention, fd leak, double-close or reachable seam.

2026-10-06 06:13 UTC: cherry-picked onto master as 234ea00db, 70161714b and 7e92d1151 (patch-ids EQUAL to the reviewed commits), and pushed 7e92d1151. The overnight gap (20:38 UTC to 06:10 UTC) was a server reload that ended the coordinating session; no work ran in it.

Remaining: AC#3, which needs both STATBUS-436 rehearsal paths to pass on v2026.10.0-rc.16, plus a green rc.16 arc harness, especially the 9 arcs above and the 8 that never ran.

2026-10-06 08:05 UTC, v2026.10.0-rc.16 (`7e92d1151`) evidence:
- Release gates all green. Orchestrator run 37424897889: decision, smoke, dev canary, LXD fault fleet (run 37426559632) and arc harness (run 37426638674, 06:56 to 07:51 UTC, 41 success, 0 failure).
  - The 9 arcs that failed on rc.15 all passed: postswap-between-migrations-kill, postswap-mid-migration-kill, boot-migrate-churn-alive-idle, flagless-selfheal-at-target, postswap-converged-selfheal, postswap-container-restart-kill, postswap-mid-tx-kill, preswap-fetch-returned-error and restore-broke-reattempt.
  - So did the 8 that never ran on rc.15: preswap-checkout-kill, rollback-pair-terminal, rollback-kill, un-park-to-completion, transient-db-backoff, worker-wedge-mid-derive, rollback-schema-floor-failure and working.
- STATBUS-436 operator rehearsal: PASS 06:42 to 07:00 UTC, single installer run, no retry (`tmp/436-operator-rc16.PASS.log`). The old daemon was refused during the install with "another ./sb install is already running (install, invoked_by=install.sh:statbus)", the v2026.09.3 row ended superseded, and there were zero refusals and zero re-attempts afterwards.
- STATBUS-436 scheduled rehearsal: run 1 (06:42 to 06:57) completed the product path, but the test's own carrier check ran `jq` inside the hardened guest, which has none (rc=127). That line had never been reached before. The check was fixed test-only to parse the carrier on the host (`test: parse the 436 capture carrier on the host`, review `tmp/436-jq-review.md` MERGE). Run 2 (07:01 to about 07:15) used the rc.16 product with only that test file overlaid, and PASSED (`tmp/436-scheduled-rc16.PASS.log`):
  - "Continuing the upgrade on the new binary after the planned handoff."
  - 18/18 steps.
  - The carrier binds the exact reference and immutable ID for app, worker, rest and proxy.
  - The resident program is v2026.10.0-rc.16 at ~/statbus/sb.
  - The health check passed at all 4 sustained checks, with no daemon restart.

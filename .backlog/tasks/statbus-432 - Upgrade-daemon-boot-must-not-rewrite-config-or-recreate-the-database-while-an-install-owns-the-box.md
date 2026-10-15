---
id: STATBUS-432
title: >-
  Upgrade daemon boot must not rewrite config or recreate the database while an
  install owns the box
status: In Progress
assignee: []
created_date: '2026-09-29 13:29'
updated_date: '2026-10-15 20:09'
labels:
  - upgrade
  - install
dependencies: []
priority: high
ordinal: 381200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
While an installer owns the box, a restarting upgrade service neither rewrites settings nor recreates the database underneath it.

### Zoom out
The upgrade service is restarted by systemd whenever it exits. On every boot it used to regenerate `.env` and bring the database up with `docker compose up -d db`, without taking any lock. If that boot happened while `./sb install` was working (for example an old unit in a restart loop after the installer swapped the binary), it could change the settings the installer was reading and replace the database container mid-detection. The installer then saw `the database system is shutting down`.

Two rules close the race:
- **Defer to an install:** if the canonical upgrade flag is held by a live install, boot touches nothing. It logs the holder once, waits briefly, then exits with a code that does not use up systemd's restart budget.
- **Start, don't recreate:** outside a forward recovery after a binary swap, which needs the new image, boot only starts the existing database and web entry containers and never replaces them.

Then the installer's own final act starts the daemon after its last change, so it never waits on its own lock.

### Zoom in
- **Found:** Finland replay D4 (`tmp/ville-replay-v2026.09.3.md`), review `tmp/review-430.md` section 3; the symptom is STATBUS-430's.
- **Shipped (all 2026-10-01/02, in v2026.10.1):** `5eb47af5e` (boot interlock; review `tmp/review-432.md` MERGE); `a2f8dff50` (the installer starts the daemon as its final act after completion changes, fixing an rc.04 smoke self-deadlock, run `36897459913`); `c893c1f02` (only a holder with trigger `install` defers; a restart barrier does not, fixing rc.06 smoke run `36919339624`); `341f61dee` (the deferral exit moved from 75 to 76, because 75 is the rollback-complete code that must restart, found by the rc.07 arcs, run `36931202990`).
- **Detection window (AC3):** closed by the start-only rule rather than by widening the install lock: before the installer holds the lock, the only overlapping boot action can no longer replace the database.
- **Proof, unit:** `TestBootInstallHeldLiveFlockExpiresWithWatchdogAndOneHolderLog`, `TestBootInstallHeldFlockReleaseAllowsContinuation`, `TestBootRestartTriggeredHeldFlockDoesNotDefer`, `TestInstallHeldBootExpiryMapsToRestartPreventedExit76`, `TestUpgradeUnitPreventsExit76RestartAndLeavesStartupBudget`, `TestRunBootInterlockPrecedesConfigAndDatabaseActions`, `TestBootDatabaseStrategyStartsExistingOutsideForwardRecovery`, `TestBootDatabaseStrategyRecreatesForPostSwapRecovery` (`cli/internal/upgrade/boot_test.go`). Green 2026-10-15.
- **Proof, real box:** the smoke and LXD fault fleets at v2026.10.1 are green, including `1-boot-concurrent-install`, `1-boot-flag-stale-handoff` and `5-install-stage-c-systemd-failed` (LXD fleet `38740447079`).
- **Not built:** the LXD reproduction of the replay itself. The implementer argued that the decision lives entirely at the Go dispatch boundary the unit tests pin, in line with the owner's 2026-10-01 preference for logical tests over full installation sequences.

### Closing review
- **Memory:** "exit codes are a shared namespace: a new one must not collide with an existing meaning" (the 75 collision) is a lesson worth keeping.
- **Documentation:** `ops/statbus-upgrade.service` comments explain 76 versus 75.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With a live install-held flag, daemon boot performs neither config generate nor any compose up; it logs the holder once, waits bounded with watchdog pings, and exits 76, which systemd does not restart (`TestBootInstallHeldLiveFlockExpiresWithWatchdogAndOneHolderLog`, `TestInstallHeldBootExpiryMapsToRestartPreventedExit76`, `TestUpgradeUnitPreventsExit76RestartAndLeavesStartupBudget`)
- [x] #2 Outside a forward recovery after a binary swap, boot starts the existing database without recreating it; post-swap recovery still recreates (`TestBootDatabaseStrategyStartsExistingOutsideForwardRecovery`, `TestBootDatabaseStrategyRecreatesForPostSwapRecovery`)
- [x] #3 The detection window is closed by the start-only rule, argued in the ticket
- [ ] #4 LXD reproduction of the replay's shape keeps the db container ID and StartedAt unchanged from detection through the last step
- [x] #5 Go unit tests pin the interlock order and both database strategies (`TestRunBootInterlockPrecedesConfigAndDatabaseActions` and the tests above)
- [ ] #6 [Owner] Accept the unit tests plus the green v2026.10.1 fleets in place of AC4's dedicated LXD reproduction, and record it in Implementation Notes. Accepted: remove AC4, check this and set Done.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### 2026-10-01

- `Service.Run` now classifies the canonical flag and live flock before recovery checkout, config generation, or database bring-up. A live install holder is named once in the journal. Boot then waits for at most 30 seconds, pings the watchdog during the wait, and exits 75 if the install still owns the flock. This leaves 90 seconds of the unit's 120-second `TimeoutStartSec` for normal startup, and a unit test parses the shipped unit to require at least 60 seconds of remaining budget. The systemd unit lists 75 in `RestartPreventExitStatus`, so this outcome does not consume `StartLimitBurst`.
- Database boot strategy is now explicit: only `flag.IsServiceNewSbRecovery()` uses `EnsureDBUp` and its target-image `docker compose up -d db`; ordinary and pre-swap boots use `StartDatabaseRouteServingMayRun`, which starts the existing db and proxy containers without recreation.
- AC#3 uses criterion 2 rather than widening the install mutex across `detectInstallState`. Before install acquires its flag there is no owner for daemon boot to observe, but the only overlapping ordinary boot operation is now start-only. It cannot replace the db container or change its image/identity, so the detection window no longer contains the destructive operation that produced `the database system is shutting down`. Once install acquires the flock, AC#1 blocks config generation and every container action altogether.
- AC#5 is the primary coverage. Focused Go tests use real live install flocks to pin bounded expiry, watchdog notification, exactly one holder-identifying log, release-to-continue, and stale-flag continuation. Additional tests pin expiry-to-exit-75 wiring, `RestartPreventExitStatus=75`, the wait-versus-`TimeoutStartSec` startup margin, source ordering before config/database actions, and start-only versus recreation strategy selection.
- AC#4's LXD reproduction was not added. The defect mechanism is completely at the Go dispatch boundary: canonical flock classification/order and the mutually exclusive start-versus-recreate callback. The unit tests observe those decisions directly and deterministically. A guest arc would retest Docker/systemd behavior already represented by the selected commands, at substantially higher cost, without covering an additional decision or race boundary.

### 2026-10-01, rc.04 smoke deadlock follow-up

- Smoke run 36897459913 exposed a self-deadlock at fresh install step 18/18: `enable --now` synchronously booted the upgrade daemon while the same installer still held the canonical flock. The daemon correctly waited for the live install holder and exited 75 after 30 seconds, so the install failed.
- The initially considered early-release shape was rejected after review because work still remained after the step table: serving verification plus completion mutations to `public.upgrade`, the read-only window, `public.system_info`, supersession, retention, and callbacks. Releasing there would allow a second installer to overlap unfinished state and could recreate the same race between release and unit start.
- The adopted design keeps the install flock through every mutation and verification. The `Upgrade service` production step now reconciles the unit, reloads systemd, enables linger, resets failed state, enables the unit without starting it, verifies `is-enabled`, and records a coalesced final `start` or `restart` action. It never waits for daemon active/READY while holding the flock.
- Defer registration deliberately yields completion mutations first, then `systemctl --user --no-block start|restart` as the installer's final lifecycle act, then flock release. The queued daemon may reach its STATBUS-432 interlock immediately, but the holder disappears during the same process unwind rather than after the installer's former 30-second-plus tail. A second installer remains excluded until after dispatch and release.
- `TestProductionStepLoopQueuesFinalStartWhileInstallFlockHeld` drives the same `executeInstallStep` path used by the production loop with a real flock, proving reconciliation and final dispatch retain ownership and a second installer cannot acquire. `TestFinalDaemonDispatchDeferRunsAfterCompletionAndBeforeFlockRelease` pins the LIFO registration order. Existing live-holder wait/exit-75 tests remain unchanged.

### 2026-10-01, rc.06 operator-restart follow-up

- Smoke run 36919339624 completed the fresh install cleanly, then failed Phase 2 at `./sb restart all`: the restart barrier correctly retained its flock through the final daemon start, but the STATBUS-432 boot interlock mistook that `HolderInstall` restart lifecycle hold for an active installation, waited 30 seconds, and exited 75. The start job failed and the restart barrier was retained.
- Boot deferral now requires the full install identity: `HolderInstall`, `Trigger: "install"`, and a live flock. `Trigger: "restart"` returns immediately, allowing the restart command's final daemon start while the restart barrier remains held through readiness. The prior flock-through-completion and deferred no-block install-exit dispatch remain unchanged.
- Empty-trigger markers do not defer. History shows the first install-holder writer, commit `eaceacef2`, already wrote both `HolderInstall` and `Trigger: "install"`; earlier marker formats did not have install-holder semantics, so there is no legitimate legacy install writer to preserve with an empty trigger.
- Focused tests use real held flocks to prove restart-triggered and empty-trigger markers do not wait or emit exit 75 behavior, while the existing install-triggered test continues to pin the bounded wait, watchdog pings, exit 75 sentinel, and exactly one holder log line. `CheckRestartBarrier` remains consistent: it explicitly treats `Trigger: "restart"` as the operator restart barrier for install/upgrade entrants, not as an installation boot interlock.

2026-10-01 correction (found by rc.07's upgrade arcs, run 36931202990): the boot-wait exit code 75 COLLIDED with the rc.67 rollback-complete `os.Exit(75)` (service.go). Naming 75 in the unit's `RestartPreventExitStatus` made systemd refuse to restart the daemon after ANY successful rollback — c-rollback-resurrection and rollback-schema-floor-adoption proved the upgrade service stays `failed` post-rollback (exit 75 is designed to cycle under Restart=always; install.sh's "UPGRADE FAILED, ROLLED BACK" banner also keys on it). The boot-wait deferral moved to exit 76; `RestartPreventExitStatus=76 78`; boot_test.go now pins both that the unit prevents 76 and that it never prevents 75. The install-hold boot deferral semantics are otherwise unchanged.

2026-10-15 vetting: status was To Do although merges 5eb47af5e, a2f8dff50, c893c1f02 and 341f61dee are on master and in v2026.10.1. Set In Progress with AC1-3 and AC5 checked: the boot tests listed in the description pass locally on master, and the v2026.10.1 LXD fleet 38740447079 passed 1-boot-concurrent-install, 1-boot-flag-stale-handoff and 5-install-stage-c-systemd-failed. AC4 awaits the owner answer in AC6.
<!-- SECTION:NOTES:END -->

Owner note 2026-10-01 13:17 UTC: prefer logical/unit tests over full installation sequences wherever the mechanism can be pinned without a guest; AC#5 (Go unit tests) is the primary coverage and AC#4's LXD repro yields wherever the unit tests genuinely take over. Implementer argues the coverage boundary in this ticket.

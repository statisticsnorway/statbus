---
id: STATBUS-382
title: Source-sensitive upgrade work runs only in the program installed on disk
status: In Progress
assignee: []
created_date: 2026-09-22 17:01
updated_date: '2026-10-31T01:17:00Z'
labels:
  - owner-decision
  - upgrade
  - recovery
  - cli
dependencies:
  - STATBUS-527
priority: high
type: bug
ordinal: 24
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
An upgrade step whose behaviour depends on code version only ever runs in the program that is installed on disk, never in a stale copy left in memory.

### Zoom out
The upgrade daemon is a long-running process. When `./sb` on disk is replaced underneath it (by `./sb install`, `install.sh`, a park recovery restoring the source binary, or an operator by hand), the daemon keeps executing the old code it loaded. Most of the time that is harmless. It is not harmless for source-sensitive work: deciding what images the source stack runs, claiming a scheduled upgrade, writing terminal states. Old code there can make decisions the installed version has already fixed, and it can loop.

So the daemon must know when it is stale and step aside: before taking on new source-sensitive work it checks that it is the installed program, and if not it hands over to the installed one. Recovery of an upgrade already in flight is never blocked by this check, or a half-done upgrade could be stranded. And a failure that will repeat identically is recorded once and stopped, never retried in a loop.

The operator's decisions win over a stale daemon. That part is already shipped and is not reopened here.

### Zoom in
- **Incident, Norway 2026-09-22:** attempting rc.28 while checkout, on-disk `sb`, settings and containers were rc.20. The running `statbus-upgrade@statbus.service` was a deleted rc.18 executable (`/proc/<pid>/exe` -> `sb (deleted)`). rc.18's source capture ran `docker compose config` without `--profile all`, so the profile-gated `app` service had no image (`restored source compose config has no image for app`), fixed in rc.19 by `a96751064`. The stale daemon retried every 1-2 s (190 attempts, then 360 per 10 min) on row 43727 with `recovery_attempts=0`, and its id-only terminal `UPDATE` could overwrite an operator's dismiss.
- **Shipped on master (v2026.09.3):** operator-owned candidate transitions are actor-guarded in the database so a stale daemon cannot overwrite an operator decision (`7542854d6`, `5c1cb6046`, merge `8fcc7d8e4`, pg_regress `328_statbus_382_actor_guarded_upgrade_transitions`). `./sb install` restarts the daemon after an inline upgrade (`cli/cmd/install_upgrade.go` `restartUpgradeService`) and when a settings change declares `RestartUpgradeDaemon`. A crash-looping unit is taken over via `upgradeUnitCrashLooping` (STATBUS-039).
- **Not on master:** branch `next/382-steps-3-4` (4 commits, about 1,300 lines, last 2026-09-24, author jhf) holds the identity gate and an install-side takeover: `cli/internal/upgrade/daemon_fingerprint.go` (sha256 of `/proc/self/exe` vs `./sb`, results `match` / `hash_mismatch` / `disk_binary_missing` / `identity_unavailable`, with a table of every legitimate mismatch source and its disposition) and `cli/cmd/install_stale_daemon.go`. It now conflicts with master in `install.go`, `install_upgrade.go`, `install/state.go` and `upgrade/service.go`, which moved on through STATBUS-447, 452, 507 and 508.
- **Mechanism on the branch:** on mismatch the daemon exits 42 so systemd restarts it on the disk binary; ungated paths are recovery, rollback and park recovery.
- **Gap the branch closes:** today a plain `./sb install` that replaces `./sb` but changes no daemon-restart setting leaves a healthy-looking daemon running the old binary until its next restart. Nothing on master compares the running executable with the disk.
- **Decision (owner, 2026-10-22): D.** `./sb install` restarts the daemon at install exit when its running program (`/proc/<MainPID>/exe`) is not the `./sb` on disk (`cli/cmd/install_stale_daemon.go`, 0267851e9). Self-upgrade already hands over by exit 42, so only a manual install left a stale daemon. The branch's in-daemon gate and churn takeover answered the same cause and were dropped; its failure reporting is on master as `reportInstallFailure`. Both 382 branches deleted 2026-10-22 (tips in tmp/382-deleted-branches.txt).
- **Related:** STATBUS-395 owns how fast the post-swap handoff is (the 30 s `RestartSec`). STATBUS-447 owns the install.sh mutex handover.

### Closing review
- **Memory:** none needed.
- **Documentation:** the decision is the doc comment on `staleDaemonFinalAction`.
- **Cleanup:** done, both 382 branches deleted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `TestFlagInvariant_EveryPhaseAndBackupPathWriterIsAccountedFor_STATBUS232` stays green across the change
- [x] #2 [Owner] Choose how the identity gate lands: rebase `next/382-steps-3-4`, reimplement its design on current master, or drop it with the reason; record the choice in Implementation Notes. AC1-3 are then built by that route, or removed if dropped.
- [x] #3 While ./sb install holds the upgrade lock it stops the upgrader before any install step runs, and a successful install starts it again on the installed ./sb (Go test through runInstall with a recorded systemd: red before, green after)
- [x] #4 A failed install leaves the upgrader stopped and says so, and the next successful ./sb install starts it (same test); the upgrader's own post-upgrade install and boxes without systemd never stop it
- [ ] #5 On a real box: replace ./sb under a running upgrader, run ./sb install, and the upgrader comes back running the ./sb on disk (sb upgrader status); a forced failing install leaves it stopped (commands and output recorded)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC4:** green in Go Test `36503468493` (v2026.09.3).
- **AC1-3:** not on master. Their implementation exists only on `next/382-steps-3-4`, which conflicts with master as of `cb34436b4`.
- **AC5:** open; it decides how AC1-3 get built.
- The former criterion for the fast post-swap handoff moved to STATBUS-395, which owns it. The 382 -> 395 dependency was removed; it formed a cycle.

### Owner decision 2026-10-22: D
./sb install restarts a stale daemon at the source of the problem; no in-daemon gate. Branch contents reviewed (4 commits, 1,333 lines) and dropped; see Zoom in.
### Evidence
- 0267851e9. Red tmp/382-red.log (undefined symbols), green tmp/382-green.log (5 cases). `go test ./cmd/ ./internal/upgrade/` ok, lint 0 issues.
- Branches deleted locally (no remote copies); tips recorded in tmp/382-deleted-branches.txt.

### Criteria under D (2026-10-22, corrected)
An earlier edit today replaced these criteria with D-only ones; they are restored here, each settled by its own reason.
- **AC5 (checked):** owner chose D, 2026-10-22. ./sb install restarts the daemon when its running program is not ./sb on disk; the in-daemon gate is dropped.
- **AC4 (checked):** stays checked; the invariant test passes with 0267851e9.
- **AC1 (open):** met by D through ./sb install rather than a gate inside the daemon: a stale daemon is restarted at install exit, so it does not claim work. Evidence: `TestStaleUpgradeDaemonIsRestartedAtInstallExit` (5 cases), 0267851e9. To check when CI is green. The ungated recovery part is unchanged code.
- **AC2 (open):** still a real claim. Proven by the next candidate's fleet, or by an observation on a box.
- **AC3 (open, owner to decide):** with D the daemon no longer runs stale code after an install, so the failure this guarded against should not arise. Remove with that reason, or keep.

### Owner direction 2026-10-23 (evening, to confirm next session)
- Activation has one route: put the new sb in place, run ./sb install. No separate activate command. A hand-copied sb picked up by a later systemd restart is acceptable; no idle self-check in the daemon.
- During a manual install, a stopped daemon and a daemon held back by the lock behave the same. If the daemon misbehaves, stopped is safer. Proposed shape: once ./sb install holds the lock, it stops the daemon. On success it starts the daemon on the installed sb. On failure the daemon stays stopped until the next successful ./sb install. This replaces the restart-at-exit in 0267851e9, closes the release-before-restart race, and covers the failed-install case.
- Stopping under the lock cannot interrupt an upgrade: the lock means no upgrade is in flight.
- The self-upgrade handoff (exit 42) is unchanged.
- Open: confirm this shape, then implement, test in a real guest, close.

### 2026-10-26: naming decided, 382 waits for STATBUS-527
- The owner chose noun commands for long-running programs: `sb upgrader run|install|start|stop|status` (STATBUS-527), and `sb worker run` after STATBUS-093.
- 382's shape, unchanged from 2026-10-23: while `./sb install` holds the upgrade lock, it runs `sb upgrader stop`. It runs `sb upgrader start` only after a successful install, so a failed install leaves the upgrader stopped. 382 uses 527's `stop` and `start` rather than its own copy, and replaces the restart at install exit (0267851e9, `install_stale_daemon.go`).
- Correction to 2026-10-23: a hand-copied `sb` does not change the version. The source code on disk sets the version, and `./sb install` brings `./sb` back in line with it. A version change goes through `install.sh` or `sb upgrade apply`.
- AC1 and AC3 are settled when this lands: a stale upgrader is stopped under the lock and restarted on the installed `./sb`, so it never claims work. AC2 is the real-guest check.

2026-10-30 (owner): back to To Do. It waited for STATBUS-527, which is Done; it starts after v2026.10.6-rc.01 passes its gate, so the candidate is not delayed by an upgrader change.

2026-10-31 00:24 owner approved building the stop-under-lock shape (recorded 2026-10-23/26) now, for rc.04. ACs 1-3 rewritten to that shape; the dropped in-daemon identity gate is no longer the route. Implementation replaces the restart-at-exit in install_stale_daemon.go (0267851e9).

Implemented (owner's design): cli/cmd/install_upgrader_stop.go stopUpgraderForInstall, called in runInstall right after the upgrade lock is held and before any step: a running upgrader is stopped (stopUpgraderUnitAndWait) and a start is queued for install exit. On success the existing final-action dispatch starts it on the installed ./sb; on failure nothing is dispatched and the install prints 'The upgrader stays stopped until the installation finishes successfully: cd <checkout> && ./sb install' (passed to the screen by ops/install-terminal-output.awk). Bypass (the upgrader's own post-upgrade install) and non-Linux never stop it. Replaces the restart-at-exit (install_stale_daemon.go staleDaemonFinalAction / queueStaleDaemonRestart removed; sameFileContent kept for sb upgrader status). Test TestInstallStopsUpgraderUnderLockAndStartsItOnlyOnSuccess drives runInstall with a recorded systemd: red before (tmp/test-382-red.log: 'upgrader stopped = false, want true' for the running cases), green after with the upgrader inactive when steps run, start dispatched only on success, notice only on failure (tmp/test-382-green.log, full ./cmd suite ok). TestInstallUpgraderStopLinesReachTheOperator: both lines pass the screen filter (old filter drops them). AC5 real box next.
<!-- SECTION:NOTES:END -->

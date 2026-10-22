---
id: STATBUS-382
title: Source-sensitive upgrade work runs only in the program installed on disk
status: In Progress
assignee: []
created_date: '2026-09-22 17:01'
updated_date: '2026-10-22 14:40'
labels:
  - owner-decision
  - upgrade
  - recovery
  - cli
dependencies: []
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
- [ ] #1 A daemon whose running executable differs from `./sb` on disk does not claim new source-sensitive work; it hands over to the disk binary, while recovery, rollback and park recovery still run ungated (unit coverage of every mismatch source in the gate table)
- [ ] #2 On a real supervised box, replacing `./sb` under a running daemon and then scheduling an upgrade shows the claim executed by the disk version, recorded in the upgrade state log or journal
- [ ] #3 A deterministic failure before claim is recorded once with a failure code and daemon/tree provenance, and the candidate is not automatically reclaimed
- [x] #4 `TestFlagInvariant_EveryPhaseAndBackupPathWriterIsAccountedFor_STATBUS232` stays green across the change
- [x] #5 [Owner] Choose how the identity gate lands: rebase `next/382-steps-3-4`, reimplement its design on current master, or drop it with the reason; record the choice in Implementation Notes. AC1-3 are then built by that route, or removed if dropped.
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
<!-- SECTION:NOTES:END -->

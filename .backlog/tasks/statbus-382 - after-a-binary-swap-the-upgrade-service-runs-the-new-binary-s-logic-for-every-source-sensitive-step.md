---
id: STATBUS-382
title: Source-sensitive upgrade work runs only in the program installed on disk
status: In Progress
assignee: []
created_date: '2026-09-22 17:01'
updated_date: '2026-10-15 16:50'
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
- **Related:** STATBUS-395 owns how fast the post-swap handoff is (the 30 s `RestartSec`). STATBUS-447 owns the install.sh mutex handover.

### Closing review
- **Memory:** none needed.
- **Documentation:** the mismatch-source table belongs as the doc comment on the gate, where the branch already has it.
- **Cleanup:** delete `next/382-steps-3-4` once its design is landed or rejected.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A daemon whose running executable differs from `./sb` on disk does not claim new source-sensitive work; it hands over to the disk binary, while recovery, rollback and park recovery still run ungated (unit coverage of every mismatch source in the gate table)
- [ ] #2 On a real supervised box, replacing `./sb` under a running daemon and then scheduling an upgrade shows the claim executed by the disk version, recorded in the upgrade state log or journal
- [ ] #3 A deterministic failure before claim is recorded once with a failure code and daemon/tree provenance, and the candidate is not automatically reclaimed
- [x] #4 `TestFlagInvariant_EveryPhaseAndBackupPathWriterIsAccountedFor_STATBUS232` stays green across the change
- [ ] #5 Owner decision on how the gate lands: rebase `next/382-steps-3-4`, reimplement its design on current master, or drop it with the reason (for example that STATBUS-447/452 already cover the field failure)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC4:** green in Go Test `36503468493` (v2026.09.3).
- **AC1-3:** not on master. Their implementation exists only on `next/382-steps-3-4`, which conflicts with master as of `cb34436b4`.
- **AC5:** open; it decides how AC1-3 get built.
- The former criterion for the fast post-swap handoff moved to STATBUS-395, which owns it. The 382 -> 395 dependency was removed; it formed a cycle.
<!-- SECTION:NOTES:END -->

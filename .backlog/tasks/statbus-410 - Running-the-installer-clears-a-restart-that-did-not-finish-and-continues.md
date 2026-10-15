---
id: STATBUS-410
title: 'After an unfinished restart, the install command finishes it or says to wait'
status: In Progress
assignee: []
created_date: '2026-09-24 15:47'
updated_date: '2026-10-15 20:08'
labels:
  - release-bug
  - install
  - restart
  - recovery
dependencies: []
priority: high
type: bug
ordinal: 363000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
After a restart that did not finish, the install command is always a way forward: it finishes the restart itself when nobody else is doing it, and says "wait" only when a restart really is still running.

### Zoom out
`./sb restart all` stops services and records what it intends to bring back before it starts them again. If it fails or is killed in between, that record stays behind. The record exists to protect a restart in progress from a competing install, not to block every later action. What matters is whether the restart still holds its lock:
- **Lock free:** the restart is dead. The installer brings back exactly the saved set of services, confirms they are ready, clears the record and continues.
- **Lock held:** a restart is running. The installer says so in plain words and asks the operator to wait, without competing.

A restart often fails for a cause outside itself, such as a password mismatch (STATBUS-407). After repeated failures systemd stops trying to start the upgrade service for ten minutes (its start limit). A retry after the cause is fixed must clear that state, or the operator stays stuck for no reason.

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** `./sb restart all` stopped services and failed starting the upgrade service on the stale database password. The restart record stayed, and `./sb install` refused: `a restart is running or did not finish ... retry with ./sb restart all ... do not delete the restart marker` (`tmp/finland-answers-4.txt:66-74`). In the local replay, after the password was fixed, `./sb restart all` kept failing with `Start request repeated too quickly` and install kept refusing; only `systemctl --user reset-failed` escaped, and no message mentioned it (`tmp/local-ville-replay.md:964-980`).
- **Shipped (v2026.09.3):** `3fa3d744d` keeps the restart intent and lets the installer finish a dead restart. `190fa941a` makes a retried restart clear the upgrade unit's failed and start-limit state before starting it (`cli/cmd/service_restart.go`). `47173a31d` records PID and start time on every install-held marker, so a refusal names who is running. `faf0905be` corrected the live-wait fixture.
- **Proof, unit:** `TestInterruptedAndLiveRestartClassification`, `TestRestartMarkerSurvivesDaemonRecovery` (`cli/internal/upgrade/restart_test.go`); `TestRestartRetryClearsStartLimitBeforeStarting`, `TestInstallRestoresStaleRestartOnlyInFixtureProject`, `TestRestartRefusesLiveButBorrowsFreeRecoveryIntent` (`cli/cmd/service_restart_test.go`). Green 2026-10-15.
- **Proof, real box:** `5-install-interrupted-restart.sh` (a stale app-only restart restored, intent cleared, installer completed) and `5-install-live-upgrade-wait.sh` (a live restart refused with no competing recovery, then converged), both PASS in rc.17 LXD `36506437069`.
- **Not proven on a box:** recovery from the start limit. No scenario drives the upgrade service into `Start request repeated too quickly` and shows the retry clearing it.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 When the earlier restart's lock is free, the installer restores exactly the saved service set, confirms readiness, clears the record and completes (`5-install-interrupted-restart.sh`, rc.17 LXD PASS)
- [x] #2 When the earlier restart still holds its lock, the installer prints a plain wait message and starts no competing recovery (`5-install-live-upgrade-wait.sh`, rc.17 LXD PASS)
- [x] #3 Live and interrupted restarts are classified correctly and the saved intent survives (`TestInterruptedAndLiveRestartClassification`, `TestRestartMarkerSurvivesDaemonRecovery`)
- [x] #4 A retried restart clears the upgrade service's failed and start-limit state before starting it (`TestRestartRetryClearsStartLimitBeforeStarting`)
- [ ] #5 [Owner] Decide whether a real-box proof of start-limit recovery is required (drive the upgrade service into the start limit with a real cause, fix it, retry, observe it running), and record it in Implementation Notes. No: check this and set Done. Yes: add that scenario as a new criterion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** rc.17 LXD PASS, fleet `36506437069`; first green rc.05 run `36130286326`.
- **AC3-4:** green locally on master, 2026-10-15.
- **Superseded criterion:** the restyle named `5-install-start-limit-recovery.sh`, never written; that is what AC5 asks about. The 410 -> 407 dependency was removed: 407 fixes the usual cause, not a precondition of this behaviour.
<!-- SECTION:NOTES:END -->

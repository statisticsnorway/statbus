---
id: STATBUS-431
title: >-
  The upgrade service can always write its maintenance flag: the install user
  owns its directories on every install path
status: In Progress
assignee: []
created_date: '2026-09-29 10:28'
updated_date: '2026-10-26 15:10'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 380200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The upgrade service can always enter maintenance mode: `~/statbus-maintenance` and `~/statbus-backups` belong to the install user on every box, however it was installed.

### Zoom out
**Root cause class (owner-approved, 2026-10-01):** an install step's done-check tested a stand-in ("a file exists", "generated files match") while the step also carried an unrelated side effect (creating these directories). Whichever step satisfied the stand-in first silently skipped the side effect. Docker then created the missing directories as root when it bind-mounted them, and the upgrade service, running as the install user, could no longer write its maintenance flag.

The principle that follows: each step's done-check verifies that step's own outcome, and a side effect that matters gets its own step. Four parts:
1. **Directories step:** an early step creates both directories as the install user. Done means they exist and are owned and writable by that user. Creation errors fail the step.
3. **Daemon self-repair:** before writing the flag, the upgrade service repairs a root-owned directory through a container (the STATBUS-429 pattern). This heals boxes already hit.
4. **Proof:** the repair is covered by focused unit tests and one local practical check. No deliberately broken LXD box is built for this.

Moving `.env.config` out of the checkout is a separate design question, out of scope.

### Zoom in
- **Incident, 2026-10-01:** v2026.10.0-rc.01 smoke `0-happy-upgrade` (run `36851924215`) failed 5 s into the upgrade: `could not enter maintenance mode before stopping services: write maintenance flag /home/statbus/statbus-maintenance/active: permission denied`. Since `8d8f48704` and `626bc0d9b` (2026-09-24/25) the Settings step, the only place that created the directories, was skipped on every fresh install. First seen on LXD arcs on 2026-09-29 (review R3 of 425 M3a).
- **Shipped (v2026.10.0):** merge `68868c1bb`, with `9f56527c1` (Directories step), shared `cli/internal/hostrepair` (repair through the proxy image, alpine fallback, no network) and daemon self-repair before the flag write (`cli/internal/upgrade`).
- **Proof, unit:** `TestCheckDirectoriesDone`, `TestRunEnsureDirectoriesCreatesBoth`, `TestRunGenerateEnvHasNoDirectorySideEffect`, `TestDirectoriesStepPosition` (`cli/cmd/install_directories_step_test.go`); `TestSetMaintenanceRepairsViaEnsureWritable`, `TestSetMaintenanceRepairFailureIsLoud`; `TestEnsureWritable*` (`cli/internal/hostrepair`). Green 2026-10-15.
- **Proof, real box:** smoke `0-happy-upgrade` (v2026.09.3 base upgraded to the candidate, the incident's own path) SUCCESS at v2026.10.0, run `37577261099`.
- **Owner decision, 2026-10-26:** the vague "complete and valid .env.config" requirement is dropped, not moved. `.env.config` holds operator answers; `.env` is generated. Existing installs are not re-questioned, and old unused keys are not rejected or warned about on every install. On-demand cleanup of old keys is STATBUS-528 instead.
- **Proof scope, same decision:** no staged root-owned LXD box. The existing unit tests plus one local practical repair check are enough. The harness workaround is not changed as part of this ticket.

### Closing review
- **Memory:** the root cause class (a done-check tests a stand-in while the step carries a side effect) is a lesson worth keeping.
- **Documentation:** none needed.
- **Cleanup:** remove the two `lxd-backend.sh` directory workarounds once a scenario proves the product path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A Directories step, before Services, creates `~/statbus-maintenance` and `~/statbus-backups` owned and writable by the install user, and its failures fail the step (`TestCheckDirectoriesDone`, `TestRunEnsureDirectoriesCreatesBoth`, `TestDirectoriesStepPosition`)
- [x] #2 Directory creation no longer rides on the Settings step (`TestRunGenerateEnvHasNoDirectorySideEffect`)
- [x] #3 The upgrade service repairs a root-owned maintenance directory before writing its flag, and says so loudly if it cannot (`TestSetMaintenanceRepairsViaEnsureWritable`, `TestSetMaintenanceRepairFailureIsLoud`)
- [x] #4 A v2026.09.3 base upgrades to the candidate on a real box (smoke `0-happy-upgrade`, `37577261099`)
- [ ] #5 Focused unit tests prove the upgrader calls the ownership repair before writing its maintenance flag, and hostrepair repairs an unwritable scratch directory through the container path. One local practical run of the repair is recorded; no deliberately broken LXD box is required
- [x] #6 [Owner] Decided 2026-10-26: drop the vague complete-and-valid .env.config criterion, with no generic warnings for old keys. On-demand cleanup is STATBUS-528. Replace the staged real-box repair requirement with the focused tests and local practical check in criterion 5
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** green locally on master, 2026-10-15.
- **AC4:** Test Smoke `37577261099` at `bce5bf39b` (v2026.10.0), `0-happy-upgrade` success.
- **AC5:** open; `checkConfigDone` is still `os.Stat(.env.config)` on master `cb34436b4`.
- **AC6:** open; `test/install-recovery/lib/lxd-backend.sh` still runs `install -d -m 0755 ~/statbus-maintenance` in two remote blocks.
- **History:** the 2026-09-29 scope note and its 2026-10-01 correction are superseded by the Description and remain in Git history.

### Owner decision 2026-10-26: narrow and finish
AC5 (generic complete/valid .env.config) dropped as over-engineering. AC6's staged root-owned real box dropped too. Focused tests are green locally: tmp/431-hostrepair-unit.log and tmp/431-maintenance-unit.log. A local Docker practical run follows when the owner's Docker Desktop restart is complete. STATBUS-528 filed for deliberate, on-demand pruning of settings the current version does not read.
<!-- SECTION:NOTES:END -->

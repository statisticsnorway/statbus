---
id: STATBUS-527
title: >-
  Each long-running program has a noun command: sb upgrader
  install|start|stop|status|run, and later sb worker run
status: In Progress
assignee: []
created_date: '2026-10-26 11:22'
updated_date: '2026-10-26 21:08'
labels:
  - cli
  - upgrade
  - install
  - naming
dependencies: []
priority: high
type: enhancement
ordinal: 453204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Each long-running StatBus program has a noun name, and `sb` has one command group per program. `sb upgrade ...` holds actions on upgrades. `sb upgrader ...` holds everything about the program that performs them. Install, operators and the test harness all use those same commands, so no step is known only to the installer.

### Zoom out
- **Why:** the long-running program on each box is called the "upgrade service", the "daemon" and `sb upgrade service` in different places. `upgrade` reads as an instruction, and its other commands are actions (`apply`, `check`, `schedule`, `dismiss`, `list`). A program is a thing, so it gets a noun, like the worker.
- **The rule:**
  - Verbs act on upgrades: `sb upgrade apply|check|schedule|dismiss|list|register|trust-key`.
  - Nouns are long-running programs: `sb upgrader` now, and `sb worker` when STATBUS-093 moves the worker to Go.
  - Each program's long-running process is started with `run`.
- **Who manages what:** systemd manages the upgrader on the host, so it gets `install`, `start`, `stop` and `status` commands. Docker manages the worker in its container, through `./sb start|stop|restart worker`, so the worker gets only `run`.
- **Why STATBUS-382 waits for this:** 382 makes `./sb install` stop the upgrader while it holds the upgrade lock, then start it again only after a successful install. Those steps are `sb upgrader stop` and `sb upgrader start`, so 382 calls them rather than keeping its own copy.
- **Not in scope:** renaming `./sb install` or `install.sh`. Their help text gets clearer here, see AC4.

### Zoom in
| Command | What it does |
|---|---|
| `sb upgrader run` | The long-running process that systemd starts. It replaces `sb upgrade service`. |
| `sb upgrader install` | Writes the systemd user unit, reloads systemd and enables the unit. This is the code behind the current "Upgrade service" install step, which then calls it. |
| `sb upgrader start` | Starts the unit. |
| `sb upgrader stop` | Takes the upgrade lock, then stops the unit and waits until its main process has exited. If an upgrade holds the lock, it refuses with a message to wait, so a stop never interrupts an upgrade. A stop that interrupted one would trigger a rollback, a snapshot restore over the live database. |
| `sb upgrader status` | Shows the unit's state, the program it runs, and whether that program is the `./sb` on disk. Read-only. |

- **systemd unit:** rename `statbus-upgrade@.service` to `statbus-upgrader@.service`, starting with the source file at `ops/statbus-upgrade.service`. `sb upgrader install` removes the old unit when it finds one: stop under the lock, disable, delete. It then installs the new unit, so a box ends up with exactly one.
- **The old name keeps working:** units already installed run `sb upgrade service`. That command stays as a hidden alias for `sb upgrader run` until the release after every supported box has run `./sb install`. A follow-up ticket removes it.
- **Self-upgrade:** the handoff by exit code 42 is unchanged. Systemd restarts the same unit on the new `./sb`, and the post-upgrade `./sb install` moves a box with the old unit name onto the new one.
- **Wording:** operator messages, help text, docs, comments and harness output say "the upgrader". There are about 73 files with "upgrade service" and about 190 references to `statbus-upgrade@`. Check each reference before changing it: some describe the old unit on purpose, for example the code that removes it.
- **Where the references are:** `cli/cmd/upgrade.go` (the `service` command), `cli/cmd/install.go` (the "Upgrade service" step, `serviceInstance`, `dispatchUpgradeDaemonFinalAction`), `cli/cmd/install_upgrade.go` (`restartUpgradeService`), `cli/cmd/install_stale_daemon.go`, `ops/statbus-upgrade.service`, `install.sh`, `test/install-recovery/` and the upgrade arcs, plus `doc/upgrade-*.md`, `doc/DEPLOYMENT.md` and `doc/install-upgrade-testing.md`.

### Closing review
- **Memory:** none needed. The naming rule is in this description and in the `sb upgrader` help text.
- **Documentation:** `doc/upgrade-timeline.md`, `doc/upgrade-recovery-model.md`, `doc/DEPLOYMENT.md` and `doc/install-upgrade-testing.md` say "the upgrader" and name the new commands.
- **Cleanup:** the `sb upgrade service` alias is removed by the follow-up ticket (AC9).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `sb upgrader run|install|start|stop|status` exist with the behaviour in the Zoom in table. Go tests cover each command, including: `stop` refuses while an upgrade holds the lock, and `stop` returns only after the main process has exited
- [x] #2 The unit is `statbus-upgrader@.service`. On a box with the old unit, `./sb install` leaves exactly one unit, the new one, running; a Go test with a recorded systemd state covers the migration
- [x] #3 Operator-facing text, help and docs say "the upgrader". Each remaining `statbus-upgrade@` or "upgrade service" reference describes the old unit on purpose
- [x] #4 The help for `./sb install` says it sets up or repairs this box at the version on disk, and names `install.sh` and `sb upgrade apply` as the ways to change version
- [ ] #5 STATBUS-093 records that the Go worker's long-running command is `sb worker run`
- [x] #6 Code review of the diff finds a single implementation of unit writing and of start/stop: the "Upgrade service" step in `./sb install` calls the same functions as `sb upgrader install|start|stop`
- [x] #7 `sb upgrade service` still starts the upgrader, as a hidden alias, and a test proves it
- [ ] #8 [Owner] Decide when the `sb upgrade service` alias is removed. A follow-up ticket for that is filed, and its ID is recorded in this ticket's Implementation Notes
- [ ] #9 The existing `0-happy-upgrade` scenario, which installs the previous release (old unit) and self-upgrades to the candidate, asserts after the upgrade: only `statbus-upgrader@` exists and is active, `statbus-upgrade@` is gone, and `sb upgrader status` reports the installed `./sb`. Proven by that scenario's run in the candidate's release gate, or the same scenario on the per-commit image; no one-off script. Run ID recorded in Implementation Notes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-26: delegated to a K3 worker (implementation through real-guest proof); Claude Opus 5.5 reviews when done.

2026-10-26 owner: keep the rename (one-time migration, one canonical name). Proof goes through the existing harness (0-happy-upgrade assertions), not a one-off guest run. The switch from the old unit to the new one happens only while the upgrader holds the upgrade lock, so it never stops itself mid-upgrade.

2026-10-26 (K3 recovery worker, sheep): landed on master as 4b458e410 (upgrader: commands + unit rename + migration + alias + harness assertions), 1e043d7ec (docs), 048c44844 (backlog 093 note). Rebased onto 62be92e3a before push.

Recovered the previous K3 worker's saved patch (tmp/396-before-base-update-worktree.diff in the shared checkout), resolved its one conflict in cli/cmd/install.go (help text) preserving STATBUS-429's certificate step, and restored the three unrelated regenerable test/expected files to HEAD.

Verification (this checkout): gofmt clean; go build ./...; go test ./cmd/ ./internal/... all ok; golangci-lint run ./... 0 issues (fixed two findings in the recovered work: ineffectual lock assignment in handoffToRenamedUpgraderUnit, De Morgan in the ordering test); ./dev.sh test-harness exit 0; bash -n on all edited shell files. Fixed replace-all damage: assertions.sh comment ('renamed from' named the resolver instead of the old unit), boot.go 'every box's the upgrader', install_quiesce_order_test.go 'the box's the upgrader', 0-happy-upgrade echo. The recursive upgrade_unit_name body the coordinator warned about was already corrected in the saved patch (body has no self-call; confirmed with coordinator).

AC evidence:
- AC1: sb upgrader run|install|start|stop|status in cli/cmd/upgrader.go. Tests: TestUpgraderStopRefusesWhileUpgradeHoldsLock (systemd never sees a stop while the lock is held), TestUpgraderStopWaitsForMainProcessExit, TestUpgraderStopFailsWhenProcessSurvives, TestUpgraderStopWithoutUnitIsANoOp, TestUpgraderStart*.
- AC2: ops/statbus-upgrader.service (renamed); migration in installUpgraderUnit under the upgrade lock, new unit written+enabled before the old is touched. Tests: TestUpgraderInstallMigratesLegacyUnit, TestUpgraderInstallMigrationOrdering (stop runs while the lock is held), TestUpgraderInstallRefusesMigrationWhileUpgradeHoldsLock, TestUpgraderInstallFixupLeavesLegacyAlone, TestHandoffToRenamedUpgraderUnit_* (internal/upgrade).
- AC3: wording swept; remaining 'statbus-upgrade@'/'upgrade service' references are the legacy-migration code, the deliberate internal protocol tokens (application_name statbus-upgrade-daemon-<pid>, advisory lock key), or doc/archive history.
- AC4: install help now says it sets up or repairs this box at the version on disk and names install.sh and 'sb upgrade apply' as the version-changing paths.
- AC6: pinned by TestInstallStepAndHelpersShareTheUpgraderImplementation (install step, final action and restartUpgradeService all call upgrader.go).
- AC7: 'sb upgrade service' hidden alias sharing upgradeServiceRunE with 'sb upgrader run'; pinned by TestUpgradeServiceAliasIsUpgraderRun.
- AC5 (093 note) committed in 048c44844. AC8 owner, AC9 real-guest: left for the release gate/owner.

2026-10-26 (K3 recovery worker, sheep) follow-up: Harness Selftest on 048c44844 caught one replace-all miss — configure-smoke-instance.sh is an executable VM_SCRIPT payload (no harness libs sourced), so $(upgrade_unit_name) exited 127. Fixed with the literal statbus-upgrader@statbus.service (0-happy-install always installs the candidate) in cc6dd10fd, verified locally by bash test/install-recovery/tests/operator-config-test.sh (PASS) and bash -n.

CI for the final master SHA cc6dd10fd (gh run list --commit): Push on master success [40397288751], Images success [40397289201], Go Test success [40397289228], app build & lint success [40397289264], Harness Selftest success [40397289306], Fast Tests success [40397836346]. All green.
<!-- SECTION:NOTES:END -->

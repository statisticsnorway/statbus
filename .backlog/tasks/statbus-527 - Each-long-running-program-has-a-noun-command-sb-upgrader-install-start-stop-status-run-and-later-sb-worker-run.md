---
id: STATBUS-527
title: >-
  Each long-running program has a noun command: sb upgrader
  install|start|stop|status|run, and later sb worker run
status: In Progress
assignee: []
created_date: '2026-10-26 11:22'
updated_date: '2026-10-26 12:42'
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
- [ ] #1 `sb upgrader run|install|start|stop|status` exist with the behaviour in the Zoom in table. Go tests cover each command, including: `stop` refuses while an upgrade holds the lock, and `stop` returns only after the main process has exited
- [ ] #2 The unit is `statbus-upgrader@.service`. On a box with the old unit, `./sb install` leaves exactly one unit, the new one, running; a Go test with a recorded systemd state covers the migration
- [ ] #3 Operator-facing text, help and docs say "the upgrader". Each remaining `statbus-upgrade@` or "upgrade service" reference describes the old unit on purpose
- [ ] #4 The help for `./sb install` says it sets up or repairs this box at the version on disk, and names `install.sh` and `sb upgrade apply` as the ways to change version
- [ ] #5 STATBUS-093 records that the Go worker's long-running command is `sb worker run`
- [ ] #6 Code review of the diff finds a single implementation of unit writing and of start/stop: the "Upgrade service" step in `./sb install` calls the same functions as `sb upgrader install|start|stop`
- [ ] #7 `sb upgrade service` still starts the upgrader, as a hidden alias, and a test proves it
- [ ] #8 [Owner] Decide when the `sb upgrade service` alias is removed. A follow-up ticket for that is filed, and its ID is recorded in this ticket's Implementation Notes
- [ ] #9 The existing `0-happy-upgrade` scenario, which installs the previous release (old unit) and self-upgrades to the candidate, asserts after the upgrade: only `statbus-upgrader@` exists and is active, `statbus-upgrade@` is gone, and `sb upgrader status` reports the installed `./sb`. Proven by that scenario's run in the candidate's release gate, or the same scenario on the per-commit image; no one-off script. Run ID recorded in Implementation Notes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-26: delegated to a K3 worker (implementation through real-guest proof); Claude Opus 5.5 reviews when done.

2026-10-26 owner: keep the rename (one-time migration, one canonical name). Proof goes through the existing harness (0-happy-upgrade assertions), not a one-off guest run. The switch from the old unit to the new one happens only while the upgrader holds the upgrade lock, so it never stops itself mid-upgrade.
<!-- SECTION:NOTES:END -->

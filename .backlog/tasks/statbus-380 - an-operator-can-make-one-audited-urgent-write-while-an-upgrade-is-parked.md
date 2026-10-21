---
id: STATBUS-380
title: A stuck upgrade tells the operator how to fix it and resume
status: Done
assignee: []
created_date: '2026-09-21 12:03'
updated_date: '2026-10-21 13:38'
labels:
  - release-bug
  - upgrade
  - recovery
  - cli
dependencies: []
priority: low
type: task
ordinal: 22
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
When an upgrade gets stuck, the operator fixes the cause and resumes it, and the box tells them how.

### Zoom out
A parked upgrade keeps the database read-only as a guard against accidents, not a lock. The flow is:
1. **Stuck:** an upgrade that fails the same way twice parks. Retries stop, the alert fires once, and the cause is recorded. The box serves the version it can prove, or stays behind the maintenance page, read-only.
2. **Fix:** on the box directly. In the database, the operator's own `./sb psql` session runs `SET default_transaction_read_only = off;`. Everyone else stays read-only.
3. **Resume:** `./sb install` stops the upgrade service, takes the upgrade lock, clears the park and runs one fresh attempt. On success it lifts maintenance and read-only and restarts the service. If the same failure returns, the upgrade parks again.

Only `./sb install` clears a park. A newer release replaces the parked upgrade. A database fix survives a forward resume and is lost only if the attempt rolls back to the snapshot.

### Zoom in
- **Guidance:** the park message (both park sites in `cli/internal/upgrade/service.go`) prints `ParkedResumeGuidance` (`cli/internal/upgrade/install_command.go`): the psql step and the install step, both runnable from any directory, and that a newer release replaces the upgrade.
- **Docs:** `doc/read-only-upgrade-window.md`, "Fixing a parked upgrade and resuming it".
- **Un-park:** `./sb install` (`cli/cmd/install_upgrade.go`, `UnparkByID` then `RecoverFromFlag`) stops the unit first and restarts it after a recovery.
- **Removed, owner 2026-10-21:** `./sb upgrade repair` (v2026.09.3: `4e8899f05`, `4069671b3`, `a0781aab7`). It required an operator name and reason, wrote an audit row and allowed one statement. That records and restricts a person who already means to write, and its doc forbade the psql path the read-only design provides.

### Closing review
- **Memory:** none needed.
- **Documentation:** done in `doc/read-only-upgrade-window.md`.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A parked upgrade's progress log names the resume flow: the operator's own ./sb psql session with default_transaction_read_only off, then ./sb install for one fresh attempt, both runnable from any directory (TestParkedResumeGuidanceNamesTheResumeFlow)
- [x] #2 ./sb upgrade repair is gone; the Go build, cmd and upgrade tests and lint pass, and CI passes (33af99026)
- [x] #3 doc/read-only-upgrade-window.md describes stuck, fix, resume as above
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** green in Go Test `36503468493` (v2026.09.3); re-run locally 2026-10-15.
- **AC4:** open; no scenario or arc uses the verb.
- **AC5:** open.

### Owner decision 2026-10-21: no audited repair verb
The read-only park is a guard against accidents, not a lock. Recording who repaired and why, and allowing one statement only, is bureaucracy over an operator who already means to write. The flow is: stuck, fix (own psql session off read-only), resume with ./sb install. Removed `./sb upgrade repair` and its tests. The park message and doc name the flow.
### Evidence 2026-10-21
- 33af99026. `go test ./cmd/ ./internal/upgrade/ ./internal/installcmd/` ok, golangci-lint 0 issues (`tmp/380-go-test.log`). `TestParkedResumeGuidanceNamesTheResumeFlow` asserts the exact lines.
- CI for 33af99026: Go Test, Fast Tests, Images, Harness Selftest, app build & lint, Push on master all success.
- Owner idea to discuss next: `./sb psql --recovery` opening a session already off read-only.
<!-- SECTION:NOTES:END -->

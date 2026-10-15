---
id: STATBUS-507
title: Rollback leaves the database stopped when an earlier rollback step fails
status: In Progress
assignee: []
created_date: '2026-10-15 09:16'
updated_date: '2026-10-15 09:26'
labels:
  - upgrade
  - rollback
  - recovery
dependencies: []
priority: medium
ordinal: 433204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a rollback never ends with the database down; 'database running and answering' is a declared end state of the restore, not a side effect of a later step. EVIDENCE (rc.02 fleet run 38696133051, scenario 5-install-source-identity-scheduled, untruncated capture): rollback() stops app, worker, rest AND db (preRestoreStopServices) before it even checks for a snapshot; with no snapshot recorded it restores nothing, then the only code that starts the database is startSourceApplicationStack, called after the git restore and config generation. That call failed ('source serving era cannot be established'), so the database was never started: 'DB not ready: service db is not running', a 5-minute reconnect into nothing, INVARIANT ROLLBACK_TERMINAL_WRITE_FAILED, box left needing manual recovery. STATBUS-452's fix (255a41d72) stops that particular path being reached; this defect remains for any other failure in the same place. The primitive already exists: StartDatabaseRouteServingMustBeStopped (compose start db + proxy, health wait), used by startRollbackDatabaseOnly, park, boot and resumeNewSb, but not by the main rollback path. LAYERS (owner ruling 2026-10-15): the procedure starts the SAME container and waits until it answers; the test reads the data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When there is nothing to restore (no snapshot), rollback does not stop the database
- [ ] #2 After the volume restore, rollback starts the same database container and waits until it answers, independently of the later serving-tier start
- [ ] #3 A failure in git restore, config generation or the serving-tier start leaves the database running and the rollback outcome recorded
- [ ] #4 Test written first and recorded red on the current code, then green
<!-- AC:END -->

---
id: STATBUS-507
title: Rollback leaves the database stopped when an earlier rollback step fails
status: In Progress
assignee: []
created_date: '2026-10-15 09:16'
updated_date: '2026-10-15 09:54'
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
- [x] #1 After the volume restore, rollback starts the same database container and waits until it answers, independently of the later serving-tier start
- [x] #2 A failure in git restore, config generation or the serving-tier start leaves the database running and the rollback outcome recorded
- [x] #3 Test written first and recorded red on the current code, then green
- [x] #4 When there is nothing to restore (no snapshot), rollback starts the same database container again right after its verified stop, before and independent of the serving tier (the stop stays one verified set; the snapshot decision comes after it)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FIXED 9bb4949c7. restoreAndFinalize now starts the SAME database container again on the no-snapshot path through the existing held-closed route (startRollbackDatabaseOnly: compose start db + its proxy, health wait, reconnect), before and independent of the serving tier; a failure there reports as a database failure through the existing degraded terminal. The snapshot path already had this (startRollbackDatabaseOnly after the volume restore). Criterion #1 was reworded from 'does not stop the database': the stop stays one verified set (STATBUS-187), and the snapshot decision comes after it, so the right fix is to start it again immediately, not to split the stop. RED/GREEN: TestUpgradeFlaglessBehindRowServingFailureKeepsDatabaseUp (livedb) - no snapshot + serving tier fails. Red on the unfixed code: docker saw only 'compose stop app worker rest db' (tmp/fix507-red2.log). Green: 'compose start db' follows, state=failed recorded. Four existing tests' docker shims claimed no proxy container (a state no real box is in) and were corrected; one source-order pin follows the renamed call. Full livedb tier + unit + golangci-lint pass. Fleet proof: rides the next candidate after rc.03.
<!-- SECTION:NOTES:END -->

---
id: STATBUS-519
title: >-
  Move to sql_saga v1.2: in-place update with its integrity gate, and the
  history-policy security fix
status: In Progress
assignee: []
created_date: '2026-10-20 11:11'
updated_date: '2026-10-20 11:19'
labels:
  - db
  - sql_saga
dependencies: []
priority: high
ordinal: 445204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Every box runs sql_saga 1.2, reached in place from 1.1, with sql_saga's own integrity check passing afterwards.

### Zoom out
sql_saga v1.2 (tag 835058eb0c8a, 2026-10-20) supports in-place updates from 1.0 and 1.1. It fixes a security defect present in 1.1: history policy/RLS protection could be bypassed by setting sql_saga.managing_history_policies. The update is atomic. Its last step runs sql_saga.check_integrity() and refuses, rolling everything back, on any damaged managed family. Upstream steps (doc/upgrade.md): install the 1.2 package and restart PostgreSQL; optionally rehearse with BEGIN; ALTER EXTENSION sql_saga UPDATE TO '1.2'; ROLLBACK; with writers stopped, run the update; verify with check_integrity().

### Zoom in
- Box path: the upgrade restarts the db container on the new image (1.2 libraries, 1.1 schema), with the app stopped in maintenance, then runs migrations. A guarded migration does the update, the same pattern as sql_saga 1.1 (20261015163419) and jsonb_stats 3.0.0 (20261018113522).
- 1.2 refuses when the privileges of sql_saga.add_system_versioning were changed. No StatBus migration changes them.
- No downgrade script exists; rollback is the pre-upgrade backup, which the upgrade's rollback restores.

### Closing review
- **Memory:** none. **Documentation:** the migration comment carries the upgrade meaning. **Cleanup:** the local image tag statbus-db:pre-saga12 after the proof.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 postgres/Dockerfile pins sql_saga_release=v1.2, and migration 20261020111102 updates 1.1 to 1.2 in place when the database is at 1.1 (a no-op otherwise); its down refuses
- [ ] #2 A box-shaped proof on data with temporal tables: the db restarts on the new image at 1.1, the rehearsal (BEGIN; ALTER EXTENSION ... UPDATE; ROLLBACK) prints ROLLBACK, the migration runs, and the verification reads 1.2 | 1.2 | 1 | NULL with check_integrity() passing and 0 detached initial privileges
- [ ] #3 The app's restricted roles read and write through the temporal views after the update, and a dump of the 1.2 database restores in one transaction
- [ ] #4 The fast suite and Go tests pass locally, and CI passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Blocked upstream (2026-10-20 11:19)
- The rehearsal (BEGIN; ALTER EXTENSION sql_saga UPDATE TO '1.2'; ROLLBACK) on StatBus demo data refuses at 1.2's final integrity gate: unique key activity_type_establishment_id_valid is 'noncanonical'.
- **Cause, an upstream sql_saga defect:** the rename-following event trigger rewrites column_names of every XOR key (mutually_exclusive_columns) sorted by name, on any DDL. The constraint keeps the given order, and 1.2's check compares conkey in order. Reproduced on a fresh 1.2 database in 6 statements (tmp/519-repro-fresh12.sql). Five StatBus keys are affected, on dev, demo, Norway and the seed.
- **Report for the sql_saga agent:** tmp/sql_saga-xor-key-order-defect.md, also copied to ../sql_saga/STATBUS_REPORT_xor_key_order.md (uncommitted). It needs the trigger fixed plus a catalog repair in the 1.0/1.1 to 1.2 path.
- **Local state:** the pin bump and migration are uncommitted (postgres/Dockerfile, migrations/20261020111102_*). They wait for a fixed tag. The local db container runs the 1.2 image with schema still at 1.1.
<!-- SECTION:NOTES:END -->

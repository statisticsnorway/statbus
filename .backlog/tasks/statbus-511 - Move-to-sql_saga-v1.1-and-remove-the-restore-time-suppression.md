---
id: STATBUS-511
title: Move to sql_saga v1.1 and remove the restore-time suppression
status: In Progress
assignee: []
created_date: '2026-10-15 16:26'
updated_date: '2026-10-15 16:27'
labels:
  - sql_saga
  - release
dependencies: []
priority: high
ordinal: 437204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
StatBus runs the released sql_saga v1.1 on every box, and a dump restores with sql_saga's checks active, so no restore-time workaround remains.

### Zoom out
sql_saga v1.1 (tag `v1.1`, 54 commits after our pin `9e39fcc` = v1.0) fixes the ACL gate that made our dumps unrestorable (STATBUS-481/482). It upgrades in place from 1.0 with `ALTER EXTENSION sql_saga UPDATE TO '1.1'`, per sql_saga's `doc/upgrade.md`. That lets STATBUS-486 remove the suppression.

### Zoom in
- **Image:** `postgres/Dockerfile` pins `sql_saga_release=v1.1`. In v1.1, `make install` builds both libraries (C and the Rust `sql_saga_native`); `sql_saga_native` is no longer a separate extension, so the separate cargo-pgrx stage goes.
- **Existing boxes:** a forward migration runs the upgrade. It needs the new libraries loaded, which the upgrade's image swap and container restart provide before migrations run. Preflight per upgrade.md: no cache API use (verified: no references), no policies created directly on history tables.
- **Fresh installs:** `CREATE EXTENSION sql_saga` gets 1.1 directly.
- **Restore:** our restores are serial `--single-transaction`, outside v1.1's parallel-restore caveat. Remove `restoreTargetConninfo`'s `session_replication_role=replica` (STATBUS-486); keep the seed round-trip guard and migration `20261008183553`.
- **Out of scope:** parallel restore.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The db image builds from sql_saga v1.1; a fresh database reports extversion 1.1 and native_library_version 1.1
- [ ] #2 A database at 1.0 is upgraded by a forward migration and passes upgrade.md's verify queries (1.1, 1.1, 1, NULL, 0)
- [ ] #3 A dump restores without session_replication_role, serial and via the seed path; the seed round-trip guard passes
- [ ] #4 Full fast suite, test-livedb and Go Test green at job level; the next candidate's ladder green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Workaround inventory (2026-10-15, before any change)
**Removed with v1.1** (they exist only because of the 1.0 ACL gate, STATBUS-481/482):
- `cli/cmd/restore_replica.go` `restoreTargetConninfo`: every pg_restore runs with `session_replication_role=replica` (3ce591f16). Call sites: `db.go:790,819,853`, `seed.go:319`, `seed_build.go:212`, `seed_verify.go:485`; its unit test `restore_replica_test.go`. v1.1's upgrade.md says never change `session_replication_role` around sql_saga.
- `test/sql/352_statbus_481_for_portion_of_view_acls.sql`: asserts each for-portion-of view's ACL equals its table's (524669e21). v1.1 normalizes direct grants on derived objects away (views get PUBLIC privileges; authorization comes from the base table), so 352's expected state is the opposite of v1.1's and the test goes.
- The direct GRANTs on `*__for_portion_of_valid` views in old migrations stay (released, immutable); v1.1's UPDATE removes them on every box.

**Kept** (guards, not workarounds):
- Seed round trip (`seed_roundtrip.go`, `seed_types_check.go`, 3f80ec06b): proves a dump restores and yields identical types. It now runs WITHOUT the suppression, which is the proof the workaround is gone.
- Ordered output in `cli/sql/generate_database_types.sql` (by name, not OID): correct regardless of sql_saga.
- Migration `20261008183553` (481-B): released, immutable. Its effect is undone by v1.1's normalization.

**Steps:** 1) Dockerfile: `sql_saga_release=v1.1`, one `make install` with Rust and libclang, drop the separate native stage. 2) Forward migration: `ALTER EXTENSION sql_saga UPDATE TO '1.1'` (preflight run locally: 161 derived grants listed for removal, no history-table policies, no cache API use). 3) Remove the suppression and test 352. 4) Seed rebuild, full fast suite, test-livedb, Go Test, then CI. STATBUS-486 closes with this ticket; STATBUS-482 (upstream) closes when v1.1 ships.
<!-- SECTION:NOTES:END -->

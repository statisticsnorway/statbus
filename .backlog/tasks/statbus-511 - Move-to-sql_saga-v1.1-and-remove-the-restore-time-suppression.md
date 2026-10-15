---
id: STATBUS-511
title: Move to sql_saga v1.1 and remove the restore-time suppression
status: In Progress
assignee: []
created_date: '2026-10-15 16:26'
updated_date: '2026-10-15 20:45'
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
- [x] #1 The db image builds from sql_saga v1.1; a fresh database reports extversion 1.1 and native_library_version 1.1
- [x] #2 A database at 1.0 is upgraded by a forward migration and passes upgrade.md's verify queries (1.1, 1.1, 1, NULL, 0)
- [x] #3 A dump restores without session_replication_role, serial and via the seed path; the seed round-trip guard passes
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

### Upgrade proof, box-shaped (2026-10-15, tmp/saga11-upgrade-proof.sh, log tmp/saga11-upgrade-proof.log)
Throwaway volume; dev stack untouched.
1. Current image `statbus-db:b6d81049` restores the dev dump: extversion 1.0, 233 grants on the for-portion-of views.
2. Same volume restarted on the new image (`saga11`, sql_saga v1.1 libraries): still 1.0, as a box is after its image swap and before migrations.
3. v1.1 preflight passes, listing the derived grants it will remove.
4. Migration `20261015163419` (guarded `ALTER EXTENSION sql_saga UPDATE TO '1.1'`) commits.
5. upgrade.md verify: 1.1, 1.1, 1, NULL, then 15 instead of 0. The 15 are pg_stat_monitor/pg_stat_statements objects (another extension's own init privileges), not sql_saga's: the same query restricted to objects belonging to no extension returns 0. upgrade.md's query counts every extension's rows; on a database with other extensions read it as "0 detached rows".
6. Access is unchanged: regular_user and admin_user can select and update through `legal_unit`/`establishment` `__for_portion_of_valid` (all 9 views are security_invoker). restricted_user's view has PUBLIC grants but reading it raises `permission denied for table legal_unit`, so the base table still decides.
7. The REVOKE that failed under 1.0 (STATBUS-481) succeeds with checks active.
8. The 1.1 database dumps and restores into an empty database with NO session_replication_role: extversion 1.1, event triggers 7/7 enabled.
AC1 (fresh 1.1 from the image) and AC2 (1.0 upgraded by a forward migration, verified) checked.

AC1 verified separately: a fresh database on the new image reports extversion 1.1, native_library_version 1.1.

### Seed round trip without the suppression (2026-10-15, tmp/saga11-seed-image.log)
The hermetic seed stage, built CI-shaped (tmp/saga11-seed-image.sh: same named contexts as images.yaml, Linux sb from the working tree, empty prior so PATH=FULL from empty), ran `sb db seed build` with `restoreTargetConninfo` removed: "seed round trip OK, seed -> restore -> dump -> restore; ACL digest identical; event triggers enabled 7/7", and types generated from the restored seed equal the committed database.types.ts. AC3 checked.
Note: images.yaml's comment names a local `./sb build seed` that only prints "No services to build"; the script above is the working local equivalent.

### Landed 42739f5f9 (2026-10-15)
Local verification on the v1.1 db image: fast suite 117/117 in one run (tmp/saga11-test-fast.log), ./dev.sh test-livedb exit 0, go test ./... exit 0, golangci-lint 0 issues. Expected-output changes are v1.1's documented catalog change: test 002 gains sql_saga.installation and loses temporal_merge_cache; doc/db-security-report.md gains __internal_reconcile_system_versioning_family and loses temporal_merge_cache_maybe_purge.
Found on the way: Go Test had been red on master since cd3b6ada8 (my column-comment migration sat above DaemonSchemaFloor). Fixed in c5d1dae35 by the reviewed floor bump.
AC4 open: CI at job level for 42739f5f9 (Images builds the db image and the seed with the round trip, Fast Tests, test-livedb, Go Test), then the next candidate's ladder.

### CI green (2026-10-15)
CI on 42739f5f9 at job level: Images 38794026480 success (db image amd64+arm64 with sql_saga v1.1; seed job round trip without suppression: ACL digest identical, event triggers 7/7, types equal), Go Test 38794026570 success (go test + golangci-lint), Harness Selftest 38794026593 success, app build & lint 38794026656 success. Fast Tests 38802563803 success (pg_regress fast suite) at 3380e9ac0, which contains 42739f5f9 with identical suite inputs (migrations, test, cli, postgres, dev.sh, app/src/lib); the runs at 42739f5f9 itself were cancelled by later pushes.
AC4 remains for the next release candidate's ladder. Owner notes sql_saga v1.2 is coming (a fix in progress); it is expected to be a quick pin bump on top of this.
<!-- SECTION:NOTES:END -->

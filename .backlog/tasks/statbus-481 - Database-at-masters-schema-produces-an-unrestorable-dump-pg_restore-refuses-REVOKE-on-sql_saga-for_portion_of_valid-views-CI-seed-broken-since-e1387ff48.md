---
id: STATBUS-481
title: >-
  Database at master's schema produces an unrestorable dump: pg_restore refuses
  REVOKE on sql_saga for_portion_of_valid views (CI seed broken since e1387ff48)
status: In Progress
assignee: []
created_date: '2026-10-08 17:19'
updated_date: '2026-10-08 18:13'
labels:
  - sql
  - ci
  - upgrade
dependencies: []
priority: high
ordinal: 407204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a StatBus database at master's schema can be dumped and restored, so backups, the published seed, and the upgrade path all work.

SEVERITY: a database in this schema state produces a DUMP THAT CANNOT BE RESTORED. That is a backup/restore risk, and therefore an upgrade-path risk on real boxes, not merely a CI inconvenience. The seed path in install.sh can fall back to a full replay, which is one way such a database gets built in the first place.

EXACT ERRORS:
- CI (published seed): pg_restore: error: could not execute query: ERROR: cannot revoke MAINTAIN directly from "establishment__for_portion_of_valid", revoke MAINTAIN from "establishment" instead. Then: Error: restore prior seed: seed build restore prior: pg_restore reported errors (transaction rolled back; database unchanged).
- Local reproduction: pg_restore: error: could not execute query: ERROR: cannot revoke INSERT directly from "establishment__for_portion_of_valid", revoke INSERT from "establishment" instead.

CI EVIDENCE (2026-10-08):
- Images: the 'seed' job fails on EVERY master commit since e1387ff48. Runs: 37811621235 (e1387ff48, 16:48), 37812620351 (27d652b03), 37812692154 (5e89838f8), 37813178937 (f8553dd00), 37814739043 (194608712). All build jobs succeed; only 'seed' fails. The failing builds take PATH=INCREMENTAL and restore the prior published seed, 'incremental base: ghcr.io/statisticsnorway/statbus-seed:f0486e26'.
- The last green Images runs were 37810003589 (f0486e266, 16:35), 37809975579 (a64f4ad38) and 37809785849 (aec850de7, 16:33). Run 37810003589 restored 'incremental base: statbus-seed:aec850de' fine.
- Fast Tests 37810572079 on f0486e266 (16:42) FAILED for real: its log shows the same restore error, then 'recreate-seed: restore failed - falling back to FULL_REPLAY', and the job failed (306_load_demo_data and 351_statbus_460_unit_existence_rule not ok).
- Consequence: Fast Tests SKIPS its pg_regress job whenever Images fails, so every master commit since e1387ff48 shows Fast Tests 'success' with pg_regress skipped. Those runs are not test evidence (this affects STATBUS-477 A/E/B: 27d652b03, f8553dd00, 194608712).

LOCAL REPRODUCTION, on PG 18.6 (postgres (PostgreSQL) 18.6, Ubuntu 18.6-1.pgdg22.04+2), WITHOUT any STATBUS-477 migration: statbus_477a_prefix is a clone of statbus_seed at master 20261008161441 (460 applied), taken before 477. Command:
  docker exec statbus-local-db sh -c 'pg_dump -U postgres -Fc -d statbus_477a_prefix -f /tmp/pre477.dump && createdb -U postgres statbus_477_restoretest2 && pg_restore -U postgres --single-transaction --exit-on-error -d statbus_477_restoretest2 /tmp/pre477.dump'
  -> restore exit 1 with the INSERT variant of the error above. The same happens for statbus_seed with 477 A/E/B applied.

BISECT: aec850de's published seed restored fine at 16:33 (Images 37810003589 used it as its incremental base). The first failing published seed is statbus-seed:f0486e26, the first published seed whose master contains 460 (a64f4ad38, sql+app: one canonical unit existence rule, migration 20261008161441_statbus_460_canonical_unit_existence_rule).

OBSERVATIONS: neither the 460 migration (20261008161441) nor the 461 migration (20261008150755) contains any GRANT, REVOKE or reference to the for_portion_of_valid views. The ACLs of the sql_saga for_portion_of_valid views mirror their base tables, including admin_user: establishment and establishment__for_portion_of_valid both carry {postgres=arwdDxtm, authenticated=r, regular_user=arwdDxtm, admin_user=arwdDxtm}. PG 18 refuses to revoke a privilege directly from such a view, while pg_dump emits per-object ACL statements for it.

OPEN QUESTION, to determine rather than guess: is the unrestorable ACL state caused by 460's migration (something in it that makes sql_saga recreate or re-grant these views), or by the FULL_REPLAY path that built the f0486e26 seed after the incremental restore failed? Both are candidates; the evidence above does not yet separate them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Determine and record whether the unrestorable ACL state comes from 460's migration or from the FULL_REPLAY seed build path
- [ ] #2 A database at master's schema survives pg_dump -Fc + pg_restore --single-transaction --exit-on-error (a test proves it, RED before, GREEN after)
- [ ] #3 Images 'seed' job green on master again, so Fast Tests runs pg_regress
- [ ] #4 Any box already in this state can be backed up and restored (repair migration if the state is in deployed databases)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Coordinator: delegated to the 460 author (@nautilus) on 2026-10-08, because this blocks all CI pg_regress evidence and is a backup/restore risk. Diagnosis before fix: decide whether 460's migration puts the ACLs into an unrestorable state or whether the FULL_REPLAY seed build produces an unrestorable database, by dumping and restoring (a) a build made by replaying all migrations through 460 and (b) a build made by restoring the last known-good seed and then applying 460. Report the diagnosis before landing any fix.

DIAGNOSIS (nautilus, 2026-10-08, scratch DBs only, all dropped). Answers the OPEN QUESTION: neither (a) 460 putting ACLs into a bad state nor (b) the FULL_REPLAY path. It is a latent defect in sql_saga's health_checks() plus a long-standing statbus ACL divergence, exposed by a pg_dump ORDER shift that 460 causes.

1. Discriminator: clone of statbus_seed at master+460 -> pg_dump -Fc --no-owner --exclude-table-data=auth.secrets -> restore exactly like the seed build (target CREATE DATABASE ... TEMPLATE template_statbus + auth grants; pg_restore --clean --if-exists --no-owner --disable-triggers --single-transaction) FAILS with 'cannot revoke INSERT directly from establishment__for_portion_of_valid'. The same clone with ONLY 460's DOWN migration applied restores cleanly (rc 0). Harness: tmp/460/diag_restore.sh.
2. Bisect within 460: dropping existence_from/until(public.establishment) -> now fails on legal_unit__for_portion_of_valid; dropping the legal_unit pair -> fails on establishment; dropping the statistical_unit pair or the STATISTICS object -> still fails. The culprits are exactly the functions whose ARGUMENT TYPE is the row type of a sql_saga-managed table.
3. Mechanism (ordering, proven by diffing the two dumps' ACL pass): pg_dump emits ACLs in dependency order. A function taking a table's row type depends on that table's type, which pulls the table earlier. With 460, the ACLs of TABLE establishment / TABLE legal_unit are emitted BEFORE the last REVOKE in the ACL pass (REVOKE ALL ON FUNCTION public.upgrade_schedule(text, boolean) FROM PUBLIC): table grants at lines 49855/49864, REVOKE at 50040, view grants at 50470/50900. Without 460: REVOKE at 49871, table grants at 50286/50295. All other managed tables stay after the REVOKE.
4. What raises: sql_saga.health_checks() is an event trigger on ddl_command_end and runs for EVERY GRANT/REVOKE (sql_saga.__internal_ddl_command_affects_managed_object returns true for any GRANT/REVOKE because objid is unreliable). Its 'Check REVOKEs on for-portion-of views' branch requires every (grantee, privilege) ACL entry of the base table to appear EXACTLY in the view's ACL. At the failing statement the replayed state is establishment = {postgres, authenticated=r, regular_user, admin_user} and establishment__for_portion_of_valid = {postgres, authenticated=r, regular_user}, so an unrelated REVOKE raises.
5. Root cause of the divergence (pre-dates 460): sql_saga's GRANT propagation tests has_table_privilege(grantee, view, priv), which is inheritance-aware. admin_user inherits regular_user, so admin_user is never propagated to the views, while the REVOKE check uses exact aclexplode entries. On master WITHOUT 460, 7 of 9 for_portion_of_valid views (activity, contact, legal_relationship, location, person_for_unit, power_root, stat_for_unit) already lack admin_user, and a LIVE 'REVOKE ALL ON FUNCTION public.upgrade_schedule(text,boolean) FROM PUBLIC' fails today with 'cannot revoke INSERT directly from activity__for_portion_of_valid'. Restores only worked because those tables' ACLs happened to be emitted after the last REVOKE.
OWNERSHIP: the trigger is sql_saga's (extension sql_saga 1.0, built in postgres/Dockerfile from veridit/sql_saga @ 9e39fcc; source sql_saga/src/2h_health_checks.sql), with no GUC to configure it. Defect A (root) is in sql_saga: propagation and check disagree for inherited roles, and the check fires on unrelated REVOKEs. Defect B is statbus state: managed views whose ACL differs from their table. 460 itself is schema-only and correct; any function taking a temporal table's row type would trigger the same reorder.
PROTOTYPE: restoring with PGOPTIONS='-c session_replication_role=replica' (event triggers do not fire in replica mode): dump(seed+460) -> restore OK -> dump -> restore OK; md5 over all relation ACLs and public/auth/admin function ACLs identical across source, round trip 1 and round trip 2; all 8 event triggers still enabled ('O') afterwards.

PLAN (rabbit's order): B, then C, then D in statbus, each RED then GREEN. B = forward migration making each sql_saga.updatable_view view's ACL equal its table's ACL, derived from the live ACLs (replay-position independent), plus a derived pg_regress assertion (table ACL = view ACL for every updatable_view) and a live unrelated REVOKE that must succeed. C = pg_restore with session_replication_role=replica on the seed build AND the box restore path (./sb db restore). This is a restore-time accommodation, not a weakened check: live DDL stays fully guarded, and the evidence asserts all 8 event triggers are still enabled. D = dump -> restore -> dump -> restore round trip with an ACL md5 comparison in the seed build and fast CI, so the next ordering shift fails loudly instead of silently falling back to FULL_REPLAY. A (sql_saga: make the check inheritance-aware or the propagation exact, and bump sql_saga_release) is waiting on the owner.

C+D LANDED as 3ce591f16 (cli: restore dumps with event triggers suppressed, and prove the seed round-trips).
C: new restoreTargetConninfo(dbName) (cli/cmd/restore_replica.go) = libpq conninfo dbname='<db>' options='-c session_replication_role=replica'. Used by EVERY pg_restore that recreates a database: runSeedRestoreCmd (./sb db seed restore, which install and dev.sh recreate-seed use), restoreSeedDump (seed build incremental base), restoreVerifyDB (seed verify) and restoreLocal phases 1, 2.5 and 3 (./sb db restore, the box restore path). This is a RESTORE-TIME ACCOMMODATION, NOT A WEAKENED CHECK: the option applies only to the restore connection, the event triggers stay enabled in the catalog, and every live session afterwards is fully guarded by sql_saga.health_checks. (The upgrade rollback restores by rsync of the volume, not pg_restore, so it is unaffected.)
D: verifySeedRoundTrip (cli/cmd/seed_roundtrip.go), run by 'sb db seed build' right after DumpSeed: it restores the new seed.pg_dump into an empty template_statbus database through restoreSeedDump, dumps that database, restores the dump into a second empty database, and then requires the ACL digest (md5 over every non-system relation ACL and function ACL) to match the seed's for both, and enabled/total event triggers to match the seed's. It reuses the restore the build already does (two schema-sized restores, seconds) rather than adding a CI job, and an unrestorable seed now fails the Images seed job LOUDLY instead of surfacing as a silent FULL_REPLAY.
EVIDENCE: the real 'sb db seed build' in an isolated faux project (scratch dir, POSTGRES_SEED_DB=seedb481_seed, prior seed = master's statbus_seed dumped by 'sb db seed dump', so seed.json carries the real fingerprint). RED with master's binary: 'PATH=INCREMENTAL', then 'pg_restore: error: ... cannot revoke INSERT directly from "establishment__for_portion_of_valid"', then 'Error: restore prior seed: seed build restore prior: pg_restore reported errors', exit 1, identical to CI. GREEN with the fix, same prior: incremental restore OK, migrated, 'Seed dumped', then 'seed round trip (STATBUS-481): OK - seed -> restore -> dump -> restore; ACL digest ef9e4daffdaae68e1b1581c331cb3345 identical; event triggers enabled 8/8', exit 0. Box path: restoreLocal's phases 1, 2.5 and 3 replayed verbatim (same flags and TOC lists) on a scratch DB from the master+460 dump (tmp/460/replay_db_restore.sh). Phase 3 rc=1 with the old '-d dbname' (same error), rc=0 with the replica conninfo, event triggers 8/8 after. go vet and go test ./... green.

B PROVEN (not yet placed; the migration slot is held by 478's 20261008175137): migration text tmp/460/481B.up.sql grants on each sql_saga.updatable_view view every (grantee, privilege) ACL entry its base table has and the view lacks. It is derived from live ACLs (no grantee or table list), only adds, is idempotent (re-run: no-op), and issues its GRANTs under SET LOCAL session_replication_role = replica. Test test/sql/352_statbus_481_for_portion_of_view_acls.sql, run on a scratch clone of the test template (master at 20261008174433). RED without B: 352.2 lists 56 missing entries (admin_user x 8 privileges on activity, contact, legal_relationship, location, person_for_unit, power_root and stat_for_unit views); 352.3 'REVOKE ALL ON FUNCTION public.upgrade_schedule(text, boolean) FROM PUBLIC' -> ERROR cannot revoke INSERT directly from "activity__for_portion_of_valid". GREEN with B: 352.2 0 rows; 352.3 REVOKE succeeds; 352.4 a REVOKE that really breaks a view ACL (REVOKE INSERT ON activity__for_portion_of_valid FROM regular_user) is STILL refused by the health check (it stays active); 352.5 event triggers 8/8. Confirms rabbit's point: a dump of the B-repaired DB still fails the OLD restore path (phase 3 rc=1), so B fixes live DDL and C fixes restore; both are needed.

FOLLOW-UP FINDING (2026-10-08 ~20:13, recorded by the 473/477 worker because the swarm channel was unavailable): Images is red again from c4203d184 (478) on, and the cause is NOT 478 and NOT test 016.
- Images 37820407663 (c4203d184) and 37820481942 (580433a19): the seed job fails in the new round-trip check: "seed round trip FAILED: ACL digest of statbus_seed_roundtrip1 (c12608659628b8f03ec1119d9dce556c) differs from the seed's (cb527bae7494c7cb51cb97bd413afcc6): the restore lost or changed grants". Fast Tests 37821079712 and 37821150225 therefore report success with the 'pg_regress fast suite' job SKIPPED.
- Why it started there: 5bf1dc967's seed build was INCREMENTAL (restore of statbus-seed:3ce591f1 plus delta) and passed. c4203d184's build logged "incremental depth cap reached (prior depth 4 + 1 >= 5) - forcing full baseline", so PATH=FULL (from empty). It is the first FULL-replay seed since the round-trip check landed, and the round trip of a full-replay seed fails.
- Local reproduction (PG 18.6), independent of 478: pg_dump -Fc --no-owner of statbus_seed (master + 478), pg_restore --no-owner into a database created from template_statbus, then compare the round-trip check's per-object ACL list. Exactly ONE entry differs: upgrade_schedule(text,boolean) {postgres=X/postgres,admin_user=X/postgres} becomes '-'. The same single difference appears on a clone with 478 down-migrated, so 478 is not the cause. The restore log shows why: 'REVOKE ALL ON FUNCTION public.upgrade_schedule(p_commit_sha text, p_recreate boolean) FROM PUBLIC' fails with "cannot revoke INSERT directly from establishment__for_portion_of_valid, revoke INSERT from establishment instead", raised from sql_saga health_checks() line 364 (event trigger). That aborts the function's ACL statements. In this database establishment and establishment__for_portion_of_valid have IDENTICAL ACLs, yet health_checks() still raises on a REVOKE that targets an unrelated FUNCTION.
- Meaning: on a FULL replay (the path install.sh can also fall back to), the database still produces a dump whose restore loses a grant. This bears directly on this ticket's open question about the FULL_REPLAY path. The round-trip check is doing its job.
<!-- SECTION:NOTES:END -->

---
id: STATBUS-481
title: >-
  Database at master's schema produces an unrestorable dump: pg_restore refuses
  REVOKE on sql_saga for_portion_of_valid views (CI seed broken since e1387ff48)
status: In Progress
assignee: []
created_date: '2026-10-08 17:19'
updated_date: '2026-10-08 17:20'
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
<!-- SECTION:NOTES:END -->

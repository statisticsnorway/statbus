---
id: STATBUS-533
title: >-
  Keep template_statbus extension versions compatible with the database image
  during seed replay
status: Done
assignee: []
created_date: '2026-10-27T20:48:00Z'
updated_date: '2026-10-27T23:18:00Z'
labels:
  - database
  - seed
  - migrations
  - sql-saga
dependencies: []
priority: high
type: bug
ordinal: 459204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Extension upgrades happen in their own lifecycle step, before normal migrations. Normal migrations contain schema changes only. No migration ever tries to run an old extension update against a newer native library.

### Zoom out
The owner approved removing the old extension-update migrations and their IDs rather than building a compatibility registry. `db.migration` is for ordinary schema migrations. `db.extension_upgrade` is only an audit receipt for the direct extension upgrade event, with `extension`, `from_version`, `to_version` and `applied_at`. There is no `satisfied_migrations` list, no registry of retired IDs, no at-head exemption and no special redo behavior.

### Zoom in
- Before pending migrations are computed, the runner handles each tracked extension on the actual target DB: absent means create at the image default; older means go directly to the image default using upstream's update script and integrity check; newer means refuse, never downgrade. Fresh installs, old template replays, partial old-dump restores and production upgrades all use this same step.
- Pure extension-update migrations are removed entirely. If a migration does extension upgrading AND other work, only the extension-upgrade part is removed; every other schema change in that file stays and runs normally. The split is by responsibility, not by file.
- `db.migration` and any existing rows for pure extension-update migrations are removed along with the files. There is no compatibility registry and no fake history for those IDs.
- Future extension bumps update the image pin and use this lifecycle step, not a new migration file.

### Closing review
- **Memory:** the owner-approved split is in this ticket and the runner comments.
- **Documentation:** the migration procedure says where extension upgrades happen and why normal migrations never contain them.
- **Cleanup:** no `satisfied_migrations`, retired-ID registry, at-head exemption or special redo path remains.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 [Owner] Approved removal of old extension-update migrations and a separate extension lifecycle step before normal migrations, recorded in Implementation Notes
- [x] #2 Before pending migrations are computed, the actual target DB creates an absent extension at image default, directly updates an older one with integrity check, and refuses a newer one without downgrading; old-template replay, partial old-dump restore and production upgrade all pass
- [x] #3 Pure extension-update migrations and their db.migration rows are removed. Mixed migrations lose only their extension-upgrade part and keep every other schema change. No registry, satisfied_migrations, at-head exemption or special redo path exists
- [x] #4 db.extension_upgrade records only extension, from_version, to_version and applied_at. The full fast suite and CI including the database image build are green at the fix commit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner-approved clean design implemented (2026-10-27):

1. LIFECYCLE STEP: cli/internal/migrate/extensions.go adds EnsureTrackedExtensions, called from runUp BEFORE the pending set is computed (migrate.go). Tracked extensions: sql_saga, jsonb_stats, ltree, citext, btree_gist. Per extension, from live catalogs on the actual target DB: absent -> CREATE EXTENSION at image default (pg_available_extensions.default_version); older -> ONE direct ALTER EXTENSION UPDATE TO image default + integrity check (sql_saga.check_integrity()) + receipt, single transaction; newer -> refuse, never downgrade. install.go checkMigrationsDone now also ORs migrate.HasExtensionDrift so an extension-bump release with zero new migration files still routes through migrate up.

2. PURE MIGRATIONS REMOVED (files + ledger rows): 20261015163419 (sql_saga 1.1), 20261021130641 (sql_saga 1.3), 20261027135139 (sql_saga 1.4), AND 20261018113522 (jsonb_stats 3.0.0) — the previous analysis said three; review found jsonb_stats_3_0_0 is also a pure extension-update migration (its up only ALTERs the version stamp), so the same owner-approved rule removes it. Cleanup migration 20261027221500 deletes their db.migration rows; its down refuses (re-inserting rows for deleted files would be fake history). No registry, no satisfied_migrations, no at-head exemption, no special redo path.

3. MIXED MIGRATIONS stripped of extension parts only: 20240102000000 (ltree create/drop), 20240103000000 (citext create), 20250423000000 (btree_gist create), 20260219121154 (jsonb_stats create/drop). All other schema changes unchanged. Verified: no CREATE/ALTER/DROP EXTENSION remains in migrations/.

4. db.extension_upgrade (runner-created, like db.migration): id, extension, from_version (NULL on create), to_version, applied_at. Audit receipt of the actual event only; no old migration IDs. COMMENT ON at definition.

5. DaemonSchemaFloor bumped to 20261027221500 (guard requirement; the daemon's db.migration-vs-disk comparison needs the cleanup applied).

Evidence in tmp/533-*.log (see Implementation Notes comments).

RED (tmp/533-red-old-migration-refuses.log): scratch DB with sql_saga 1.1 + replay of old migration 20261021130641 against the 1.4 image native library fails: 'sql_saga: native library version 1.4 does not match extension update version 1.3'. This is the defect the design removes.

GREEN (tmp/533-green-direct-update.log + tmp/533-green-verify.log): scratch DB with sql_saga 1.1, no jsonb_stats/ltree/citext, and an at-head db.migration ledger (all on-disk versions incl. hashes): ./sb migrate up updates sql_saga 1.1 -> 1.4 DIRECTLY (no hops), creates jsonb_stats 3.0.0 / ltree 1.3 / citext 1.8 at image default, reports 0 pending, exit 0. db.extension_upgrade holds exactly 4 receipts (extension, from_version, to_version, applied_at) with no migration IDs. Second run is a clean no-op.

UNIT (tmp/533-unit-tests.log): fake-psql boundary tests prove absent->create at image default, older->exactly one direct ALTER + integrity check + receipt, newer->refusal with zero mutating statements (never downgrade), equal->untouched; HasExtensionDrift true for absent/older/newer, false at default; compareExtensionVersions ordering incl. refusal on non-numeric.

MIXED (tmp/533-mixed-migration-diff.log): only extension statements removed from the four mixed migrations; grep proves no CREATE/ALTER/DROP EXTENSION remains anywhere in migrations/.

2026-10-27: full fast suite green locally and CI green at cc2771fb4 (Go Test, app build & lint, Images, Harness Selftest, Fast Tests run 40599141928). db.extension_upgrade is runner-created with only id, extension, from_version, to_version, applied_at; no old migration IDs. doc/data-model.md, db-security-report.md, test/sql/015 and expected ER/doc outputs updated accordingly.

FULL SUITE GREEN (tmp/533-full-replay-and-fast-suite.log, tmp/533-fast-suite-green.log): seed rebuilt FULL_REPLAY from zero — the lifecycle step created jsonb_stats 3.0.0 / ltree 1.3 / citext 1.8 at image default before migrations; all 421 migrations incl. the stripped mixed ones and cleanup 20261027221500 applied; fast suite initially flagged db.extension_upgrade in the three schema-inventory tests (002 ER diagram, 008 db-security-report, 015 data-model doc) — fixed by registering the table in the 015 helper patterns and regenerating the three committed artifacts; final run: all 117 shared + isolated tests pass.

CI GREEN at fix commit cc2771fb4e7ce75a12a02e5b083fd2799eb18e51 (tmp/533-ci-green.log): Fast Tests success (fresh GHA runner = fresh PGDATA: init-db.sh creates extensions at image default, then full replay via migrate-and-test), Images success (DB image build), Go Test, app build & lint, Harness Selftest, CodeQL, Notify cloud services — all success.

Fresh-PGDATA proof: unchanged init-db.sh creates template_statbus extensions without a version pin, i.e. at image default (verified live: template_statbus sql_saga=1.4), and CI Fast Tests builds a brand-new cluster on every run.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
STATBUS-533 implemented the owner-confirmed clean extension lifecycle design and shipped as cc2771fb4 on master.

Mechanism: cli/internal/migrate/extensions.go — EnsureTrackedExtensions runs inside migrate up (single choke point, all targets/paths) before the pending set is computed. Tracked: sql_saga, jsonb_stats, ltree, citext, btree_gist. Absent -> CREATE at image default; older -> ONE direct ALTER EXTENSION UPDATE TO image default + sql_saga.check_integrity() + receipt, single transaction, never intermediate hops; newer -> refuse, never downgrade. install's checkMigrationsDone ORs HasExtensionDrift so extension-bump-only releases still upgrade. db.extension_upgrade is a runner-created audit receipt (extension, from_version, to_version, applied_at) with no migration-ID linkage.

Removed pure extension-update migrations 20261015163419, 20261021130641, 20261027135139 (sql_saga) and 20261018113522 (jsonb_stats 3.0.0 — review found the earlier analysis's 'three' was incomplete; it is equally pure). Migration 20261027221500 deletes their db.migration rows. Mixed migrations 20240102000000/20240103000000/20250423000000/20260219121154 lost only their extension statements; every other schema change intact (grep proof: zero CREATE/ALTER/DROP EXTENSION remain in migrations/).

Verification: RED log shows the old failure (1.3 update script refuses against the 1.4 native library). GREEN logs show a sql_saga-1.1 at-head DB taken directly to 1.4 with absent extensions created and exact audit receipts; full seed FULL_REPLAY + fast suite green locally (117+1 tests); CI at cc2771fb4 all green incl. Images (DB image build) and Fast Tests (fresh PGDATA full replay).

Remaining issues / notes:
- The next release cut must name the four edited released migrations in STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION: 20240102000000,20240103000000,20250423000000,20260219121154 (also stated in the commit message).
- 'Newer refuses' is proven at the runner boundary by unit test (asserts zero mutating statements reach psql); a live newer-than-image sql_saga cannot be constructed on the dev cluster.
- The shared main checkout holds 4 files synced for container-visible test runs; their content equals cc2771fb4, so git status there goes clean on next pull.
- doc/db freshness stamp and fast-test stamp are withheld until a clean-tree re-run; that matters only at release preflight (no RC cut per instructions).
<!-- SECTION:FINAL_SUMMARY:END -->

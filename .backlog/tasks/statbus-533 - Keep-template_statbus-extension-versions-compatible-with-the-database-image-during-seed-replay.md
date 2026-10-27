---
id: STATBUS-533
title: >-
  Keep template_statbus extension versions compatible with the database image
  during seed replay
status: In Progress
assignee: []
created_date: '2026-10-27T20:48:00Z'
updated_date: '2026-10-27T22:27:00Z'
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
- [ ] #1 [Owner] Approved removal of old extension-update migrations and a separate extension lifecycle step before normal migrations, recorded in Implementation Notes
- [ ] #2 Before pending migrations are computed, the actual target DB creates an absent extension at image default, directly updates an older one with integrity check, and refuses a newer one without downgrading; old-template replay, partial old-dump restore and production upgrade all pass
- [ ] #3 Pure extension-update migrations and their db.migration rows are removed. Mixed migrations lose only their extension-upgrade part and keep every other schema change. No registry, satisfied_migrations, at-head exemption or special redo path exists
- [ ] #4 db.extension_upgrade records only extension, from_version, to_version and applied_at. The full fast suite and CI including the database image build are green at the fix commit
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
<!-- SECTION:NOTES:END -->

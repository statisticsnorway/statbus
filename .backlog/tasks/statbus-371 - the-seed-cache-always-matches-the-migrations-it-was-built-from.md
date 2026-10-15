---
id: STATBUS-371
title: A cached seed never holds a migration version the code no longer has
status: In Progress
assignee: []
created_date: '2026-09-16 22:34'
updated_date: '2026-10-15 16:48'
labels:
  - release-bug
  - migrations
  - ci
  - fail-fast
dependencies: []
priority: high
type: task
ordinal: 9
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A cached database seed never holds a migration version that the code no longer has, so restoring a seed and then migrating always applies each migration exactly once.

### Zoom out
A migration version becomes part of history the moment any seed may have recorded it, not when a release ships it. Images publishes a seed for every master push, so a version can sit in a retained seed long before any release candidate contains it. Two defences follow:
- **Consumption:** a build that finds a cached seed incompatible with its migrations rejects it before restoring and falls back to a full replay.
- **Prevention:** a release candidate that renumbers or removes a version that may already live in a retained seed is refused. The fix is to restore the original version and add a forward migration.

Prevention needs one authority for "versions that may live in a retained seed". It must be immutable history, not mutable registry contents, because deleting or expiring an image would erase the evidence the guard relies on. The chosen authority is every migration version visible on master's first-parent history since the previous release tag: that is exactly where seeds are published and where builds look for them. Older versions are already frozen by the released-migration immutability check.

### Zoom in
- **Incident, 2026-09-16:** migration `20260903205636` (STATBUS-347) was retimestamped to `20260907120000` in `f6d249b62`. Niue's cached seed still held the old version and its `rollback_finish_pending_at` column. The content-hash check ignored ledger rows with no file, so the cache was accepted, replay re-added the column, and pg_regress failed every commit after rc.11 with `column rollback_finish_pending_at already exists`.
- **Consumption fix:** `aaaaee881` (fail-closed compatibility check before `pg_restore`), `23b3993ad` (rejected cache falls back to full replay). Niue run `35116209731`: stale cache rejected, full replay, 100/100 passed.
- **Prevention guard:** `06ec54f40`, `5473e68ea`, shipped in v2026.09.3. `release.MissingSeedLineageMigrations` (`cli/internal/release/seed_lineage.go`) is called from the prerelease preflight (`cli/cmd/release/release.go`, `checkSeedLineageGuardAgainst`) and the tag validator (`cli/cmd/release/release_verify.go`). The refusal names the version, its first commit and original path.
- **Authority grounding:** Images publishes `statbus-seed:payload-<sha>` only on master push (`.github/workflows/images.yaml`); builds choose a prior seed by walking first-parent ancestors (`cli/cmd/seed_ancestor.go`).
- **Known edge:** a manual `workflow_dispatch` of Images on a non-master commit could publish a seed outside the first-parent line. Builds never select it, so it is not consumed.

### Closing review
- **Memory:** none needed.
- **Documentation:** the authority rationale lives here and in the `seed_lineage.go` doc comment; no separate doc.
- **Cleanup:** the earlier criterion asking for a test that a decision document exists was removed as a text-presence check (previous wording in Git at `ea170989e`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A release candidate that removes or renumbers a version seen on first-parent history since the previous release is refused, naming the version, first commit and original path (`TestMissingSeedLineageMigrationsRejectsPrereleaseRenumber`, `...RejectsPrereleaseRemoval` in `cli/internal/release/seed_lineage_test.go`)
- [x] #2 Additions and description-only renames that keep the version pass the guard (`TestMissingSeedLineageMigrationsAllowsAdditionsAndSameVersionRename`)
- [x] #3 An incompatible cached seed is rejected before restore mutates anything, and the build falls back to full replay where permitted (`TestRunSeedRestoreCmd_ValidatesCacheBeforeRestoreMutation`, `TestClassifySeedRestoreErrorFallsBackForIncompatibleCache` in `cli/cmd/`)
- [ ] #4 Owner decision: first-parent master history since the previous release tag is the authority for versions that may live in a retained seed. Yes closes this ticket. No names the replacement authority and reopens the guard work.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** shipped in v2026.09.3 (`06ec54f40`, `5473e68ea`); green in Go Test `36503468493`; re-run green locally on master `cb34436b4`, 2026-10-15.
- **AC4:** open; the only remaining work, and it needs no code.
<!-- SECTION:NOTES:END -->

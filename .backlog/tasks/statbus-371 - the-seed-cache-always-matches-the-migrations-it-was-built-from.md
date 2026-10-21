---
id: STATBUS-371
title: A cached seed whose migrations changed is never restored or built on
status: Done
assignee: []
created_date: '2026-09-16 22:34'
updated_date: '2026-10-21 11:58'
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
Restoring a cached seed and then migrating gives the same database as a full replay, even when a migration already on master is later renumbered, edited or removed.

### Zoom out
The seed is a speed shortcut: a dump at a commit, restored in seconds instead of replaying every migration. It is published for each master push and used by developer builds, CI and the next incremental seed build. No installed box runs untagged master, so master-only migrations reach seeds and laptops, not deployments.

Accidents happen. A migration on master can need renumbering or removal before release. The protection sits where the seed is used:
- **Restore:** a cached seed whose migrations no longer match the checkout is rejected before anything is written, and the build replays every migration.
- **Seed build:** a prior seed whose migrations changed is not built on; the next seed starts from empty.
The cost of an accident is a slower build, never a wrong database.

### Zoom in
- **Incident, 2026-09-16:** migration `20260903205636` (STATBUS-347) was retimestamped to `20260907120000` in `f6d249b62`. Niue's cached seed still held the old version. The restore path had no check, so the cache was accepted and diverged.
- **Fix:** the migrations fingerprint (`seed.json` `migrations_fingerprint`, `migrate.UpMigrationsFingerprintUpTo`, since STATBUS-116) covers version, order and content of every migration up to the seed's version. `aaaaee881` checks it before restore (`validateCachedSeedForRestore`); `23b3993ad` falls back to full replay. `SeedBuildDecision` uses the same fingerprint to choose incremental or full. Niue run `35116209731`: stale cache rejected, full replay, 100/100 passed.
- **Removed, owner 2026-10-21:** a release-time guard (`06ec54f40`, `5473e68ea`) refused any candidate that renumbered or removed a migration seen on master since the last release, with no override. It added no protection beyond the fingerprint and made an unreleased mistake impossible to fix. Removed in `e6a912a4d`. The released-migration immutability check keeps its declared override (`STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION`).

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed. The fingerprint's doc comment in `cli/internal/migrate/fingerprint.go` states its purpose.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An incompatible cached seed is rejected before restore mutates anything, and the build falls back to full replay where permitted (`TestRunSeedRestoreCmd_ValidatesCacheBeforeRestoreMutation`, `TestClassifySeedRestoreErrorFallsBackForIncompatibleCache` in `cli/cmd/`)
- [x] #2 A seed build whose prior seed's migrations were edited or removed starts from empty instead of building on it (`TestSeedBuildDecision_FullWhenPrefixMigrationEdited`, `TestSeedBuildDecision_FullWhenPrefixMigrationRemoved` in `cli/cmd/`)
- [x] #3 No release gate refuses a candidate for renumbering or removing an unreleased migration: the seed lineage guard is removed (`e6a912a4d`), release and migrate tests green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** shipped in v2026.09.3 (`06ec54f40`, `5473e68ea`); green in Go Test `36503468493`; re-run green locally on master `cb34436b4`, 2026-10-15.
- **AC4:** open; the only remaining work, and it needs no code.

### Owner decision 2026-10-21: remove the release guard
The release-time seed lineage guard encoded that an accident cannot happen, with no escape hatch. Accidents are made rare by tests and practice, and their cost is contained where the seed is used: the fingerprint rejects a mismatched seed before restore and the build replays every migration, and the next seed build starts from empty. Removed in e6a912a4d: `cli/internal/release/seed_lineage.go` with its tests, the calls in `release.go` (prerelease preflight) and `release_verify.go` (tag validator), and its exec inventory entry. Duplicate migration versions stay caught by `migrate.listMigrationFiles` (`TestListMigrationFilesDuplicateStillErrors`).
### Evidence 2026-10-21
- `go test ./cmd/release/ ./internal/release/ ./internal/upgrade/ ./internal/migrate/` ok, golangci-lint 0 issues (`tmp/371-remove-guard.log`).
- `TestSeedBuildDecision_*`, `TestRunSeedRestoreCmd_ValidatesCacheBeforeRestoreMutation` and `TestClassifySeedRestoreErrorFallsBackForIncompatibleCache` green.
<!-- SECTION:NOTES:END -->

---
id: STATBUS-526
title: >-
  Incremental seed build must detect extension-version changes (sql_saga 1.3
  broke Images)
status: Done
assignee: []
created_date: '2026-10-21 23:08'
updated_date: '2026-10-21 23:36'
labels:
  - bug
  - ci
dependencies: []
priority: high
type: bug
ordinal: 452204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
An incremental seed build never restores a prior seed dump into an image whose extension set differs from the one that produced it.

### Zoom out
The STATBUS-116 incremental seed gate (SeedBuildDecision) fingerprints only migrations. The sql_saga 1.3 bump (STATBUS-519) changed the db image's extension libraries: the seed-builder restored the prior seed (built on the v1.1 image) into the v1.3 image, and sql_saga 1.3's catalog guard CHECK ("restore old sql_saga dumps per doc/upgrade.md") refused the COPY of sql_saga.era. The Images job failed on the STATBUS-519/524 commit (run 39683421483).

The incremental path restores the prior dump's extension catalog rows verbatim, so it is only valid when both images install the same extension versions. Extension bumps are exactly the commits where incremental is invalid.

### Zoom in
- Record the image's extension identity (sorted name=default_version list from pg_available_extensions) in seed.json at dump time.
- Gate the incremental path on it: absence (pre-field seed.json) or mismatch forces a full rebuild, with the reason in the loud decision log.
- Backstop: if the prior restore fails anyway, drop the half-restored seed db (single-transaction restore rolls back) and rebuild full from empty, mirroring the STATBUS-116 Part C stale-prior fallback. Full from-empty is always correct; the restore is only an optimisation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An extension version bump between the prior seed's image and the current image forces a full seed rebuild (no incremental restore), with the reason in the build log
- [x] #2 A prior seed restore that fails for any reason falls back loudly to a full rebuild instead of failing the build
- [x] #3 seed.json records the image's extension versions; Go tests pass; CI Images job for the STATBUS-519/524 commit goes green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Verification 2026-10-21 (frog)
- Unit tests TestSeedExtensionDecision_* cover match/mismatch/missing-prior/missing-current (cli/cmd/seed_decision_test.go); `go test ./cmd/` and `go build ./... && go vet ./cmd/` pass.
- CI Images run 39691713860 (commit 59b2bbefe): seed build logged 'prior-present=true decision-incremental=true -> PATH=FULL (from empty), reason: prior seed predates extension-version recording (STATBUS-526)', then a full build dumped the seed at migration 20261021143000 and the job went green. The restore-failure backstop was not needed (the gate fired first).
<!-- SECTION:NOTES:END -->

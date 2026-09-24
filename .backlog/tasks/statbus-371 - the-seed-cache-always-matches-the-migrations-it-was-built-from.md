---
id: STATBUS-371
title: Retained seed lineages preserve every migration version they may contain
status: In Progress
assignee: []
created_date: '2026-09-16 22:34'
updated_date: '2026-09-24 18:45'
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

## Status 2026-09-24

**In Progress:** `dd30f3167` (`06ec54f40`, `5473e68ea`) adds `cli/internal/release/seed_lineage.go` and `seed_lineage_test.go` for #1-3 by equivalent tests. #4 pre-mutation cache/fallback tests need separate confirmation; #5 named owner-authority test and `doc/seed-lineage-authority.md` are absent. **Remaining:** prove cache rejection/fallback and record the authoritative retained lineage with owner approval.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

The prerelease gate preserves every migration version visible in the authoritative retained seed lineage. A candidate that removes or renumbers one of those versions is rejected and directed to restore it plus add a forward migration. Cache consumption separately rejects incompatible cached history and falls back to full replay where that fallback is permitted. Renumbering does not itself rebuild a cache.

## Evidence, 2026-09-24

The merged prerelease guard rejects retained migration renumbering (`cli/cmd/release/release.go:892-909` and `cli/cmd/release/release_verify.go:265-276` at master `7a9cf707e`). The current authoritative lineage is the first-parent union after the previous release baseline (`cli/internal/release/seed_lineage.go:15-37` at master `7a9cf707e`), with its retained-version cases in `cli/internal/release/seed_lineage_test.go`. Incompatible-cache validation precedes restore mutation (`cli/cmd/seed_cache_test.go:52-87`), while permitted full-replay fallback is classified by `cli/cmd/seed_gate_test.go:11-23`, both at master `7a9cf707e`. Earlier repair commit and CI-run claims remain unverified and are not part of the operative evidence.

The owner decision on the first-parent retained-lineage choice remains open. Mutable registry contents are not the authority because deletion or expiry could remove the history used by the gate. This rationale is target policy pending owner confirmation.

## Acceptance Criteria

- [ ] #1 `cli/internal/release/seed_lineage_test.go::TestMissingSeedLineageMigrationsRejectsPrereleaseRenumber` identifies the retained version, first commit, and original path and rejects renumbering.
- [ ] #2 `cli/internal/release/seed_lineage_test.go::TestMissingSeedLineageMigrationsRejectsPrereleaseRemoval` rejects removal from retained first-parent history.
- [ ] #3 `cli/internal/release/seed_lineage_test.go::TestMissingSeedLineageMigrationsAllowsAdditionsAndSameVersionRename` preserves the version while allowing additions and description-only path changes.
- [ ] #4 `cli/cmd/seed_cache_test.go::TestRunSeedRestoreCmd_ValidatesCacheBeforeRestoreMutation` and `cli/cmd/seed_gate_test.go::TestClassifySeedRestoreErrorFallsBackForIncompatibleCache` prove pre-mutation incompatibility rejection and permitted full-replay fallback.
- [ ] #5 `new: cli/internal/release/seed_lineage_authority_test.go::TestOwnerDecisionNamesAuthoritativeRetainedLineage` verifies `new: doc/seed-lineage-authority.md::owner-decision` records owner confirmation or a concrete replacement authoritative lineage before this ticket is complete.

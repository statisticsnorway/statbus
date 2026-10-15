---
id: STATBUS-362
title: Live-database tests drive a pinned sb in their own scratch worktree
status: In Progress
assignee: []
created_date: '2026-09-07 17:26'
updated_date: '2026-10-15 19:53'
labels:
  - harness
  - testing
  - upgrade
dependencies:
  - STATBUS-361
priority: medium
type: task
ordinal: 70
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A live-database test always drives the exact `sb` binary it started with, in its own scratch checkout, so nothing else on the machine can change what is under test halfway through.

### Zoom out
Live-database tests run real `sb` subcommands against a real local database. They used to execute the project's own `./sb`, a file that a concurrent rebuild or a raw `go build` can replace at any moment. Then the test silently drives a different program, which can leave the developer's database in a state no test meant to create. The cure is isolation: each test package gets a detached worktree with its own generated settings, builds an identity-bearing `sb` once, and drives only that pinned copy. Tests never write the developer's own `.env`.

These tests are also a distinct tier, so they are selected by what they need (a real database), not by a runtime environment flag that lets them compile and skip silently in ordinary runs.

### Zoom in
- **Incident, 2026-09-07 (STATBUS-354 review):** an identity-less `./sb` (no `cmd.commit`) appeared mid-run; every mutating subcommand then exited 69 after the first test had applied a real down migration, leaving `statbus_local` below the daemon floor (`tmp/STATBUS-354-stale-sb-investigation.md`).
- **Owner-approved design (2026-09-07):** a git worktree per test package, part of the Fast Tests workflow.
- **Shipped (v2026.09.3):** `ee25738b0`, `b0128bc7f`, `240fa0a92`, `dbeec8153`: `cli/internal/livedbtest` builds pinned scratch worktrees with a private `HOME` and generated scratch `.env`; 25 live files carry `//go:build livedb` (38 tests); `./dev.sh test-livedb` runs them, and Fast Tests calls it. The manual stable-release check is isolated under its own `release_live` tag.
- **Proof:** `TestPinnedSBIgnoresProjectBinaryReplacement` (`cli/internal/upgrade/live_prune_test.go`) replaces the project `./sb` with a script that exits 99 and requires the run to be unaffected. The Fast Tests step "Live-database tests" is green (`36505196729`). The two remaining `filepath.Join(projDir, "sb")` uses in live tests are fixtures that deliberately read or replace the project file, not execution.
- **Provisional names:** build tag `livedb`, tier name "live-database tests", and 25 claim-based test names (table in the notes), implemented 2026-09-24 as provisional until the owner confirms.

### Closing review
- **Memory:** none needed.
- **Documentation:** `doc/DEVELOPMENT.md` describes `./dev.sh test-livedb`.
- **Cleanup:** the 2026-09-07 to 09-24 design and sequencing sections were folded in here; full text in Git history.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No live-database test executes the project `./sb`; each drives a pinned binary built once in its own scratch worktree, and never writes the project `.env`
- [x] #2 `TestPinnedSBIgnoresProjectBinaryReplacement` proves a mid-run replacement of the project `./sb` does not change the binary under test
- [x] #3 Live tests are selected by the `livedb` build tag, compiled out of ordinary `go test ./...`, and run as the "Live-database tests" step of Fast Tests (green in `36505196729` and on master `f1e7dcfba`, run `38771500938`, 2026-10-15)
- [ ] #4 Owner decision: confirm the provisional build tag `livedb`, tier name "live-database tests" and the 25 claim-based test names (notes), or name what to change. Confirmation closes this ticket.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** shipped in v2026.09.3; Live-database tests step green on master run `38771500938` (2026-10-15).
- **AC4:** open.

### Provisional names (implemented 2026-09-24, awaiting owner confirmation)

Rule: a name states the claim the assertions prove, nothing more or less.
Provenance (ticket numbers) goes in a comment. `_Helper` marks a subprocess
entry point, not a claim. Terra (pristine) judged the draft against each
test body: 15 accurate, 6 underclaim, 3 overclaim, 1 wrong subject; the
eight corrected names below are Terra's (`tmp/STATBUS-362-naming-judgment.md`).

| # | today | final | |
|---|---|---|---|
| 1 | `TestLiveAbortFailedPreBackupStop` | `TestUpgradeAbortBeforeBackupLeavesRowFailedWithNoBackupPath` |  |
| 2 | `TestLiveCleanupActorRaceStaleLoserCannotMutate_STATBUS354` | `TestCleanupRaceStaleLoserCannotMutate` |  |
| 3 | `TestLiveCompleteInProgressUpgrade_FlaglessBehindClaimsAndRollsBack` | `TestUpgradeFlaglessBehindRowRollsBack` | Terra-corrected |
| 4 | `TestLiveCompleteInProgressUpgrade_FlaglessBehindHelper` | `TestUpgradeFlaglessBehindRow_Helper` |  |
| 5 | `TestLiveDetect_PendingRollbackIsCrashedNotReattempt` | `TestInstallDetectsPendingRollbackAsCrashedNotReattempt` |  |
| 6 | `TestLiveEnumTwins` | `TestUpgradeFailureCodeEnumMatchesGoConstants` |  |
| 7 | `TestLiveExecObserved_ConstraintRejectionIsOnTheJournal` | `TestUpgradeConstraintRejectionAndZeroRowUpdateAreJournaled` | Terra-corrected |
| 8 | `TestLiveFloorFailureHoldAndHumanRetry_STATBUS354` | `TestRollbackFloorFailureHoldsUntilHumanRetryThenRecovers` | Terra-corrected |
| 9 | `TestLiveFloorSuccessBeforePendingStepRollbackWins_STATBUS354` | `TestRollbackStepWinsOverAtFloorLedger` | Terra-corrected |
| 10 | `TestLiveMaintenanceFile_ExtractorCommandRunsAgainstTheRealRow` | `TestMaintenanceFileExtractorReadsTheLiveRow` |  |
| 11 | `TestLiveMigrationCommitBeforeLedgerRestoreRetry_STATBUS354` | `TestMigrationFloorReapplyAfterPreColumnSnapshotRecordsOneLedgerRow` | Terra-corrected |
| 12 | `TestLivePendingCleanupMarkerPreservesSentinel_STATBUS354` | `TestCleanupMarkerPreservesSentinelData` |  |
| 13 | `TestLivePreColumnSnapshotAdoptionRollback_STATBUS354` | `TestRollbackFromPreColumnSnapshotReappliesFloor` |  |
| 14 | `TestLivePreswapFetchReturnedErrorRealSite_STATBUS339` | `TestUpgradePreswapFetchErrorMarksUpgradeFailed` | Terra-corrected |
| 15 | `TestLivePruneDeletedTags_AllPrunedRowLands` | `TestPruneDeletedTagsRecordsAllPrunedRow` |  |
| 16 | `TestLiveReattemptRestore_DelayedSecondInstallCannotRestoreAgain` | `TestRestoreReattemptSecondActorCannotRestoreAgain` |  |
| 17 | `TestLiveRecoverFromFlag_PendingRollbackNeverRestores` | `TestRecoveryWithPendingRollbackNeverRestoresSnapshot` |  |
| 18 | `TestLiveRecoveryRollback_StaleActorCannotRecreateMarker` | `TestRecoveryStaleActorCannotRecreateMarker` |  |
| 19 | `TestLiveRecoveryRollback_StaleActorHelper` | `TestRecoveryStaleActor_Helper` |  |
| 20 | `TestLiveRestoreAndFinalize_HealthyTail` | `TestRollbackFinalizeHealthyTailCommitsAndUnlinks` |  |
| 21 | `TestLiveRestoreAndFinalize_UnlinkFailureThenRecovery` | `TestRollbackFinalizeUnlinkFailureRecoversCleanupOnly` |  |
| 22 | `TestLiveRollbackFinishing` | `TestRollbackFinishBlocksClaimsThenFinalizesAndAllowsClaims` | Terra-corrected |
| 23 | `TestLiveRollbackFinishing_ExternalWritesReopen` | `TestRollbackFinishReopensExternalWrites` |  |
| 24 | `TestLiveStablePreflight` | `TestReleaseStablePreflightGates` |  |
| 25 | `TestLiveTerminalRowCleanupMarkerPublishesSourceBinary_STATBUS354` | `TestCleanupAfterTerminalRowRemovesMarkerAndRetainsRow` | Terra-corrected |

2026-10-15 count check: all 25 provisional names in the table exist as test functions on master. The livedb tier now has 38 tests in 25 files; the other 13 were added after the table under their own claim-based names, so the table covers the original 25 renames only.
<!-- SECTION:NOTES:END -->

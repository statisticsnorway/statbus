---
id: STATBUS-362
title: >-
  live tests drive the mutable on-disk ./sb: pin the binary they start with
status: To Do
assignee: []
created_date: '2026-09-07 17:26'
updated_date: '2026-09-15 08:04'
labels:
  - testing
  - upgrade
dependencies: []
priority: medium
type: task
---

## Ground truth (2026-09-07)

`live_statbus354_crash_twins_test.go` (and other `STATBUS_LIVE_DB=1` tests) invoke
`filepath.Join(projDir, "sb")` directly. That file is mutable: any concurrent
rebuild, or a raw `go build` without dev.sh's `cmd.commit` ldflag, changes what
the test is driving mid-run. Observed 2026-09-07 during the 354 review: an
identity-less `./sb` (`vcs.modified=true`, no `cmd.commit`) made every mutating
subcommand exit 69 after twin 1 had applied a real down migration, leaving
`statbus_local` below the daemon floor. Investigation:
`tmp/STATBUS-354-stale-sb-investigation.md`.

## What to do

Live tests build (via the same ldflags dev.sh uses) or copy the binary once at
test start into a temp path and drive THAT for the whole run. Add one test that
proves a mid-run replacement of `./sb` does not change the binary under test.

## Done when

- No live test references `filepath.Join(projDir, "sb")` for execution.
- The pinning test passes; full live suite green.

## Not this ticket

The freshness guard itself is correct (`cli/`-scoped). Do not widen or weaken it.

## Scope addition (2026-09-07 21:03): tests must never write the project's .env

`TestLiveReattemptRestore_DelayedSecondInstallCannotRestoreAgain`
(`cli/internal/upgrade/live_reattempt_race_test.go`) puts a fake `git` on
PATH that answers `rev-parse` with `1111…1111`, then lets the code under test
run `sb config generate` against the REAL project dir. Result on 2026-09-07:
the developer's `.env` carried `COMMIT_SHORT=1111…` and `VERSION=shim git:
describe …` from 16:38 until the RC cut at 20:47, and `build-sb` tried to
pull seed image `statbus-seed:1111…`. Owner ruling: unprincipled. Rule: a
live test gets a scratch project dir (copy of the tree, own `.env`) or it
does not exercise config generation. Same family as the stale-`./sb`
problem this ticket already covers; fix together.

## Design (owner-approved 2026-09-07 21:33): git worktree per test package

Root cause of both symptoms: live tests use the developer's checkout as the
daemon's project directory, so the daemon's ordinary behaviour (execute
`./sb`, `config generate` writing `.env`, publish `sb.old` over `sb`)
mutates the tree the developer is working in.

The daemon's project-dir surface is small and known (`grep filepath.Join
(projDir` in non-test code): `tmp/`, `.env`, `.env.config`,
`.env.credentials`, `sb`, `sb.old`, `migrations/`, `ops/`, `caddy/`,
`.db-seed/`, `dbdumps/`.

Per package, once, in `TestMain` when `STATBUS_LIVE_DB=1`:

1. `git worktree add --detach $tmp HEAD` (exactly one commit; uncommitted
   edits excluded by construction).
2. Copy `.env.credentials` from the real tree; run `sb config generate` in
   the worktree so the worktree's `.env` is written by real `git`, no fake
   SHAs. The generated `.env` points at the same local database as today.
3. `go build` with the ldflags dev.sh uses (`cmd.commit`, version) to
   `$tmp/sb`. Every test drives that path; the real `./sb` is never executed
   by a test again.
4. `findProjDir` returns `$tmp`; cleanup is `git worktree remove --force`.

Unchanged: `docker compose` stays shimmed on PATH (tests never touch the
developer's containers); the shared local DB and the cross-package flock
stay. Containerising the daemon was considered and rejected: it buys nothing
the worktree does not and makes the shims harder.

Consequences: `live_reattempt_race_test.go` drops its fake `git` entirely
(the version it wants is the worktree's real HEAD). The freshness guard on
`./sb` is untouched.

Guard tests:
- Replace the real `./sb` with `exit 99` while a live test runs; the test's
  binary is unaffected.
- After the live suite: `git status --porcelain` in the real tree is empty
  and `.env` is byte-identical to before.

## Workflow integration (owner-approved 2026-09-07 21:35): part of this ticket

Fast Tests (`fast-tests.yaml`, GitHub runner `ubuntu-24.04`) already has
services up, a migrated DB, and one Go test against that live DB (the daemon
floor oracle). Add one step after it:

    STATBUS_LIVE_DB=1 go test -C cli -count=1 -run 'TestLive' \
      ./internal/upgrade ./internal/install

Runtime ~2-4 min on top of the run. No change to `release prerelease`:
check 7 already reads Fast Tests green at HEAD, so the live tier joins that
single oracle. The worktree fixture above is the prerequisite (the runner's
checkout is the project dir too). `TestLiveStablePreflight` stays manual: it
needs a real RC tag and a token. Update `doc/DEVELOPMENT.md` ~620 to say the
tier now runs per commit and how to run it locally.

Done when, in addition to the above: a Fast Tests run at HEAD shows the live
step green with the 24 tests listed, and a deliberately red live test on a
branch turns Fast Tests red.

## Names, final table (coordinator draft 2026-09-14, Terra pristine judgment applied)

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

## Selector and tier name (Terra-corrected)

- Selector: build tag named for the MECHANISM, `//go:build livedb`. `go test
  ./...` compiles the tier out; `go test -tags livedb ./internal/upgrade
  ./internal/install` runs it. The `STATBUS_LIVE_DB` env var and every
  `t.Skip` guard go. `TestReleaseStablePreflightGates` (row 24) needs a real
  tag and a token and stays manual under its own tag `release_live`.
- Tier name in docs and the Fast Tests step: **live-database tests**. Terra:
  "recovery" is the majority subject, not the set's property; what the 25
  share is a real local database. STATBUS-359's four-cell rule (install/
  upgrade x works/recovers) does not transfer as a family label here; only
  its per-test "name the claim" discipline does.
- Workflow step (fast-tests.yaml, after the daemon floor oracle):
  `go test -tags livedb -count=1 ./internal/upgrade ./internal/install`.

## Why not in the current batch

Owner rule from 2026-09-07: no renaming before the ruling, and the ruling
was deferred. It also touches 19 test files under cli/internal/upgrade
while that package is the one the ladder is proving; landing it mid-ladder
would move the code under the candidate. It is the first item after the
batch RC is green and the owner has ruled Q1 (build tag `livedb`).

## Ruling needed, one question

Q1: selector = build tag `livedb`, tier name "live-database tests", names as
in the table above. Yes, or name what to change.

## Batch sequencing (owner ruling 2026-09-15)

This ticket lands in the ONE batch after the current release: it does not
touch master until v2026.09.1-rc.08 (or the first later rc that goes fully
green) has been installed on Norway and promoted to stable. Then all batch
tickets land in one push, one candidate, one ladder. Position in that push:
**7 of 8**. live-database tests: worktree sandbox, livedb build tag, Fast Tests step, 25 renames; needs owner Q1 ruling first

Batch order: 370 -> 368 -> 367 -> 363 -> 357 -> 361 -> 362 -> 359.

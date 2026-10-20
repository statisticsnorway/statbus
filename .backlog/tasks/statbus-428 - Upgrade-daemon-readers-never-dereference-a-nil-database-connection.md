---
id: STATBUS-428
title: Upgrade daemon readers never dereference a nil database connection
status: In Progress
assignee: []
created_date: '2026-09-29 00:30'
updated_date: '2026-10-20 12:40'
labels:
  - upgrade
dependencies: []
priority: medium
ordinal: 377200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Non-blocking note N2 from the review of the rollback convergence fix (tmp/review-rollback-db-recreate-2.md). After a recovery path that could not reconnect, several readers still dereference d.queryConn without a nil check (e.g. cleanStaleMaintenance ~service.go:5240). Today completeInProgressUpgrade fails first with ErrQueryConnUnavailable, which covers them in Run's order, but any reordering would reintroduce a panic. Sweep every d.queryConn/d.listenConn reader reachable after recovery; return ErrQueryConnUnavailable instead of panicking. Also consider N1: let the convergence defer retry the reconnect once after a success-path reconnect failure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every queryConn/listenConn reader reachable after recovery is nil-safe with a named error
- [x] #2 A test drives each with nil connections and gets an error, not a panic
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit after v2026.09.3 (2026-09-29): v2026.09.3 (ce089d416) made completeInProgressUpgrade and upgradeParkedReason nil-safe. The full sweep of queryConn/listenConn readers (AC1/AC2) remains.

Implemented in c942b55af (pushed to master).

Mechanism: one accessor pair, queryConnOrErr/listenConnOrErr (service.go, next to ErrQueryConnUnavailable), returning the named ErrQueryConnUnavailable / new ErrListenConnUnavailable. All unguarded readers now route through it; behavior with a live connection unchanged.

Guarded readers:
- error-returning: ExecuteUpgradeInline, acquireAdvisoryLock, upsertCandidate, promoteExistingCandidate, claimScheduledUpgradePass, executeUpgrade, servingTreeConvergenceObligation, recoverServingTreeConvergence, incrementRecoveryAttempts, UnparkByID, resumeNewSb, ReattemptRestore, CommitSHAsByTag, TagsAtCommit, finalizePendingRollback, isRollbackFinishPending (now wraps the sentinel so errors.Is works)
- void best-effort sweeps (log + skip pass): markImagesFailed, verifyArtifacts, syncConfigToSystemInfo, supersedeOlderReleases, supersedeCompletedPrereleases, cleanStaleMaintenance, clearStaleReadOnlyWindow, checkMissedUpgrades, pruneDeletedTags, preDownloadImages, supersedeBelowInstalled, recordApplyRefused, clearApplyRefused
- degraded fallbacks: loadLogRelPath (empty string), probeRowStateForDiagnostic (<unreadable> pair)
- classifier: verifyUpgradeObservedStateEx guards the Check 2 ledger read and classifies a missing session as ObservedPositionUnreadable/CauseDBUnreachable (Check 1 is pure git and still runs without a session, pinned by TestVerifyUpgradeObservedState_BinarySHAmismatch)
- Run: off-channel sweep cutoff read, LISTEN upgrade_check/upgrade_apply registration (via listenConnOrErr), StampUnitFloor call site (skips the stamp when no session)

Deliberately unguarded: runOneShot entrypoints (RunDismiss/dismissNoSuchRow/registerStep/RunCheck/RowStateForCommit) — connect() fails first, so the closures never see a nil session; connect/reconnect/Close paths manage the fields with existing nil checks.

Evidence:
- red: tmp/428-red.log — TestNilConnQueryReadersReturnNamedError panics with SIGSEGV inside pgx (*Conn).QueryRow at service.go:2901 (ExecuteUpgradeInline) on the pre-fix code.
- green: tmp/428-green.log — gofmt clean, golangci-lint 0 issues, go test ./internal/upgrade/ ok (150s), including the new nil_conn_readers_test.go driving every guarded reader with nil connections and asserting errors.Is(err, ErrQueryConnUnavailable) / typed classifier verdicts / established fallbacks.
<!-- SECTION:NOTES:END -->

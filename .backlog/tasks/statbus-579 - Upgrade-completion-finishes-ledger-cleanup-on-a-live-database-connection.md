---
id: STATBUS-579
title: Upgrade completion finishes ledger cleanup on a live database connection
status: In Progress
assignee: []
created_date: '2026-11-07T21:52:00Z'
updated_date: '2026-11-07T22:00:00Z'
labels:
  - upgrade
  - recovery
  - release
dependencies: []
priority: high
type: bug
ordinal: 506204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed on real Norway rc02-to-rc03 upgrade at 2026-11-07 21:47:36 UTC. Upgrade completed and serves correctly, but clear-install-failure banner, explicit frontend notification, supersede-older/completed-prerelease and retention queries all use a cached closed queryConn after the database restart. Both rc02 and rc03 remain completed. Terminal row and read-only OFF use fresh connections and succeeded. Evidence tmp/rune-measure/final-rc03/dispatch-complete.log:510-519 and subsequent read-only ledger query. Fix now before stable promotion, without changing domain data or interrupting acceptance recalculation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A behavioral regression fails before the fix when completion succeeds through a fresh terminal session while the cached pass connection is closed.
- [ ] #2 Successful completion clears any stale failure banner, publishes the completion notification and retires obsolete release rows through a live bounded connection, with recovery/completion paths covered.
- [ ] #3 Relevant Go/live-database tests and exact-SHA CI pass, and a candidate-built real upgrade demonstrates the completed ledger and cleanup outcomes.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 22:00Z, STATBUS-579 RED evidence: commit a15c8ade00d71d54a62d40c21c03fa7ea343cbd7 adds TestCompletionFinishesLedgerAfterCachedConnectionCloses, a behavioral livedb regression through the real flagless completion writer. Command from cli/: STATBUS_LIVEDB_TEST_TIER=1 go test -tags livedb -count=1 -run '^TestCompletionFinishesLedgerAfterCachedConnectionCloses$' -v ./internal/upgrade. Disposable clone statbus_livedb_42268 from seed 20261107200300, log tmp/579-red.log. Closing the cached connection at the successful serving probe leaves the target durably completed but fails the old completed RC/available-release supersession, skipped-RC retention purge, clearing all three install failure banner values, explicit post-completion notification, and restored daemon advisory-lock ownership. This reproduces the real Norway completion defect without changing Norway. Dove owns GREEN implementation and permanent host acceptance. The next candidate and stable promotion remain blocked until GREEN, exact-SHA CI, fresh release gates and actual candidate host evidence pass.
<!-- SECTION:NOTES:END -->

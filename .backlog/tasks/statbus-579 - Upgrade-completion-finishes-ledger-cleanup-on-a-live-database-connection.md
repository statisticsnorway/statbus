---
id: STATBUS-579
title: Upgrade completion finishes ledger cleanup on a live database connection
status: Done
assignee: []
created_date: '2026-11-07T21:52:00Z'
updated_date: '2026-11-07T23:47:00Z'
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
- [x] #2 Successful completion clears any stale failure banner, publishes the completion notification and retires obsolete release rows through a live bounded connection, with recovery/completion paths covered.
- [x] #3 Relevant Go/live-database tests and exact-SHA CI pass, and a candidate-built real upgrade demonstrates the completed ledger and cleanup outcomes.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 22:00Z, STATBUS-579 RED evidence: commit a15c8ade00d71d54a62d40c21c03fa7ea343cbd7 adds TestCompletionFinishesLedgerAfterCachedConnectionCloses, a behavioral livedb regression through the real flagless completion writer. Command from cli/: STATBUS_LIVEDB_TEST_TIER=1 go test -tags livedb -count=1 -run '^TestCompletionFinishesLedgerAfterCachedConnectionCloses$' -v ./internal/upgrade. Disposable clone statbus_livedb_42268 from seed 20261107200300, log tmp/579-red.log. Closing the cached connection at the successful serving probe leaves the target durably completed but fails the old completed RC/available-release supersession, skipped-RC retention purge, clearing all three install failure banner values, explicit post-completion notification, and restored daemon advisory-lock ownership. This reproduces the real Norway completion defect without changing Norway. Dove owns GREEN implementation and permanent host acceptance. The next candidate and stable promotion remain blocked until GREEN, exact-SHA CI, fresh release gates and actual candidate host evidence pass.

2026-11-07 22:20Z: GREEN 5da3c8a8d implements shared bounded completion cleanup for normal, flagless and post-swap recovery writers. Root independently passed the all-three-writers plus authority/banner/retention failure livedb cases (tmp/579-root-focused.log). Full unit, livedb and race suites passed. Exact-source 85e35e613 CI then correctly blocked the RC before tagging: Go Test 42419488473 found three unchecked newly returned errors, and Harness Selftest 42419488486 rejected an invented completed-RC fixture under the existing no-fabrication doctrine. Neither failure is waived. Dove owns the two Go caller corrections with lint RED/GREEN. Coordinator committed fae77ecf9 to use genuine upgrade rows and the product retention plan: scenario-selection RED exit1, GREEN pass and shell syntax pass (tmp/579-harness-red.log, tmp/579-harness-green.log). Read-only retention prototype passed on local seed. Completed-RC retirement will be checked on the real Norway rc03-to-final-RC upgrade, not by fabricating host history. Ticket remains In Progress. Fresh exact-SHA CI, candidate gates and host evidence still required. No stable promotion or additional Norway mutation occurred.

2026-11-07 22:27Z: Caller correction90033d6b6 checks all three newly returned errors. Supersession and retention nil-session calls now assert named errors in the established positive contract test. The idle time-safety sweep logs its failure and retries at the next poll, while completion's load-bearing cleanup still propagates errors. Linux lint0issues (tmp/579-lint-linux-green.log). Worker focused unit race PASS1.043s and livedb race PASS10.701s (tmp/579-ci-callers-unit.log, tmp/579-ci-callers-livedb.log), including all three actual completion writers, retention SQL error and advisory authority. Coordinator independently reran all TestNilConn cases PASS0.016s (tmp/579-root-nil-callers.log). Native lint also now0issues after separately tracked569 PTY test-helper fix95b966a5c, independently checked tmp/569-lint-native-root.log. Genuine host assertionfae77ecf9 passes scenario-selection and syntax with no fabricated upgrade rows. Norway read-only pre-final baseline at22:21:44 confirms healthy/idle/currentrc03 and two real same-family completed RC rows; final-host script tmp/579-final-norway-readonly.sql is prepared to verify the completed-family population becomes1 and retention settles after the new candidate. AC2 is covered by real disposable database success/failure tests. AC3 and Done remain pending fresh exact-SHA CI/full candidate gates and actual candidate host evidence. No stable promotion yet.

2026-11-07 23:47 UTC final acceptance: v2026.11.2-rc.04 is 929fe787c2ab323d3a8c6d013bb9864fbec7bd67. All exact-source CI and full candidate gates passed, including Smoke42422098754 genuine happy-upgrade ledger assertion, LXD42422880347, Upgrade Arc Harness42422939393 and Orchestrator42421987884 completed/success; independent chain exit0. On the real idle, tracked-clean Norway host, fetched named tag, verified signed target commit, then used supported upgrade register/schedule at23:40:31. Exact target claimed23:40:44.553617 and completed23:46:03.621958 (319.068s to durable completion); fixup/callback finished23:46:11. Actual completion journal positively records 'Superseded 2 completed prerelease(s) in same family' and 'retention: purged 2 upgrade row(s) (scope=all, installed=4)'. Both genuine old rc02/rc03 completed rows retired, leaving the exact rc04 as the sole completed family member. Read-only after-upgrade query23:46:29 confirms installed_completed=true, banner_cleared=true for all three keys, family_completed_count=1 versus2 before, retention_actions=0, read_only off, workers idle, zero failed tasks and source20261107200300. Actual app artifact is full SHA929fe787 and monitor rc04/ok with every check ok. Four exact unit stocks and eight NULL-hash history summary rows match pre-upgrade. Positive verifier tmp/rune-measure/final-rc04/verify-acceptance.mjs passed, results verified-acceptance.json and verification.log. Full actual log dispatch-complete.log, completion-journal.log, before-upgrade.out, after-upgrade.out, monitor-current.json and build-current.json preserved in that directory. Snapshot45.6GB/31.2GBcopied243.5s is this host run, not a claim about upgrade wall speedup. All579criteria are verified. Reports577 visual running/idle acceptance is a separate open item, not waived by these host checks. Stable promotion remains pending that final acceptance.
<!-- SECTION:NOTES:END -->

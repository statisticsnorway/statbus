---
id: STATBUS-433
title: >-
  Fixture-branch Images runs cancel master's Fast Tests via shared concurrency
  group
status: Done
assignee: []
created_date: '2026-09-29 14:00'
updated_date: '2026-09-29 14:55'
labels: []
dependencies: []
ordinal: 382200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The upgrade-arc harness dispatches images.yaml (workflow_dispatch) on throwaway
test/upgrade-arc-* fixture branches (upgrade-target.sh). .github/workflows/fast-tests.yaml
triggered on workflow_run of "Images" with no branch filter, so every fixture Images
run started a Fast Tests run classified candidate=false, landing in concurrency group
'fast-tests-master' with cancel-in-progress: true — cancelling master's own Fast Tests.
Measured since 2026-09-27: 4 master Fast Tests runs were cancelled by fixture runs
(918e682a9, 4daee93fa, 34ca4a5b2, f22016803's second run 36575920976); none of those
4 SHAs has a green Fast Tests run. The fixture runs themselves fail by design
(deliberately-broken migrations), adding unrelated red noise.

Fix (landed): add `branches: [master]` to fast-tests.yaml's `workflow_run` trigger, and
key the concurrency fallback group on the branch actually exercised (not a fixed
'fast-tests-master' literal), so a non-master run reaching the fallback (e.g. a manual
`gh workflow run fast-tests.yaml --ref <branch>`) also cannot share master's cancellable
group. Per GitHub docs (`on.workflow_run.<branches|branches-ignore>`), the trigger filter
filters on the triggering run's head_branch, so ordinary master-push Images runs
(images.yaml push trigger is already `branches: [master]`) still trigger Fast Tests
unchanged; fixture-branch Images runs no longer do. RC tags and PRs use separate `on:`
triggers, unaffected. Contract tests extended:
TestFastTestsExcludesFixtureBranch_STATBUS433 in
cli/cmd/workflow_candidate_concurrency_test.go asserts the workflow_run trigger's
branches filter is exactly `[master]`; TestFastTestsCandidateConcurrency_STATBUS415 gained
table rows proving a fixture-branch workflow_run and a workflow_dispatch on another
branch never land in master's concurrency group, while master A/B still share it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 fast-tests.yaml starts no run for an Images completion on a non-master branch (workflow_run.branches: [master])
- [x] #2 Only master's runs share the cancellable master concurrency group; other branches and manual dispatches get their own group (contract test rows)
- [x] #3 Master's Fast Tests completes after the fix
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done 2026-09-29: merge e069fbcfe (reviews tmp/review-433.md, tmp/review-433-2.md MERGE, addendum for 956b8a0f4). Evidence: Go Test success at e069fbcfe (TestFastTestsExcludesFixtureBranch_STATBUS433 and the STATBUS-415 concurrency table incl. fixture and other-branch rows); Fast Tests 36584215345 at e069fbcfe completed success. Also fixed: a missing Fast Tests verdict no longer suggests 'gh workflow run --ref <raw SHA>' (956b8a0f4).
<!-- SECTION:NOTES:END -->

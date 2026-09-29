---
id: STATBUS-433
title: >-
  Fixture-branch Images runs cancel master's Fast Tests via shared concurrency
  group
status: To Do
assignee: []
created_date: '2026-09-29 14:00'
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

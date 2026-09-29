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
'fast-tests-master' with cancel-in-progress: true — cancelling master's own Fast Tests
(observed: master commit f22016803's Fast Tests cancelled twice at 13:32-13:33 UTC by
fixture runs; since 2026-09-27: 52 cancelled, 5 failed, 3 succeeded). The fixture runs
themselves fail by design (deliberately-broken migrations), adding red noise.

Fix (landed): add `branches: [master]` to fast-tests.yaml's `workflow_run` trigger. Per
GitHub docs (`on.workflow_run.<branches|branches-ignore>`), this filters on the
triggering run's head_branch, so ordinary master-push Images runs (images.yaml push
trigger is already `branches: [master]`) still trigger Fast Tests unchanged;
fixture-branch Images runs no longer do. RC tags and PRs use separate `on:` triggers,
unaffected. Contract test extended:
TestFastTestsExcludesFixtureBranch_STATBUS433 in
cli/cmd/workflow_candidate_concurrency_test.go asserts the workflow_run trigger's
branches filter is exactly `[master]`.
<!-- SECTION:DESCRIPTION:END -->

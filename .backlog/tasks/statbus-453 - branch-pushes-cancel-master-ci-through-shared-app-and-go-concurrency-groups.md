---
id: STATBUS-453
title: Branch pushes cancel master CI through shared app and Go concurrency groups
status: In Progress
assignee: []
created_date: '2026-10-06 14:49'
labels:
  - ci
  - release
dependencies: []
references:
  - STATBUS-364
  - STATBUS-452
priority: high
---

## Observed failure

The single master push at 2026-10-06 14:40:41 UTC published `49bb3f1a5817cd25d8986c9da2b581fd83258653`. The app workflow run37480974869/job112328682457 was cancelled during Run App Tests. Its check annotation says: "Canceling since a higher priority waiting request for app-build-lint-master exists".

Competing run37481254979 was a push to `dependabot/npm_and_yarn/app/sharp-0.35.5`, created14:42:43 UTC, SHA `ca5d66a8ca4be7c46f5d4d6620ec398af7e66fd6`. Its later PR run is separate. Remote master remained49bb at14:48, and the coordinator did not push again or cancel any run. Evidence: `tmp/452-ci-app-cancellation-20261006.log`.

The app workflow permits non-ops branch pushes, but its concurrency expression puts EVERY non-PR event into `app-build-lint-master`. The Go workflow has the same expression shape with `go-test-master`, but its push trigger is master-only. Its reachable sibling collision is a manual workflow_dispatch on another branch, not a Dependabot branch push. The observed cancellation was the app run only. Both corrections must preserve their existing trigger filters.

## Small fix and intended behavior

Keep the STATBUS-364 policy: pushes and manual dispatches to master share one group and newer master runs cancel older ones. PR groups remain scoped to their PR ref. Other branch pushes/manual dispatches must have their own ref-scoped groups, never master's group. No trigger filters, release-gate exemptions or cancel-in-progress policy need changing.

Delegate a bounded source change in those two workflows, with one small real-expression behavior check using the existing workflow-test conventions. A check must establish actual group equality/inequality for representative events, not merely forbid a literal token.

## Acceptance Criteria

- [ ] #1 Master push and master dispatch group together; PR refs and other branch refs remain distinct, including the observed Dependabot branch.
- [ ] #2 Baseline reproduces the grouping collision; corrected expressions pass behavioral checks and actionlint, preserving newest-master-wins.
- [x] #3 Independent exact-source review accepts the bounded correction; integrate with patch/source proof and no push during active CI.
- [ ] #4 Exact corrected master CI, including app and Go, finishes successfully. Preserve the original cancellation evidence rather than calling it a passing run.

## Reviewed source integration, 2026-10-06 15:00 UTC

Otter froze clean235aab129c92fc923765e1d5c4a611da6173b5e8: two group expressions and comments plus one37-line positive parsed-expression/cancellation contract test. No trigger, exemption, permission or dependency changes. Existing real app cancellation proves the baseline defect. Local RED contract pin and manually transcribed event/ref model are retained separately from actual actionlint; the model does not evaluate GitHub YAML. Focused package tests, build, vet and lint0issues passed.

Independent panda MERGE report tmp/453-concurrency-review.md was read in full. It independently checked both actual workflow sources with actionlint, existing exemption and coverage tests, exact source blobs and unchanged policy boundaries. Hosted corrected CI is explicitly pending, not waived by source MERGE.

The coordinator integrated only this reviewed commit as b8a9d0e33216c8ae3f200026a14352c2e27bd2b6. Stable patch IDs match and the full repository outside backlog notes equals reviewed235aab. Evidence tmp/453-reviewed-integration-20261006.log. No push occurred. Separate Fast Tests on49bb then failed exactly008/016, so the next push waits for their observed, reviewed schema-contract correction as well. Original app cancellation is never counted as green.

## Safety and next action

No production, database, cloud guest, Slack or secret operations. Work in an isolated source worktree, do not push or edit master. At delegation, Fast Tests37481764536 for49bb were still in progress. They subsequently failed exactly008/016 at14:58:22, recorded in STATBUS-452. No next push until their bounded correction is reviewed and ALL existing CI is terminal. STATBUS-451's source-only investigation is complete, implementation remains the following bounded step after these CI corrections.

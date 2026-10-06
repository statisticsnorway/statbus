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
- [ ] #3 Independent exact-source review accepts the bounded correction; integrate with patch/source proof and no push during active CI.
- [ ] #4 Exact corrected master CI, including app and Go, finishes successfully. Preserve the original cancellation evidence rather than calling it a passing run.

## Safety and next action

No production, database, cloud guest, Slack or secret operations. Work in an isolated source worktree, do not push or edit master. Current Fast Tests37481764536 for49bb remain in progress. Wait for all existing CI to become terminal before the next push. STATBUS-451's read-only release-gate investigation may continue, but this observed CI blocker gets the next bounded fix and review.

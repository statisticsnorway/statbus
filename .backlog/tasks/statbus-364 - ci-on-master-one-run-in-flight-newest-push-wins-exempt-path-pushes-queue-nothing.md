---
id: STATBUS-364
title: >-
  CI on master: one run in flight, newest push wins, exempt-path pushes queue nothing; Fast Tests gets the same diff-since-green coverage as go-test
status: In Progress
assignee: []
created_date: '2026-09-07 20:25'
updated_date: '2026-09-07 20:25'
labels:
  - ci
  - release
dependencies: []
priority: high
type: task
---

## Why

The release gate asks one question: is HEAD green. A green run at HEAD proves
every commit since the previous green run; intermediate commits carry no
information the tip does not. Today every master push queues its own full
Fast Tests run (13 min, single niue runner) behind every earlier one, keyed
per SHA with no cancellation. On 2026-09-07 four backlog-only pushes delayed
the RC cut by ~50 minutes, twice.

## Ground truth

- `fast-tests.yaml` concurrency group is `fast-tests-<head_sha>`,
  `cancel-in-progress` only for pull_request. `go-test.yaml` same shape.
- Runner time per Fast Tests run: setup ~1 min, suite 10 min, daemon floor
  oracle 1.5 min.
- `release prerelease` already reasons "green at older SHA covers HEAD when
  every file changed since is in `ops/release/ci-exempt-paths.txt`" for
  go-test and app-build-lint. Check 7 (Fast Tests) does not use it.

## Work

1. Fast Tests, go-test, app-build-lint on master: fixed concurrency group per
   workflow (e.g. `fast-tests-master`), `cancel-in-progress: true`. Result:
   the running job is cancelled when a newer push lands, at most one pending
   run is kept, older pending runs are cancelled by GitHub. PR runs keep
   their per-ref groups.
2. Check 7 in `cli/cmd/release`: apply the same diff-since-green exempt-path
   coverage used for go-test, so a backlog-only push after a green run
   passes without a new run. Reuse the existing helper; no second copy of
   the exempt list.
3. Prove it with tests, not prose: a unit test for check 7's coverage path
   (green at older SHA + only exempt files changed = pass, one non-exempt
   file = fail with the run URL named); `actionlint` on the workflows.

## Done when

- Two master pushes 30 s apart produce one completed Fast Tests run at the
  newer SHA and one cancelled run (observed in `gh run list`).
- `./sb release prerelease` on a backlog-only commit after a green Fast
  Tests run passes check 7, naming the covering run.
- Adversarial review by a different session; runner CI green at HEAD.

## Not this ticket

Making the suite itself faster than 10 min.

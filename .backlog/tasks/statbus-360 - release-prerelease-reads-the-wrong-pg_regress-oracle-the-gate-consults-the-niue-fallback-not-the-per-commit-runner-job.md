---
id: STATBUS-360
title: >-
  release prerelease reads the wrong pg_regress oracle: the gate consults the niue fallback, not the per-commit runner job, and its output misleads the operator
status: To Do
assignee: []
created_date: '2026-09-07 13:11'
updated_date: '2026-09-07 13:11'
labels:
  - release
  - ci
dependencies: []
---

## Ground truth (2026-09-07)

Two CI jobs run the identical pg_regress fast suite (`./dev.sh
migrate-and-test fast`, 98 tests, no 4xx/5xx):

| workflow | job name shown | where | role (owner ruling) |
|---|---|---|---|
| `fast-tests.yaml` | "Fast Tests" | GitHub runner, every push | **the** per-commit pg_regress oracle |
| `pg_regress.yaml` | "pg_regress" | niue self-hosted, one commit at a time, often cancelled by the next push | fallback for when we choose to run it ourselves; never a gate to wait on |

`./sb release prerelease` has two separate checks that both read this
tier, and they disagree about which job is the source of truth:

1. Check 7 "Fast tests cover latest migrations" (`release.go` ~150-260):
   local stamp first, else `checkWorkflowAtCommit(release.WorkflowPgRegress)`,
   i.e. the **niue fallback**. Its messages say `pg_regress is still pending
   at <sha>`, `Watch: gh run watch <niue run>`, `Fix: wait for the run to
   complete`. On a normal day the niue run is pending or cancelled while the
   runner's Fast Tests has been green for half an hour. The operator (or the
   coordinating agent) is told to wait on a job that does not gate.
2. `checkPrereleaseWorkflowGate(release.WorkflowFastTests, "fast-tests")`
   later in the same preflight reads the **runner job** correctly.

The help text says "pg_regress (fast pg_regress suite; local-stamp fast path
+ CI fallback)" and lists "fast-tests" as a separate oracle, which reads as
two different suites. They are one suite.

Observed cost: on 2026-09-07 the coordinator waited ~40 minutes on
`pg_regress.yaml` at HEAD `256873ab2` while `fast-tests.yaml` was already
green, and reported "pg_regress and Fast Tests" as two distinct oracles to
the owner. The output produced that misunderstanding.

## Ruling (owner)

Fix the OUTPUT and the oracle, not the reader's understanding. One suite,
one name, one gate:

- Check 7 consults `fast-tests.yaml` (the runner). `pg_regress.yaml` is not
  consulted by any gate. The local stamp remains the operator's escape valve
  exactly as today.
- Every message in check 7 names the runner job and points `Watch:` /
  `URL:` at its run, never at niue.
- Help text: one line for the suite ("pg_regress fast suite: local stamp, else
  the Fast Tests runner job at HEAD"), and `fast-tests` is not listed a second
  time as if it were something else.
- The two workflows' `name:` fields say what they are: the runner is the
  oracle, niue is "pg_regress (self-hosted fallback)". STATBUS-359 owns the
  broader naming sweep; this ticket may land the two `name:` lines early
  because they are what the gate's output quotes.
- `release_drift_ci_escape.go`'s stamp-ride (STATBUS-219) reads the same
  runner job.

## Tests

- `release_ci_exempt_ride_test.go`, `release_drift_ci_escape_test.go`,
  `workflow_check_test.go` pin `WorkflowPgRegress`; move them to
  `WorkflowFastTests` and add one test that asserts check 7's pending/failed/
  missing messages contain the runner workflow's name and never
  `pg_regress.yaml`'s.
- A test that the help text mentions the suite once.

## Done when

`./sb release prerelease` on a commit whose runner Fast Tests is green and
whose niue run is pending or cancelled passes check 7 without a local stamp,
and its output nowhere tells the operator to wait for niue.

## Coordination checkpoint: 2026-09-07 16:31

Implementation landed as `938df6891`. At `f2862bd47`, runner Fast Tests succeeded while niue fallback failed. Runner is the per-commit pg_regress oracle, niue is not a gate. Final evidence/acceptance and exact new HEAD CI remain before Done.

## Evidence: independent Sol review, 2026-09-07 16:43

- Squid ACCEPT for `938df6891`. Focused STATBUS360/workflow/oracle tests and full `./cmd/release ./internal/release` Go packages passed. Report: `tmp/STATBUS-360-review.md`.
- Negative oracle proves niue-green alone does not satisfy check 7. Failure prose names Fast Tests and help lists the suite once. Whole prerelease command was not executed by reviewer.
- At `f2862bd47`, runner run 34141738192 succeeded while fallback 34141738170 failed, demonstrating the distinct signals.
- Fallback failed before tests: duplicate column 42701 applying re-timestamped migration 20260907120000 against stale cached state. This is a test-cache repair issue, not a release gate or evidence of a fleet orphan. Read-only repair scoping delegated, no remote rebuild authorized.
- At `081d7e4ec`, Images succeeded and runner Fast Tests remains in progress. Done remains pending final CI verification.

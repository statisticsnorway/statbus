---
id: STATBUS-365
title: >-
  rc.01 ladder stopped at step 1: fleet admission guard (admit.sh) died silently at gh api on its first real run, orchestrator mislabelled it SUPERSEDED
status: In Progress
assignee: []
created_date: '2026-09-07 21:03'
updated_date: '2026-09-07 21:03'
labels:
  - ci
  - release
  - fail-fast
dependencies: []
priority: high
type: bug
---

## What happened

`v2026.09.1-rc.01` (`b6d810493`) was tagged at 20:47. Release Fleet
Orchestrator run 34160749022 dispatched Test Smoke run 34160818299. Its
first step, `orchestrator-fleet-admission/admit.sh` (added 09-04 in
`4284eeca2`, STATBUS-350, never exercised on a real RC until now), exited 1
after 0.9 s **without printing any of its own `::error` lines**. Under
`set -euo pipefail` that means the `gh api repos/.../actions/runs/<id>` call
itself failed (token is the workflow `GITHUB_TOKEN` with `actions: read`).
The orchestrator then stopped the chain and its summary job says
"SUPERSEDED — stopped for a newer candidate", which is false: no newer
candidate exists.

Run locally against the same (now completed) parent, the script prints its
reason correctly, so the script logic is fine; the failure is the API call
in the runner's context.

## Work

1. Find the real cause from the run logs (`gh run view 34160818299 --log`,
   job "Select smoke scenarios"), reproduce as closely as possible with a
   workflow-scoped token, and fix it. Candidates: `gh` not authenticated via
   `GH_TOKEN` in a composite action, `actions: read` insufficient for
   `GET /actions/runs/{id}` on this repo, `jq -e` exit on a field shape.
2. `admit.sh` must fail loudly: capture `gh api` stderr and HTTP status and
   print them before exiting. A guard that refuses without saying why is a
   guard nobody can fix at 21:00 on release night.
3. The orchestrator must not call a child failure "SUPERSEDED" unless it
   actually observed a newer tag. Failure for the child's own reasons is
   "FAILED at step N" with the child run URL.
4. Tests: a unit test for the admission decision that runs the script
   against a recorded parent JSON (in_progress, completed, wrong sha, wrong
   path), asserting both exit code and the printed reason; `actionlint`.
5. Adversarial review by a different session, then the coordinator cuts
   rc.02 from the fix commit and the ladder re-runs.

## Done when

Test Smoke for the next RC passes admission and prints
`Admitted orchestrated paid run: ...`; the orchestrator's summary names the
real outcome. Both observed in `gh run view` output, recorded here.

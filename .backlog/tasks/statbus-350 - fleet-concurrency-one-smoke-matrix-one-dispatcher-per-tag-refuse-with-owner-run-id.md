---
id: STATBUS-350
title: >-
  fleet concurrency: one smoke matrix, native bounded queue, and owner-aware dispatch
status: In Progress
assignee: []
created_date: '2026-09-04 06:40'
updated_date: '2026-09-04 20:18'
labels:
  - release
  - ci
  - fail-fast
dependencies: []
priority: high
type: bug
ordinal: 343000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Observed failure

Four workflows rented Hetzner VMs under the shared workflow-level
`hetzner-vm-fleet` group: `test-install.yaml`, `test-upgrade.yaml`,
`install-recovery-harness.yaml`, and `upgrade-arc-harness.yaml`. On
`v2026.09.0-rc.14`, a third entrant replaced an already-pending smoke run under
GitHub's default single-pending policy. The victim concluded `cancelled` with
zero jobs and no explanation. The orchestrator waited out its budget twice and
lost roughly three hours despite no product failure.

## Verified platform facts

- GitHub now supports `concurrency.queue: max`: up to 100 runs can wait without
  pending-run replacement. The concurrency-group API exposes the ordered
  members, including each run's ID, name, status, URL, and queue position.
- Workflow concurrency is acquired before any job starts. A pending run cannot
  execute a first-job refusal.
- A list-only check outside the group is not atomic. Two arrivals can both see
  an empty group. Native concurrency remains the authority that makes global
  different-tag VM overlap impossible.
- Current actionlint 1.7.12 rejects GitHub's documented `queue` key. The code
  therefore needs one exact, path-scoped ignore plus a structural regression
  test until actionlint learns the key.
- Deleted workflow filenames remain queryable through the Actions API. Real
  historical smoke evidence exists under both old identities and must remain
  discoverable.

## Approved design: native bounded queue with guardrails

The King approved Option A on 2026-09-04. Do not build a custom lease or
controller. GitHub's concurrency group remains the single atomic quota owner.

### 1. One smoke workflow and one dispatch

Replace `test-install.yaml` and `test-upgrade.yaml` with dispatch-only
`test-smoke.yaml`. Its selected-scenario matrix runs jobs named exactly
`0-happy-install` and `0-happy-upgrade`; those bare names are evidence marks.
The workflow accepts a space-separated `scenarios` input so the per-scenario
coverage optimizer can dispatch only the uncovered half when appropriate.

Collapse the orchestrator's two parallel smoke jobs into one job that asks the
shared coverage authority for both scenarios, dispatches `test-smoke.yaml` at
most once, and passes the uncovered selectors. Dev starts only after that one
smoke stage succeeds. Leave every between-stage supersession decision intact.

Introduce `WorkflowTestSmoke = "test-smoke.yaml"`. Retain explicit legacy
constants for `test-install.yaml` and `test-upgrade.yaml`, and include new plus
legacy identities in `WorkflowsRunningScenario`. The stable smoke gate becomes
the same per-scenario coverage authority used by the two harness gates, with
the existing `SKIP_TEST_INSTALL=1` operator bypass retained for compatibility.

### 2. Native atomic serialization

Put this exact workflow-level block on the three resulting paid fleet
workflows: `test-smoke.yaml`, `install-recovery-harness.yaml`, and
`upgrade-arc-harness.yaml`:

```yaml
concurrency:
  group: hetzner-vm-fleet
  cancel-in-progress: false
  queue: max
```

No workflow may recreate a separate fleet group or enable cancellation. Add a
parsed structural test over the exact three-file set. Add only the exact
actionlint ignore required for `queue` on those paths; every other actionlint
diagnostic remains fatal.

### 3. Orchestrator fail-fast and race cleanup

Before `dispatch-fleet-and-wait` dispatches a paid fleet workflow, query
`GET /repos/{owner}/{repo}/actions/concurrency_groups/hetzner-vm-fleet`. If the
group has any member, refuse before dispatch and name the current owner run ID,
name, status, URL, and queued waiters. This is an operator diagnostic, not the
atomic lock.

A manual dispatch can race the preflight. After correlating its own run, the
action queries the group again. If its run is waiting behind another owner, it
cancels only its own named pending run, verifies that cancellation, and fails
with both run IDs and URLs. It must never cancel the running owner. This keeps
the orchestrator fail-fast without weakening the native serialization.

Direct hand dispatches do not use this action. They wait safely in GitHub's
native queue and can be inspected and cancelled by their exact run IDs.

### 4. Queue operations and stale work

Document the exact concurrency-group API command that lists owner and waiters,
and `gh run cancel <run-id>` for an explicitly selected pending waiter. Do not
provide an unqualified bulk-cancel command and do not present cancelling the
running owner as routine.

Each fleet's existing scenario selection and the orchestrator's arriving-stage
supersession checks remain authoritative. The dispatcher removes its own
race-created waiter, so an orchestrated run cannot sit latent and start after
its polling owner has failed. A hand-dispatched waiter remains an explicit
operator request and is not silently reinterpreted or discarded.

## Acceptance

- One tag creates at most one smoke run and at most one smoke fleet lease.
- The new smoke matrix leaves exact per-scenario job marks and accepts an
  uncovered selector subset without changing their names.
- Historical marks under both deleted smoke filenames remain discoverable.
- The stable smoke gate evaluates both scenario facts, not a bare workflow
  success that a subset run could satisfy.
- All three paid workflows share `queue: max`, retain
  `cancel-in-progress: false`, and cannot overlap across tags.
- An occupied group makes orchestrated dispatch refuse immediately with the
  real owner and waiter details from the concurrency-group API.
- A preflight race cancels only the orchestrator's own named pending run. It
  never cancels the running owner and never leaves latent paid work behind.
- Hand-dispatched waiters remain visible, ordered, and individually
  cancellable by run ID. No pending run is silently replaced.
- Local Go tests, workflow structure tests, YAML parsing, and actionlint with
  the one documented queue-key exception pass before push.
- Final acceptance is one later batch RC exercising the live orchestrator,
  both smoke marks, owner-aware refusal/cancellation diagnostics, and all fleet
  stages. No RC or paid dispatch is part of the overnight implementation.
<!-- SECTION:DESCRIPTION:END -->

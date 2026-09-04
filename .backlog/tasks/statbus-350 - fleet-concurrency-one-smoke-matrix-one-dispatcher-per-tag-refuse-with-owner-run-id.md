---
id: STATBUS-350
title: >-
  fleet concurrency: one smoke matrix, one dispatcher per tag, refuse with the owner's run id
status: In Progress
assignee: []
created_date: '2026-09-04 06:40'
updated_date: '2026-09-04 20:03'
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

Four workflows rented Hetzner VMs under the shared workflow-level `hetzner-vm-fleet` group: `test-install.yaml`, `test-upgrade.yaml`, `install-recovery-harness.yaml`, and `upgrade-arc-harness.yaml`. On `v2026.09.0-rc.14`, a third entrant replaced an already-pending smoke run under GitHub's default single-pending policy. The victim concluded `cancelled` with zero jobs and no explanation. The orchestrator waited out its budget twice and lost roughly three hours despite no product failure.

## Verified platform facts that change the original design

GitHub now supports `concurrency.queue: max`: up to 100 runs can wait without replacement, with FIFO processing by time of entry into the group. GitHub also exposes the live group and ordered members through `GET /repos/{owner}/{repo}/actions/concurrency_groups/{group}`.

The original proposed first-job guard is not implementable inside the current workflow-level group. GitHub acquires workflow concurrency before any job starts, so a pending run cannot execute its first job. Moving a list-only guard outside the group is not an atomic replacement: two simultaneous runs can both observe an empty group and both proceed toward paid VM work. The tmp prototype demonstrates both facts.

## Common implementation, whichever admission policy is chosen

1. Replace the two smoke workflows with dispatch-only `test-smoke.yaml`, running `0-happy-install` and `0-happy-upgrade` as a two-entry matrix with those exact job names.
2. Collapse the orchestrator's two smoke jobs into one dispatch. Preserve per-scenario coverage semantics explicitly.
3. Introduce `WorkflowTestSmoke = "test-smoke.yaml"`. Keep legacy `test-install.yaml` and `test-upgrade.yaml` identities in `WorkflowsRunningScenario`; real historical proof exists only under each old identity, and deleted workflow filenames remain queryable through the Actions API.
4. Point the stable smoke gate at the new workflow while retaining the existing operator bypass contract.
5. Leave the King's between-stage supersession mechanism unchanged.

## Decision required before implementation

### A. Native bounded queue, recommended

- Add `queue: max` to the shared workflow-level concurrency on all three resulting VM-fleet workflows. This preserves the exact global cross-tag quota boundary and removes zero-job pending replacement.
- Before orchestrator dispatch, query the concurrency-group API and fail immediately with the current owner's run ID and name if occupied. Hand-dispatched runs are safe but queue rather than executing a first-job refusal.
- Use the same API in `dispatch-fleet-and-wait` for owner-aware queue/cancellation diagnostics.
- Add a narrow actionlint suppression plus a structural regression test until actionlint supports GitHub's new `queue` key. Current actionlint 1.7.12 rejects the documented key as unknown.

### B. Exact self-refusal for hand dispatches

Authorize a larger admission redesign. It needs an atomic durable lease or a controller/worker split before the workflow-level group. A plain `gh run list` check is insufficient and must not be shipped as if it closed the race. This is materially larger than smoke consolidation and native queuing.

## Acceptance after the decision

- One tag produces one smoke run with both exact scenario marks and one fleet lease.
- Historical marks under both deleted smoke filenames remain discoverable.
- Global different-tag VM concurrency remains impossible.
- A duplicate dispatch either receives the approved explicit refusal or waits in the approved bounded native queue. It is never silently replaced.
- Diagnostics name the current owner from the concurrency-group API rather than guessing from unrelated active runs.
<!-- SECTION:DESCRIPTION:END -->

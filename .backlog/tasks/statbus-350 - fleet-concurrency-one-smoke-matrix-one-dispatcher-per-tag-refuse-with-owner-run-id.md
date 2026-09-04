---
id: STATBUS-350
title: >-
  fleet concurrency: one smoke matrix, one dispatcher per tag, refuse with the owner's run id
status: In Progress
assignee: []
created_date: '2026-09-04 06:40'
updated_date: '2026-09-04 19:53'
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
## The problem

Four workflows rent Hetzner VMs and share `concurrency: group: hetzner-vm-fleet` so that two VM-renting RUNS never fan out at the same time and exceed the Hetzner project quota: `test-install.yaml`, `test-upgrade.yaml`, `install-recovery-harness.yaml`, `upgrade-arc-harness.yaml`.

A GitHub concurrency group holds at most ONE running run and ONE pending run. A third entrant makes GitHub cancel the previously pending run: zero jobs, no message. `cancel-in-progress: false` protects only the running run. This is GitHub's scheduler, not a queue, and not something we store.

The two smoke tests each rent ONE VM but each is its own workflow, so together they spend BOTH group slots on two single-VM jobs. The orchestrator dispatches them in parallel, so while it is live the group is full, and any other dispatch on the same tag (a hand dispatch, an orchestrator rerun while the old smoke still runs) evicts a pending smoke silently and starves the orchestrator's poll budget.

Observed 2026-09-04 on v2026.09.0-rc.14: a hand-dispatched arc run entered as the third entrant; test-install was cancelled with zero jobs, test-upgrade waited two hours, orchestrator attempt 1 timed out; attempt 2 re-created the same collision. No product failure anywhere. Three hours lost and a confused morning.

## What to do

1. **One smoke matrix.** Replace `test-install.yaml` and `test-upgrade.yaml` with one workflow, `test-smoke.yaml`, running `0-happy-install` and `0-happy-upgrade` as a two-entry matrix (two VMs in parallel, one group slot). Keep the tag-push trigger and `workflow_dispatch`. Keep the per-job names exactly `0-happy-install` and `0-happy-upgrade` so the evidence lookup finds them. Update `cli/internal/release/workflow_check.go` (`WorkflowTestInstall`, `WorkflowTestUpgrade`) and `WorkflowsRunningScenario` in `evidence.go` to the new identity; the stable gate's `checkStableWorkflowGate` for test-install becomes the smoke workflow.
2. **Orchestrator stages 1 and 2 collapse into one** dispatch of `test-smoke.yaml` via `dispatch-fleet-and-wait`. The orchestrator then never holds two group slots.
3. **Refuse, do not get cancelled.** The first job of every fleet workflow runs `gh run list --repo $GH_REPO --json databaseId,status,headSha,workflowName` and, if another run in the group is `in_progress` or `queued` at the same head sha with a different run id, FAILS with exactly: `refused: run <id> (<workflow>) already owns hetzner-vm-fleet for <tag>; wait for it, or cancel it deliberately, then re-dispatch`. The message is the fix. Hand dispatch stays valid when the group is free on that tag; this probe makes the rule self-enforcing.
4. **Name the cancellation.** In `.github/actions/dispatch-fleet-and-wait/action.yml`, when the correlated run concludes `cancelled` with zero jobs, print `cancelled by hetzner-vm-fleet concurrency; owning run: <id>` instead of a bare failure.
5. **Write it down** in `test/install-recovery/README.md`: never dispatch into the fleet group while an orchestrator is live on the same tag; before rerunning an orchestrator, confirm the group is empty with `gh run list`.

## What NOT to touch

The King's supersession rule (`decide-obsolete` and each stage's `if:` in the orchestrator) is a different mechanism: it stops a chain BETWEEN stages when a newer tag appears and never yanks running VMs. Leave it as is.

## Done when

- One tag push produces exactly one smoke run holding one group slot, both scenarios green in it, and the stable gate reads their evidence under the new identity (`./sb release covered 0-happy-install <sha>` and `0-happy-upgrade` both "ran and passed at <sha>").
- A deliberate second dispatch into the group on the same tag fails within its first job with the `refused: run <id> ...` line and rents no VM.
- `dispatch-fleet-and-wait` names the owning run when a dispatched run is cancelled by the group.
<!-- SECTION:DESCRIPTION:END -->

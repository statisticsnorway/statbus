---
id: STATBUS-214
title: >-
  fleet-orchestrator-chain: GitHub's single-pending-slot cancels the third
  tag-fired fleet — replace the shared concurrency group with one orchestrator
  workflow chaining the fleets
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-17 07:14'
updated_date: '2026-08-18 08:13'
labels:
  - install-recovery
  - release
  - ci
  - quality-gate
dependencies: []
references:
  - .github/workflows/install-recovery-harness.yaml
  - .github/workflows/upgrade-arc-harness.yaml
  - .github/workflows/test-install.yaml
  - >-
    .backlog/tasks/statbus-208 -
    vm-fleet-collision-same-name-VMs-across-tag-fired-workflows-—-refuse-then-delete-kills-the-other-runs-live-VM-project-server-limit-breached.md
priority: high
ordinal: 214000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: one tag push runs ALL fleets to verdicts, in an order that fits the Hetzner limit — no stampede, no starvation, and no fleet silently cancelled.
> FOUND: 2026-08-17, first live contact of the 208 capacity fix at v2026.08.0-rc.02: Test Install ran (group held), Install Recovery took the pending slot, and the Upgrade Arc Harness — arriving third — was CANCELLED with zero jobs (run conclusion 'cancelled', jobcount 0). GitHub semantics the 208 ruling missed: a concurrency group keeps at most ONE running + ONE pending run; any additional queued run cancels the previously-pending one (cancel-in-progress:false protects only the RUNNING run). The architect's shared-group ruling was wrong for 3+ workflows — owned; the run was the oracle.

THE RULING (architect): replace the shared hetzner-vm-fleet concurrency group with an ORCHESTRATOR workflow: the v*-rc.* tag-push trigger moves to ONE new workflow that invokes the three fleets as workflow_call jobs in an explicit needs: chain (test-install → install-recovery-harness → upgrade-arc-harness, cheapest-first). Deterministic order, zero cancellation surface, no concurrency-group games; each inner workflow keeps its own max-parallel 3 (peak VM demand unchanged, fits the limit); each keeps workflow_dispatch for manual/subset runs. The inner workflows' own tag triggers are REMOVED (the orchestrator owns the tag) — with an in-place comment naming this ticket so the 199 layer-pin's tag-fired premise is updated, not violated: the 199/205 gates key on runs AT the commit and are trigger-agnostic (workflow_call runs report the caller's sha — the builder VERIFIES head_sha attribution for workflow_call before wiring, and if call-attribution breaks the gates' head_sha match, falls back to the orchestrator dispatching via `gh workflow run --ref <tag>` sequentially instead of workflow_call; either mechanism satisfies the ruling — attribution correctness decides).
INTERIM at rc.02, no build needed: the foreman hand-dispatches the arc harness at the tag once the install-recovery fleet completes — sequential by hand this once.

ORACLES: actionlint; the 199 layer-pin test updated to the orchestrator's trigger geometry; THE REAL ONE: the next tag runs all three fleets to verdicts with zero cancelled runs and zero resource_limit_exceeded.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One tag push yields verdicts from ALL three fleets — zero cancelled runs, zero limit breaches — observed at a real RC tag
- [ ] #2 The gates' run-at-commit attribution verified under the chosen mechanism (workflow_call sha attribution, or sequential gh-dispatch fallback) before wiring
- [ ] #3 The 199 layer-pin and the workflow comments reflect the orchestrator geometry; manual workflow_dispatch paths preserved on all three fleets
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-18 08:13
---
THIRD LIVE DEMONSTRATION of the shared-group cancellation at v2026.08.0-rc.03 (2026-08-18): the tag fired all three fleet workflows; the group held Upgrade Arc Harness (running) + Install Recovery Harness (pending); Test Install run 32115159028 was CANCELLED with zero jobs. Consequence for the rc.03 gates: test-install has no green at the tag yet — foreman will re-dispatch it at v2026.08.0-rc.03 once the fleet drains (after the arc suite and install-recovery complete, and after the ruled one-arc 215 spot-check). This cancellation is the exact failure the orchestrator exists to remove; it stays the mechanic's next assignment after the 216/217/218 gate-hardening round.
---
<!-- COMMENTS:END -->

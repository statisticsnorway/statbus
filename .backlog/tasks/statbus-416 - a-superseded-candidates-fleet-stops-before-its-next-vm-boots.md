---
id: STATBUS-416
title: A superseded candidate's fleet stops before its next VM boots
status: To Do
assignee: []
created_date: '2026-09-25 09:45'
updated_date: '2026-09-25 09:45'
labels:
  - release-bug
  - ci
dependencies: []
priority: high
type: bug
ordinal: 367000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A newer RC does not interrupt an already running VM, but each queued scenario of the older RC checks freshness before it rents its own VM. The older fleet reports SUPERSEDED, neither failed nor green promotable proof, while the newer candidate's independent orchestrator proceeds without a capacity collision.

## Grounded evidence, 2026-09-25

- Install Recovery Harness [run 36104217764](https://github.com/statisticsnorway/statbus/actions/runs/36104217764) for rc.02 had three failed scenarios by 07:23Z and 12 scenario jobs still queued at 07:30Z (`gh run view 36104217764 --json jobs`). Completed job step lists contained no per-scenario freshness check. A newly queued scenario started with checkout and artifact download, then provisioned its VM.
- `.github/workflows/release-fleet-orchestrator.yaml:107-125,281-295,380-394,529-543` checks the newest tag at the initial decision and between fleet stages, never between matrix scenarios. Its final Fleet verdict at `:732-816` independently rechecks tags and distinguishes SUPERSEDED from a genuine failure.
- `.github/actions/orchestrator-fleet-admission/admit.sh:81-88` checks newest RC once before each child fleet starts, not when an individual scenario later gets a VM slot. Its supersession refusal exits 1, so it is not a neutral per-scenario outcome.
- `.github/workflows/install-recovery-harness.yaml:110-113`, `upgrade-arc-harness.yaml:105-108`, and `test-smoke.yaml:23-26` share `hetzner-vm-fleet`, `cancel-in-progress: false`, `queue: max` (STATBUS-208). Cancelling in-flight VMs would strand cleanup and contend with the newer fleet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `TestSupersededCandidateStopsBeforeEachVMAndPropagatesFleetVerdict_STATBUS416` pins the shared freshness action as the first post-checkout step in all three VM matrix jobs and requires every subsequent step, including `always()` cleanup, to respect its output.
- [ ] #2 Each scenario queries the remote newest RC at its own arrival. On a newer tag, its log contains `SUPERSEDED by <tag>: stopping before VM boot`, its job summary names the newer tag, and it creates no VM. Non-RC manual refs and unknown remote lookup proceed.
- [ ] #3 An aggregate of *all* selected matrix scenario markers emits a distinct SUPERSEDED verdict and exposes it to the orchestrator through its dispatch-and-wait action. Missing marker/artifact never produces a green proof. The final Fleet verdict respects child-observed supersession even if its own tag refresh fails.
- [ ] #4 Live sibling VMs finish and self-clean, the shared noncancelling VM capacity lock remains, and no superseded fleet launches the next stage. A real failure with no superseding tag stays red.
- [ ] #5 A tagged CI exercise verifies the observable job summary, artifact verdict, orchestrator SUPERSEDED verdict, and absence of new VM boots after a newer RC tag appears. Record run IDs and actual conclusions.
<!-- AC:END -->

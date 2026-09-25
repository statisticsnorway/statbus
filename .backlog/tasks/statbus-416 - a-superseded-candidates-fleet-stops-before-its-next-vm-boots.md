---
id: STATBUS-416
title: A superseded candidate's fleet stops before its next VM boots
status: In Progress
assignee: []
created_date: '2026-09-25 09:45'
updated_date: '2026-09-25 12:20'
labels:
  - release-bug
  - ci
dependencies: []
priority: high
type: bug
ordinal: 367000
---

## Status 2026-09-25

**Follow-up dispatch defect (rc.04, run 36121911613).** rc.04 (`2a27caf85`) was cut at 10:03:52Z. Its orchestrator smoke job failed at 10:05:08Z in `dispatch-fleet-and-wait/dispatch.sh` preflight, before any scenario ran, because the shared concurrency group still listed rc.03 Install Recovery Harness run 36116753412. That older run's last two jobs had ended at 10:04:07Z and 10:04:22Z, so GitHub was still releasing the group. REST reports its head_branch `v2026.09.3-rc.03`, event `workflow_dispatch`, actor `github-actions[bot]`; workflow run REST does not expose the orchestrator-run-id input. Newer candidate dispatch must wait a bounded 20 minutes for exclusively older bot-dispatched RC occupants, reporting remaining jobs and never cancelling. Same/newer candidate, manual human dispatch and unknown provenance still refuse. This is a classification fix, not evidence that tagged CI has passed; AC #5 remains open.

**In Progress, tagged proof pending.** `ef32c20c5` (merge `21426f622`) adds the shared `scenario-superseded` check as the first post-checkout step in all three VM jobs (`.github/workflows/test-smoke.yaml:103`, `install-recovery-harness.yaml:480`, `upgrade-arc-harness.yaml:634`), plus marker aggregation (`.github/actions/scenario-fleet-verdict/aggregate.sh:34-35`), dispatch propagation and the structural test (`cli/cmd/workflow_harness_domain_validation_test.go:22-74`). This is not an observed supersession. AC #5 requires a real newer-tag exercise with job summary, artifact, orchestrator SUPERSEDED verdict, run IDs/conclusions and no new VM boots; keep all AC open until rc.03 gate evidence.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A newer RC does not interrupt an already running VM, but each queued scenario of the older RC checks freshness before it rents its own VM. The older fleet reports SUPERSEDED, neither failed nor green promotable proof, while the newer candidate's independent orchestrator proceeds without a capacity collision.

## Grounded evidence, 2026-09-25

- Install Recovery Harness [run 36104217764](https://github.com/statisticsnorway/statbus/actions/runs/36104217764) for rc.02 had three failed scenarios by 07:23Z and 12 scenario jobs still queued at 07:30Z (`gh run view 36104217764 --json jobs`). Completed job step lists contained no per-scenario freshness check. A newly queued scenario started with checkout and artifact download, then provisioned its VM.
- `.github/workflows/release-fleet-orchestrator.yaml:107-125,281-295,380-394,529-543` checks the newest tag at the initial decision and between fleet stages, never between matrix scenarios. Its final Fleet verdict at `:732-816` independently rechecks tags and distinguishes SUPERSEDED from a genuine failure.
- `.github/actions/orchestrator-fleet-admission/admit.sh:81-88` checks newest RC once before each child fleet starts, not when an individual scenario later gets a VM slot. Its supersession refusal exits 1, so it is not a neutral per-scenario outcome.
- `.github/workflows/install-recovery-harness.yaml:110-113`, `upgrade-arc-harness.yaml:105-108`, and `test-smoke.yaml:23-26` share `hetzner-vm-fleet`, `cancel-in-progress: false`, `queue: max` (STATBUS-208). Cancelling in-flight VMs would strand cleanup and contend with the newer fleet.
## Observations and follow-up fix, 2026-09-25

The per-scenario supersession check (merged `ef32c20c5`) has not yet had a chance to fire: rc.04 was cut 10:03:52Z while rc.03's last two scenarios were already running (ended 10:04:07Z/10:04:22Z); no rc.03 scenario started after the cut.

rc.04 exposed the opposite defect: its orchestrator run 36121911613 failed in 90 s at 10:05:08Z because `.github/actions/dispatch-fleet-and-wait/dispatch.sh` preflight_fleet_group refused (`Hetzner VM fleet occupied`) while rc.03's fleet (run 36116753412) was draining. Fixed in `2feb30f29`: an older candidate's occupying run -> bounded wait (30 s polls, 20 min cap, owner id and remaining jobs logged); same/newer/manual/unknown occupant -> refuse as before; the occupant is never cancelled. Merged in `a3526f832`; rc.05's orchestrator dispatched its smoke normally. Proof of the per-scenario stop still pending: needs a cut while a fleet has scenarios still queued.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `TestSupersededCandidateStopsBeforeEachVMAndPropagatesFleetVerdict_STATBUS416` pins the shared freshness action as the first post-checkout step in all three VM matrix jobs and requires every subsequent step, including `always()` cleanup, to respect its output.
- [ ] #2 Each scenario queries the remote newest RC at its own arrival. On a newer tag, its log contains `SUPERSEDED by <tag>: stopping before VM boot`, its job summary names the newer tag, and it creates no VM. Non-RC manual refs and unknown remote lookup proceed.
- [ ] #3 An aggregate of *all* selected matrix scenario markers emits a distinct SUPERSEDED verdict and exposes it to the orchestrator through its dispatch-and-wait action. Missing marker/artifact never produces a green proof. The final Fleet verdict respects child-observed supersession even if its own tag refresh fails.
- [ ] #4 Live sibling VMs finish and self-clean, the shared noncancelling VM capacity lock remains, and no superseded fleet launches the next stage. A real failure with no superseding tag stays red.
- [ ] #5 A tagged CI exercise verifies the observable job summary, artifact verdict, orchestrator SUPERSEDED verdict, and absence of new VM boots after a newer RC tag appears. Record run IDs and actual conclusions.
<!-- AC:END -->

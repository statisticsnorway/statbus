---
id: STATBUS-223
title: >-
  ride-relocation: the orchestrator swallowed the path-sensitivity shortcut —
  move the decision up to it and delete the fleet's now-dead copy
status: To Do
assignee: []
created_date: '2026-08-18 09:54'
labels:
  - ci
  - release
  - install-recovery
dependencies: []
references:
  - .github/workflows/release-fleet-orchestrator.yaml
  - .github/workflows/upgrade-arc-harness.yaml
  - ops/release/upgrade-sensitive-paths.txt
  - cli/cmd/release.go
priority: medium
type: enhancement
ordinal: 223000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: STATBUS-199 D2 ratified a cost shortcut. When an RC's diff against the previous RC touches nothing in ops/release/upgrade-sensitive-paths.txt, re-proving the upgrade is waste, so the arc suite short-circuits: the `decide` job computes sensitivity, `discover` returns an empty matrix, and 31 VM boot-and-test cycles are not spent. The stable release gate re-derives that same decision independently and never trusts the workflow's verdict, so the shortcut is a pure economy measure that can never affect what gets promoted.

WHAT GOES WRONG: STATBUS-214 moved the `v*-rc.*` tag onto the orchestrator, which now dispatches each fleet with `gh workflow run`. That arrives as a `workflow_dispatch` event, and `decide` is gated on `github.event_name == 'push'` — so it never runs again at an RC tag. Every RC, however trivial its diff, now pays the full 31-VM suite and the hours of wall-clock that go with it. Nobody wrote that change; it fell out of the trigger move.

THE DETAIL: with `decide` skipped, `needs.decide.outputs.sensitive` is empty, so every RIDE clause that reads it evaluates false and the full path runs. Three pieces of just-landed machinery become unreachable at RC tags as a result: `discover`'s RIDE early-exit, `no-arcs-guard`'s RIDE exemption, and STATBUS-218's `construct` RIDE clause — 218's entire saving, landed hours earlier, along with its open observation criterion, which can now never be met. The `decide` job itself is dead code: its only trigger was the tag push that no longer reaches this workflow.

THE FIX: the decision moves up to the layer that now owns release-scope economy. The orchestrator computes sensitivity against the previous RC tag — the same derivation `decide` performs today, moved rather than rewritten — and simply does not dispatch the arc fleet when the RC is not upgrade-sensitive. Then delete the fleet's dead copy: `decide`, `discover`'s RIDE early-exit and its RIDE env, `no-arcs-guard`'s RIDE exemption (which becomes an unconditional zero-arc guard), and 218's `construct` clause. Dead paths get removed, not kept as defensive cover.

Two boundaries the builder must not guess at. **Scope: only the arc fleet is skipped.** upgrade-sensitive-paths.txt is about upgrades; test-install and install-recovery prove installation and recovery, which a frontend-only change can still break. They are always dispatched. **Authority is unchanged:** the gate keeps re-deriving sensitivity itself (checkUpgradeArcHarnessGate's walk), so the orchestrator's decision stays a cost optimizer and never a correctness source. A skipped dispatch leaves no run at the RC commit, which the gate already handles — `WorkflowCheckMissing` falls through to the same path-sensitivity walk that an incomplete green does, and rides a prior full-suite green loudly or refuses.

WHY THAT HELPS: a minimal RC stops costing a full fleet and hours of release latency, which is what 199 D2 was ratified to prevent; STATBUS-218's saving becomes reachable again in its stronger form, since not dispatching a fleet beats dispatching one that skips its own jobs — no runner, no fixture branches, no image builds, no queue slot; and the decision ends up in the one place that knows what a release cut costs, instead of inside a tool that can no longer see how it was invoked.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The orchestrator derives upgrade-sensitivity against the previous RC tag and skips dispatching ONLY the arc fleet when the RC is not sensitive; test-install and install-recovery are always dispatched
- [ ] #2 The skip is printed loudly — the previous RC compared against, the verdict, and the full sensitive-path list — never a silent omission
- [ ] #3 The arc harness's now-dead RIDE machinery is DELETED: the decide job, discover's RIDE early-exit and env, no-arcs-guard's RIDE exemption, and STATBUS-218's construct clause
- [ ] #4 A sensitive RC still dispatches the full 31-arc suite, and a manual workflow_dispatch of the arc harness still runs its selected arcs regardless of sensitivity
- [ ] #5 The stable gate is untouched and still re-derives sensitivity itself; a skipped dispatch leaves no run at the RC commit and the gate's existing Missing→walk path handles it
- [ ] #6 STATBUS-218 is re-scoped or closed as subsumed, with its observation criterion resolved rather than left permanently unmeetable
<!-- AC:END -->

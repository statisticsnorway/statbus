---
id: STATBUS-223
title: >-
  ride-relocation: the orchestrator swallowed the path-sensitivity shortcut —
  move the decision up to it and delete the fleet's now-dead copy
status: To Do
assignee: []
created_date: '2026-08-18 09:54'
updated_date: '2026-08-18 10:13'
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
Releasing a new version should not cost hours of testing nobody needs. Right now every release candidate runs the full three-hour, 31-machine upgrade test fleet — even one that changed nothing but a web page — because a recent change accidentally switched off the shortcut that used to skip it.

WHY THE SHORTCUT EXISTS: upgrade tests prove that an existing installation can move to the new version without losing data. If a release changes nothing that an upgrade touches, running them again proves nothing new, so STATBUS-199 D2 ratified skipping them and inheriting the previous release's proof. The decision is checked twice, independently: the workflow decides whether to spend the machines, and the release gate re-derives the same judgement itself before allowing a promotion, so the shortcut can never affect what actually ships.

WHAT GOES WRONG: STATBUS-214 moved the release tag onto the new orchestrator, which now starts each fleet by dispatching it. That arrives as a different event type than a tag push, and the job that computes "is this release upgrade-sensitive" only runs on a tag push — so it never runs again. Nobody decided this; it fell out of the trigger move.

THE DETAIL: with `decide` skipped, `needs.decide.outputs.sensitive` is empty, so every clause reading it evaluates false and the full path runs. Three pieces of just-landed machinery become unreachable as a result: `discover`'s early-exit, `no-arcs-guard`'s exemption, and STATBUS-218's `construct` clause — 218's entire saving, landed hours earlier, along with its open observation criterion, which can now never be met. The `decide` job itself is dead code: its only trigger was the tag push that no longer reaches this workflow.

THE FIX: the decision moves up to the orchestrator, which is now the thing that knows what a release costs. It works out whether the release is upgrade-sensitive and simply does not start the upgrade fleet when it is not. The fleet's own copy of that logic then gets deleted rather than left lying around: `decide`, `discover`'s early-exit and its RIDE env, `no-arcs-guard`'s exemption (which becomes an unconditional zero-arc guard), and 218's `construct` clause.

Two boundaries the builder must not guess at. **Only the upgrade fleet is skipped.** The sensitivity list is about upgrades; the install and recovery fleets prove things a web-page change can still break, so they always run. **Authority is unchanged:** the release gate keeps working out sensitivity for itself, so the orchestrator's decision only ever saves money and can never let something ship unproven. A skipped fleet leaves no run at that commit, which the gate already handles — it treats "no run" exactly as it treats an incomplete one, and either inherits an older proof loudly or refuses.

WHY THAT HELPS: a trivial release stops costing a full fleet and hours of waiting, which is what the shortcut was ratified to prevent. STATBUS-218's saving comes back in a stronger form, because not starting a fleet beats starting one that skips its own work — no machines, no throwaway branches, no image builds, no queue slot. And the decision ends up in the one place that can see the whole release, instead of inside a tool that can no longer tell how it was invoked.
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-18 10:13
---
Description rewritten to the Purpose Sandwich — the point now lands in the first two sentences in words that need no code knowledge ("releasing a new version should not cost hours of testing nobody needs"), the mechanism and file-level detail are unchanged below it, and the close states what is regained. No change to scope, acceptance criteria, or the ruling: only the opening's altitude. Filed before the King's calibration on STATBUS-220; corrected because this is the one of my recent tickets carrying a real decision he may need to weigh.
---
<!-- COMMENTS:END -->

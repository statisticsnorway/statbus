---
id: STATBUS-223
title: >-
  ride-relocation: the orchestrator swallowed the path-sensitivity shortcut —
  move the decision up to it and delete the fleet's now-dead copy
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-18 09:54'
updated_date: '2026-08-18 14:55'
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

author: mechanic
created: 2026-08-18 14:55
---
Built to spec, frozen for review (no commits), part 1/2. release-fleet-orchestrator.yaml gained a new `decide-upgrade-sensitivity` job (no needs — runs from the start in parallel with test-install, since it's pure git/grep with no VM cost); `upgrade-arc-harness` now needs it too.

DECISION LOGIC (AC#1): the new job's script is the SAME derivation the deleted `decide` job used to run, relocated verbatim — PREV_RC via `git tag --sort=-version:refname | grep -- '-rc\.' | sed -n '2p'`, substring-match the diff against `ops/release/upgrade-sensitive-paths.txt`. `upgrade-arc-harness`'s `if:` skips ONLY when explicitly confirmed non-sensitive:
```
if: >-
  ${{ !cancelled() &&
      needs['install-recovery-harness'].result == 'success' &&
      !(needs['decide-upgrade-sensitivity'].result == 'success' && needs['decide-upgrade-sensitivity'].outputs.sensitive == 'false') }}
```
Any other state (job failed, cancelled, or output merely absent) falls through to RUNNING the fleet — safe default. test-install and install-recovery-harness have no dependency on this job at all, so they always run regardless (AC#1's other half).

LOUD PRINTING (AC#2): the decide job's script prints PREV_RC, the full sensitive-paths list, every changed file since PREV_RC, and the verdict — unconditionally, every run, whether sensitive or not (same logging the deleted `decide` job already did, just relocated).

AC#5 (gate untouched): zero changes to cli/cmd/release.go or any Go file. The gate's own CheckUpgradeArcHarnessGate/sensitivity walk is completely independent of this workflow-side decision, as it always was — a skipped dispatch leaves WorkflowCheckMissing at that commit, which the gate's existing Missing→path-sensitivity-walk fallback already handles.

Part 2/2 (deletions + upgrade-arc-harness.yaml changes + 3-path trace) follows.
---

author: mechanic
created: 2026-08-18 14:55
---
Part 2/2 — the deletions (AC#3) and the three-path trace.

DELETED from upgrade-arc-harness.yaml:
- the entire `decide` job (checkout + the sensitivity-diff script), replaced with a one-line comment naming STATBUS-223 and pointing at the orchestrator.
- `construct`'s `needs: [decide]` and its whole STATBUS-218 RIDE `if:` clause — back to a fully bare job (no needs, no if), since nothing decides skip-eligibility inside this file anymore.
- `discover`'s `needs: [decide]` and `if: always()` (the guard existed ONLY to survive decide's skip — with decide gone there's nothing to survive, so bare is honest, not a ghost guard) — and inside its script, the `RIDE` env var and the whole `if [ "$RIDE" = "true" ]; then ... exit 0; fi` early-exit block.
- `no-arcs-guard`'s `decide` need and its RIDE-exemption clause — it's now unconditional: `!cancelled() && needs.discover.result == 'success' && needs.discover.outputs.count == '0'`, a pure backstop (STATBUS-216's nullglob check already catches the "arcs/ folder empty" case earlier and louder).

KEPT, per your instruction, on `run-arc`: the explicit per-need result checks (`needs.construct.result == 'success' && needs['image-wait'].result == 'success' && needs.discover.result == 'success' && needs.discover.outputs.count != '0'`) — they guard genuine FAILURE, not skip, and stay valid/valuable even though the specific 215 trap they were written against can no longer occur in this file (construct/discover have no needs of their own now, so nothing upstream of them can be skipped either). Updated its comment to say so explicitly rather than leaving stale 215-vs-decide narrative.

Top-of-file header comment rewritten: the STATBUS-214 "KNOWN CONSEQUENCE, flagged not fixed" paragraph (which this ticket exists to resolve) is replaced with a STATBUS-223 paragraph explaining RIDE relocated, not just fixed, and that this file carries NO RIDE machinery of its own anymore.

THREE-PATH TRACE (mentally executed against the final YAML):

1. SENSITIVE TAG PUSH via orchestrator: decide-upgrade-sensitivity computes sensitive=true (prints PREV_RC/paths/changed-files/verdict). upgrade-arc-harness's if: `!(success && false)` → `!(false)` → true → dispatches. Inside upgrade-arc-harness.yaml: construct/discover run unconditionally (bare), full 31-arc matrix, no-arcs-guard skipped (count!=0), run-arc runs the full matrix, teardown deletes all pushed branches, cleanup sweeps. Full suite, as before 214 broke it.

2. NON-SENSITIVE TAG PUSH via orchestrator: decide-upgrade-sensitivity computes sensitive=false (prints the same loud reasoning, verdict says fleet will be SKIPPED). upgrade-arc-harness's if: `!(success && true)` → `!(true)` → false → job SKIPPED — `gh workflow run upgrade-arc-harness.yaml` is NEVER CALLED. Zero VMs, zero fixture branches, zero image builds, zero queue slot (strictly better than 218's construct-level skip, which still spent 20-30min). Orchestrator concludes green (skipped jobs don't fail a run) as long as test-install + install-recovery-harness succeeded, which don't depend on this decision at all. At promotion time the gate sees WorkflowCheckMissing at this commit and falls through to its own independent sensitivity walk (untouched) — AC#5 holds.

3. MANUAL workflow_dispatch OF THE ARC HARNESS DIRECTLY (bypassing the orchestrator): construct/discover/run-arc run unconditionally regardless of sensitivity — this file has no sensitivity logic left at all to gate on. Verified construct ALWAYS builds/pushes all 7 lineages' fixture pairs regardless of which `scenarios` subset is selected (its fixture-build step isn't conditioned on SCENARIOS_INPUT), so a subset dispatch still gets the full teardown cleanup — consistent with the 220 fix in the same file. AC#4 holds.

LAYER-TEST INTERACTION: none. `TestReleaseGateLayer_TagFiredWorkflows` re-run (`-count=1`, fresh) still passes — the orchestrator file's `on: push: tags:` trigger and absence of `branches:` are both untouched by this change; only jobs/logic inside it changed. Also ran the full release/workflow-gate Go suite (`go test ./cmd/... ./internal/release/... -run 'Release|Workflow|Gate|Arc|Harness' -count=1 -v`) — all green, plus `go build ./...` OK.

AC#6 (218): closed as subsumed — separate comment on STATBUS-218 itself, and I found the architect had already ruled the same closure independently (218 comment #4, landed just before mine) — no conflict.

Validated: `ruby -ryaml` + `actionlint` clean on both files (zero findings, confirmed against a full-repo actionlint sweep showing zero attributions to either file). Frozen, no commits.
---
<!-- COMMENTS:END -->

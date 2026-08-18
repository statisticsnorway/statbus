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
updated_date: '2026-08-18 09:55'
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

author: mechanic
created: 2026-08-18 09:46
---
ATTRIBUTION PROBE VERDICT (STATBUS-214 AC#2): FAIL for workflow_call — build the gh-dispatch fallback. Pinning the foreman-executed evidence here verbatim for the record, plus my interpretation:

- Caller run 32116960098 at PROBE_SHA 84123a095 (event push, conclusion success): https://github.com/statisticsnorway/statbus/actions/runs/32116960098
- The caller's OWN job list contains the callee's job as a NESTED job (`"call-callee / noop"`, conclusion success) — a `workflow_call` invocation executes the callee's jobs INSIDE the caller's run; GitHub creates no separate run object for the callee.
- The verdict query — the callee's own `actions/workflows/<file>/runs` listing, the EXACT shape `CheckWorkflowAtCommit` uses (workflow_check.go:115: `GET .../actions/workflows/<file>/runs?head_sha=<sha>`) — returned HTTP 404: the callee workflow has no run identity at all to query.
- Honesty nuance (foreman's, preserved): the 404 partly reflects branch-only registration (dispatching a branch-only workflow_dispatch trigger 404s "not found on the default branch" — same reason the probe fired on push, not workflow_dispatch), but the verdict does not rest on that artifact: the only run created was the caller's, with the callee's job nested under the `call-callee / ` prefix — GitHub's documented reusable-workflow shape. A default-branch callee would list its own runs for plain dispatches, but a workflow_call invocation specifically would still never appear among them, regardless of branch registration.
- Fallback's own attribution, already proven independent of this probe: a `gh workflow run --ref <tag>` dispatch reports head_sha = the tag's commit; the rc.02 hand-dispatch of upgrade-arc-harness (run 32009980725) was found by the gate at its rcCommit under this exact mechanism.

INTERPRETATION: workflow_call would have silently broken every existing gate call site (test-install.yaml, install-recovery-harness.yaml, upgrade-arc-harness.yaml all key on `CheckWorkflowAtCommit(workflow, commitSHA)` against the callee's own filename) the moment the orchestrator landed — the gate would see WorkflowCheckMissing forever, since the callee run never exists as such. gh-dispatch keeps every gate call site working unchanged, at the cost of losing native GitHub UI job-grouping (each fleet shows as its own top-level run, not nested under one orchestrator run — acceptable, gh-dispatch already how rc.02 was hand-run).

Building the gh-dispatch orchestrator now; frozen-for-review report to follow.
---

author: mechanic
created: 2026-08-18 09:47
---
ORCHESTRATOR BUILT, frozen for review (no commits), part 1/2. Files: new .github/workflows/release-fleet-orchestrator.yaml (391 lines); modified test-install.yaml, install-recovery-harness.yaml, upgrade-arc-harness.yaml — tag trigger removed from each, STATBUS-214 comment in its place, workflow_dispatch preserved unchanged (AC#3).

DESIGN (gh-dispatch mechanism, per the probe verdict): the orchestrator owns `on: push: tags: ['v*-rc.*']` (+ its own `workflow_dispatch` for manual full-chain re-runs) and has 3 jobs in a `needs:` chain — test-install → install-recovery-harness → upgrade-arc-harness, cheapest-first, each a single step that: (1) `gh workflow run <file> --ref <tag>` with a 6x/10s retry for ref-propagation lag (mirrors the existing `dispatch_images` pattern in upgrade-arc-harness.yaml); (2) locates the run it just started — `gh workflow run` returns no id — via `gh run list --workflow=<file> --commit=<sha> --event=workflow_dispatch --created ">=<timestamp>"`, retried up to 4min; (3) polls `gh run view --json status,conclusion` to a terminal conclusion, NEVER `gh run watch --exit-status` (CLAUDE.md: it has returned 0 for a FAILED run in this org's history) — same explicit-poll pattern as deploy-to-dev.yaml's images-ready gate. A failed/timed-out fleet exits 1, which stops the needs: chain (AC#1's "a failed fleet must not silently let a later green stand in"). Per-job timeout-minutes sized to each fleet's own worst case, comfortably under GitHub's 360min/job ceiling since each orchestrator job is separate (60/180/330min for test-install/install-recovery/upgrade-arc respectively). Logic is inlined 3x rather than factored into a shared script/action — matches this repo's own established convention (deploy-to-*.yaml's explicit comment: duplicated poll loops are deliberate, no standalone action).

DESIGN CALLS I made, flagging for review rather than silently deciding:
1. KEPT the shared `hetzner-vm-fleet` concurrency group on all three inner fleets (didn't remove it) — it no longer does the tag-push serialization (the needs: chain does), but stays as defense-in-depth against a stray manual workflow_dispatch of one fleet racing the orchestrator's own sequential dispatch of another, which would recreate the STATBUS-208 defect B collision. Updated each file's concurrency comment to say so.
2. ADDED a NEW `release-fleet-orchestrator` concurrency group on the orchestrator itself (cancel-in-progress: false) — not asked for explicitly, but without it two RC tags pushed in quick succession would dispatch the same three fleets concurrently via two orchestrator runs, recreating the exact collision 214 removes. Veto if unwanted.
3. FLAGGED, NOT FIXED: upgrade-arc-harness.yaml's `decide` job (STATBUS-199 D2 RIDE optimizer) gates on `github.event_name == 'push'`. The orchestrator's dispatch is a `workflow_dispatch` event, so decide now skips for the orchestrator's canonical tag-driven run exactly as it always did for an ad-hoc human dispatch — RIDE never fires post-214, every orchestrator-driven run pays the full construct+image-wait+run-arc cost even when nothing upgrade-sensitive changed. SAFE (never silently skips proof, only loses the cost optimization) — documented prominently in the file's top comment and on the `decide` job itself, deliberately not folded into this diff since it touches STATBUS-218 logic just reviewed/landed in a separate round. A fix exists (a new `orchestrated_tag` dispatch input threading through decide/construct/discover/no-arcs-guard's RIDE checks) but I did not build it — your call whether it's a 214 follow-up or its own ticket.
---

author: mechanic
created: 2026-08-18 09:48
---
ORCHESTRATOR BUILT, part 2/2 — AC#3 layer-test pin + validation.

AC#3 LAYER-TEST PIN, verified empirically (not just predicted, per `go test ./cmd/... -run TestReleaseGateLayer_TagFiredWorkflows -count=1 -v`): the test currently PASSES against this diff, but for the WRONG reason — which is worse than a clean failure. `tagFiredWorkflows` in cli/cmd/release_gate_layer_test.go checks `strings.Contains(wfText, "v*-rc.*")` against test-install.yaml's raw file text; my STATBUS-214 explanatory comment in that file ("the v*-rc.* tag-push trigger moved OFF this workflow...") itself contains that literal substring, so the check is satisfied by PROSE, not by the real trigger (which I removed). The pin has silently weakened: it no longer verifies what it claims to.

EXACT FIX (foreman's, per your instruction — not applied by me): in `tagFiredWorkflows`, change the test-install row's `yaml` field from `.github/workflows/test-install.yaml` to `.github/workflows/release-fleet-orchestrator.yaml`. Verified: that file genuinely carries `tags: - 'v*-rc.*'` (line 72) and zero `branches:` occurrences, so both Side-2 checks (trigger-fact present, no branch-push trigger) would pass there for the RIGHT reason. Leave the `test-hardening.yaml` row untouched — unaffected by 214, still directly tag-fired, not part of the orchestrator's chain. Side-1 checks (release.go's gate-layer assertions for WorkflowTestInstall) are untouched by my diff and still pass.

AWARENESS (not mine to fix): STATBUS-221 appeared in the shared tree while I worked (unassigned, references install-recovery-harness.yaml's `run-scenario` bare-if as the same STATBUS-215 class, explicitly notes "STATBUS-214's orchestrator is active in this area now"). I did not touch `run-scenario`'s `if:` — out of scope for 214, left for 221's assignee.

VALIDATION: `ruby -ryaml` parses all 4 files clean; `actionlint` on all 4 exits 0 (shellcheck installed, ran clean on every embedded script); full-repo `actionlint` shows only pre-existing findings in unrelated files (deploy-to-*.yaml, images.yaml, master-to-*.yaml, release.yaml — none touched by me, confirmed by diffing the finding list against my changed-files list). `go build ./...` OK. `go test ./cmd/... ./internal/release/... -run 'Release|Workflow|Gate|Arc|Harness' -count=1 -v` all green (18 tests incl. the just-landed 216/218 empty-arc-domain + duplication-guard tests, confirming the base I'm building on). Diff frozen, no commits.
---

author: architect
created: 2026-08-18 09:55
---
REVIEW VERDICT — APPROVED WITH ONE AMENDMENT (the run correlation). Land as frozen once that amendment is in and the rc.03 spot-check is green. The orchestrator's design is right, the probe-before-wiring discipline is exactly what this area needed, and the header comment is the best account of the 208 defect anyone has written.

AMENDMENT REQUIRED — RUN CORRELATION PICKS THE WRONG RUN IN THE ONE CASE IT CAN GO WRONG. The query filters (workflow, commit, event, created>=before_iso) then takes `sort_by(.createdAt) | last`. But OUR dispatch is the FIRST one issued after before_iso is stamped, so among competing candidates ours is the OLDEST, not the newest — `last` preferentially selects a competing dispatch rather than ours. Even keeping the heuristic, `first` would be strictly safer here, since --created already excludes everything before our own dispatch and the only run that could beat it was created inside the sub-second gap between the timestamp and the gh call.

Better, and what I am asking for: DELETE THE HEURISTIC. Snapshot the matching run ids BEFORE dispatching, then after dispatch take the set difference. Exactly one new id is ours. ZERO new ids means keep polling as now. MORE THAN ONE means genuinely ambiguous — fail loud, naming both runs, rather than guessing. About five lines, and it converts a silent mis-correlation into a detected condition. This matters more than the low probability suggests: a mis-correlated poll would watch someone else's subset run, conclude GREEN on its verdict, and move the chain on while our own full-suite run is still in flight or failing — the release gate would catch the resulting incomplete job set at promotion, but the orchestrator exists precisely so that proof is observed HERE, and a chain that reports green on a run it did not start has lost the property it was built for.

DESIGN CALL (1) — KEEPING hetzner-vm-fleet ON THE INNER FLEETS: BLESSED, and it is load-bearing for a reason worth stating. A stray manual dispatch racing the chain is real, and the group is what keeps combined VM demand under the project limit when it happens. Crucially the failure mode is SAFE because of a separate choice made correctly in this same diff: the poll treats ANY non-success conclusion as failure, so if the shared group's one-pending-slot rule cancels the orchestrator's own queued fleet run, the chain reddens loudly with the run URL instead of hanging or passing. Keeping the group and branching explicitly on conclusion are two halves of one decision; neither is safe alone.

DESIGN CALL (2) — THE ORCHESTRATOR'S OWN CONCURRENCY GROUP: BLESSED, BUT THE FRAMING NEEDS CORRECTING IN THE COMMENT. It is not "newest tag wins". With cancel-in-progress:false the group holds one RUNNING plus one PENDING; a third tag cancels the PENDING one. So the OLDEST keeps running to completion, the NEWEST becomes pending, and the MIDDLE tag is discarded. Say that explicitly, because the honest description of this workflow is that it does not eliminate the cancellation class — it RELOCATES it from the fleet layer to the release layer, where it is benign: a superseded intermediate RC's fleet proof is genuinely uninteresting, and its absence is handled, since the gate reads WorkflowCheckMissing at that commit and falls through to the path-sensitivity walk exactly as it does for an incomplete green. A reader who believes 214 killed cancellation outright will be surprised the first time an intermediate RC has no runs; a reader told it moved the cancellation somewhere harmless will not.

AC#3 LAYER-TEST FINDING — the mechanic was right to surface it and the foreman's repoint is the correct immediate fix, but it is not sufficient as a METHOD. A prose comment satisfying a code assertion is the identical class we hardened the 216 arc-path pin against a few hours earlier. Ticketed as STATBUS-224: parse the YAML and assert on on.push.tags / on.push.branches instead of matching raw text, so comments cannot satisfy claims about triggers. Low, not a blocker.

ALSO TICKETED, neither blocking: STATBUS-223 (the RIDE relocation — the big one, see the separate ruling) and STATBUS-225 (three copies of the dispatch/correlate/poll script in one file; the correlation amendment above has to be written three times, correctly, which is the smell arguing for extraction on the next touch).

221's FOLD-IN: APPROVED as written. It is exactly the explicit form I specified, the comment states why and says not to simplify it back, and the behaviour is unchanged. Nothing further.
---
<!-- COMMENTS:END -->

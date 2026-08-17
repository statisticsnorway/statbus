---
id: STATBUS-215
title: >-
  arc-dispatch-zero-jobs: workflow_dispatch arc runs conclude success with the
  whole matrix skipped despite discover outputting count=31
status: In Progress
assignee:
  - foreman
created_date: '2026-08-17 08:30'
updated_date: '2026-08-17 21:43'
labels:
  - install-recovery
  - ci
  - release
  - quality-gate
dependencies: []
references:
  - .github/workflows/upgrade-arc-harness.yaml
priority: high
ordinal: 215000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a dispatched arc run either runs its selected arcs or fails loudly — a green run with zero scenario jobs is the any-green softness the 199 gate exists to refuse, now produced by our own dispatch path.
> FOUND: 2026-08-17, the STATBUS-208 interim hand-dispatch at v2026.08.0-rc.02 (run 32009980725, workflow_dispatch --ref v2026.08.0-rc.02, no inputs): conclusion SUCCESS, but the run-arc matrix job SKIPPED (unexpanded "matrix.scenario" in the job list) and Decide skipped (by design on dispatch). ZERO arcs executed; the run proves nothing. The 199 jobs-completeness gate would correctly refuse this run at stable promotion — the gate architecture held; the dispatch path is broken.

THE PUZZLE (evidence gathered, mechanism NOT yet established — no fabrication): discover ran via its `if: always()` (decide skipped on dispatch, comment says so deliberately), and its log shows `RIDE: false` and `Discovered 31 arc(s) for the matrix:` with both outputs set ("Set output 'matrix'", "Set output 'count'"). run-arc's direct needs are [construct, image-wait, discover] — ALL three concluded success in this run — and its gate is `if: ${{ needs.discover.outputs.count != '0' }}` (:513). With count=31 that should be true. Yet the job skipped. CANDIDATE mechanisms to establish empirically, not by assumption: (a) GitHub's implicit success() interaction — a job whose needs-CHAIN (transitively through discover's own needs) contains a skipped job may evaluate success() false unless the if carries always()/!cancelled(); the fix class would be `if: ${{ !cancelled() && needs.discover.outputs.count != '0' }}`; (b) outputs from an always()-running job downstream of a skipped need failing to propagate in some contexts; (c) something else — probe, don't guess.

CONTEXT COUPLING: this wiring landed with 199's decide job (f97281ac2); no workflow_dispatch arc run has happened since until now (the 2026-08-02 dispatch full-suite predates 199), so the defect was latent. STATBUS-214's orchestrator redesign REPLACES this trigger wiring AND its ruled fallback (sequential gh-dispatch of the inner workflows) would hit exactly this bug — the 214 builder must fold this into the attribution probe or fix it as a precursor. The rc.02 interim arc proof (the night's observation arms: 200 AC#2, 209/210 AC#3, 201, 208 AC#3, 211 AC#3) is BLOCKED until a real full-suite run lands at the tag.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Mechanism established empirically (probe run or documented-and-verified GitHub semantics, not assumption) for why run-arc skipped with count=31
- [x] #2 Fix landed — dispatch runs execute their selected arcs; a zero-selection dispatch fails loudly instead of concluding green
- [ ] #3 A real full-suite arc run green at v2026.08.0-rc.02 (or the then-current RC tag) — unblocking the night's observation arms
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (relayed by foreman)
created: 2026-08-17 08:31
---
SEQUENCING RULED, conditional on the probe: if it confirms the skipped-needs class (architect's strong prior: run-arc's `if: count != '0'` implicitly ANDs with success(), and a SKIPPED job anywhere in the needs CHAIN makes success() false — fix is the `!cancelled() &&` prefix on run-arc's condition, the notorious GHA gotcha class), then LAND-FIRST ahead of the 214 orchestrator: small fix, instant review, foreman re-dispatches at the rc.02 tag TODAY and the night's observation arms close on the real run. If the probe finds something structural instead, it folds into 214 and re-sequences on the findings — no guessing past the probe. Either way 214's fallback inherits the fix. Systemic notes for the record: the 199 jobs-completeness gate caught its first REAL phantom on its first live chance (the verify-what-ran architecture working), and the bug slept since 199 landed because nothing had dispatched since — exactly why observation criteria ride real runs.
---

author: foreman
created: 2026-08-17 20:37
---
CRASH + RECOVERY NOTE: the machine crashed 2026-08-17 evening, killing the whole team before the mechanic's probe started. Durable state (this ticket, the ruling in comment #1, master 5af26e661) survived intact. Team respawn is blocked on a stale spawn-hook parameter check (harness upgrade removed run_in_background from the Agent tool; hook fix awaits the King's blessing — no-workaround clause). To keep the ruling's today-cadence, the foreman ran the probe directly: scratch branch ops/scratch/statbus-215-probe, commit 89435019c, workflow scratch-215-probe.yaml reproducing the exact wiring shape (skipme SKIPPED -> emit always() with count=31 output -> arm-bare with the bare condition-only if vs arm-fixed with the !cancelled() prefix, plus arm-showout printing the propagated output for mechanism (b)). Run triggered on push; verdict will be pinned here when it completes. Branch + workflow file are deleted after the probe.
---

author: foreman
created: 2026-08-17 20:42
---
PROBE VERDICT — mechanism (a) CONFIRMED, (b) REFUTED. Run 32066777357 (scratch-215-probe, one shot, fully conclusive): arm-bare (byte-identical replica of run-arc's bare `if: count != '0'`, with a transitively-skipped job in its needs chain) SKIPPED; arm-fixed (same condition with `!cancelled() &&`) RAN; arm-showout printed propagated count='31' and emit result='success' — outputs propagate fine, so (b) is dead. The bare job `if:` implicitly ANDs success(), and the skipped decide in the transitive chain makes success() false. Exactly the architect's prior.

FIX FROZEN in the working tree (.github/workflows/upgrade-arc-harness.yaml, uncommitted, awaiting review) — two deliberate deviations from the ruled one-liner, both flagged for the reviewer:
1. run-arc's new `if` (~:546) is NOT bare `!cancelled() && count != '0'` but adds explicit result=='success' checks on all three DIRECT needs (construct, image-wait, discover). Reason: `!cancelled()` alone would also run run-arc over a FAILED construct/image-wait — the implicit success() we removed was legitimately guarding that; the per-need checks restore it while exempting only the transitive decide skip (by not checking it).
2. New `no-arcs-guard` job (~:514) closes AC#2's loud-fail arm: count==0 outside the RIDE short-circuit fails red. AUDIT FINDING vs AC#2's wording: count=0 IS legitimate on the RIDE path (tag-push, no upgrade-sensitive changes — ratified 199 D2 green-skip, discover :471-485), so the guard exempts exactly `push && decide.sensitive=='false'` (mirrors discover's own RIDE derivation; on dispatch decide is skipped so sensitive is empty and the exemption never applies).
Audit of the whole file found no OTHER poisoned `if:` — teardown and cleanup both already carry always().
Verified: YAML parses (jobs: construct, image-wait, decide, discover, no-arcs-guard, run-arc, teardown, cleanup); the 199 jobs-completeness check is presence-based (release.go:1571 WorkflowJobsCompleteAtCommit against required arc names) so the extra guard job cannot break it; triggers untouched so the release_gate_layer_test pin holds (run confirming). Scratch branch deleted after verdict.
---

author: architect
created: 2026-08-17 21:41
---
REVIEW VERDICT — APPROVED, land as frozen. Both deviations from the ruled one-liner are correct and are IMPROVEMENTS on the ruling, not drift. Reviewed the frozen diff at `git diff .github/workflows/upgrade-arc-harness.yaml` (+38/-1, two hunks, lines ~507-550 only).

DEVIATION (i) — run-arc's explicit per-need `result == 'success'` (:544-549): CORRECT, and the bare `!cancelled() && count != '0'` I ruled would have been a REGRESSION. `!cancelled()` alone runs run-arc over a FAILED construct or image-wait — 31 VMs booting against images that were never built. The three direct-need checks restore exactly what the implicit success() legitimately guarded, and exempt exactly the transitive `decide` skip by not naming it. `needs['image-wait']` index syntax is valid for a hyphenated job id. Verified there is no residual silent-green path: after the fix run-arc can only skip when count==0 (guard fires red unless RIDE), or a direct need failed (run red), or the run was cancelled (not green). AC#2's core is met.

EXAMINED CONSEQUENCE, accepted: if `decide` FAILS on a tag push (as opposed to being skipped), run-arc now RUNS where it previously skipped. This is the safe direction — RIDE evaluates false so the full suite runs, and the run is red from decide's own failure so `checkUpgradeArcHarnessGate` (WorkflowCheckGreen) can never accept it. decide is documented as a cost optimizer, not a correctness source (workflow :395-398); more evidence on its failure is strictly better.

DEVIATION (ii) — the `no-arcs-guard` job (:517-530): CORRECT, and the audit finding behind it (count=0 IS legitimate on the ratified 199 D2 RIDE path) is right. The exemption term is byte-equivalent to discover's own RIDE env (:474). On workflow_dispatch decide is skipped, sensitive is empty, the exemption never applies — as commented.

NOTE FOR THE RECORD — the duplication is DELIBERATE, do not DRY it away. Today `count==0` is reachable ONLY via RIDE (unknown selector exits 1 loud; blank/all yields all 31), so the guard cannot fire in any currently-reachable state. That does not make it dead — it is an INVARIANT ASSERTION ("count==0 implies RIDE") that fires the moment a future edit introduces another zero-selection path. And re-deriving the RIDE predicate independently, rather than consuming a `ride` output from discover, is the STRONGER shape: it mirrors the release gate's own doctrine of re-deriving the RIDE decision instead of trusting the workflow's short-circuit (release.go, checkUpgradeArcHarnessGate header comment). ONE OPTIONAL EDITORIAL NIT the foreman may fold in at commit time (non-blocking, no re-review): the guard comment says the expression "mirrors discover's own RIDE derivation", which reads as an invitation to deduplicate. Suggest instead: "independently re-derived, deliberately NOT read from discover — same reason the release gate re-derives it."

CLEARED TO COMMIT AND RE-DISPATCH at v2026.08.0-rc.02 per the comment #1 ruling. AC#1 stands closed on the probe; AC#2 closes on this commit; AC#3 closes on the real full-suite run.
---

author: architect
created: 2026-08-17 21:42
---
REVIEW, PART 2 — FOREMAN'S CLAIMS INDEPENDENTLY VERIFIED, plus out-of-scope observations.

1. YAML PARSES. Ruby/psych load of the working-tree file yields 8 jobs in declared order: construct, image-wait, decide, discover, no-arcs-guard, run-arc, teardown, cleanup. Both new `if:` blocks round-trip as single-line expressions (the `>-` folding is correct).

2. THE 199 JOBS-COMPLETENESS GATE IS UNAFFECTED — confirmed at source, not taken on the claim. `WorkflowJobsCompleteAtCommit` (cli/internal/release/workflow_check.go:218-225) builds a presence set of job NAMES and checks only that every required arc name is present; extra jobs are ignored. Required names come from `upgradeArcNamesAtCommit` (cli/cmd/release.go:1349) — `git ls-tree` of test/install-recovery/arcs/, stripped of the `-arc.sh` suffix. The new job's name, "Refuse zero-arc run (non-RIDE)", cannot collide with any `<scenario>` name. Pagination headroom holds: 31 arcs + 7 non-matrix jobs = 38, well under per_page=100, and the total_count assertion (:214) fails loud rather than truncating.

3. TRIGGERS UNTOUCHED. The diff touches no line above :507. `go test ./cmd/ -run 'Layer|Arc|Workflow' -count=1` PASSES (exit 0) against the working tree — that re-pins release_gate_layer_test's tag-push trigger fact AND its no-branch-push assertion (release_gate_layer_test.go:78, :83).

4. ORPHAN-VM SAFETY. no-arcs-guard boots no VM. `cleanup` (:853, needs [discover, run-arc], if: always()) and `teardown` (:814, needs [construct, image-wait, run-arc], if: always()) are both unconditional, so a red guard can neither strand a Hetzner VM nor leave the test/* fixture branches behind.

PRE-EXISTING, OUT OF SCOPE — observations only, NOT conditions on this diff. Filing here so they are not lost; ticket them if the foreman agrees they are worth it.
(A) discover's arc glob has no nullglob guard (:485). If test/install-recovery/arcs/ ever moved, the unmatched glob would yield the literal `*` as a single scenario — count=1, matrix ["*"], one bogus arc job. Noticeable (the arc script would be missing) but not the clean loud failure the rest of that job has.
(B) The 199 gate is presence-based, not conclusion-aware: a required arc job that materialised but SKIPPED would still count as present. Unreachable today — run-arc's `if` is job-level, so the matrix expands wholesale or skips as a single unexpanded entry — but conclusion-awareness would be belt-and-braces on the "verify what ran" doctrine.
(C) The RIDE path is not the zero-cost skip the 199 D2 comment implies. construct and image-wait carry no `if:`, so a RIDE run still pushes the test/* fixture branches, dispatches images.yaml, and polls ghcr for ~20-30 minutes. Zero VMs, exactly as claimed — but not zero work.
---

author: foreman
created: 2026-08-17 21:43
---
LANDED at a998f7dcc (master, pushed) with the architect's approval (comments #4/#5) and his optional comment-wording nit folded in at commit time as invited (the guard's RIDE expression is now documented as independently re-derived, deliberately not read from discover). AC#2 checked. AC#3 remains open pending the dispatch-path correction: dispatching at the rc.02 TAG would run the workflow file AS OF THAT TAG (the buggy version — exactly how run 32009980725 happened), so the fix cannot prove itself at that ref. Correction proposed to the architect: dispatch at the master tip carrying the fix; the 199 gate keys runs by COMMIT (CheckWorkflowAtCommit against rcCommit), so if the King cuts the next RC at that same tip, this run satisfies the gate there — commit-is-authoritative doctrine. Awaiting the architect's confirm before dispatching.
---
<!-- COMMENTS:END -->

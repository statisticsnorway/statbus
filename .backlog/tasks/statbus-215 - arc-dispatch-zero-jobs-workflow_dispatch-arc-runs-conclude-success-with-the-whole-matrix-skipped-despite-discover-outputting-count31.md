---
id: STATBUS-215
title: >-
  arc-dispatch-zero-jobs: workflow_dispatch arc runs conclude success with the
  whole matrix skipped despite discover outputting count=31
status: In Progress
assignee:
  - foreman
created_date: '2026-08-17 08:30'
updated_date: '2026-08-17 20:42'
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
- [ ] #2 Fix landed — dispatch runs execute their selected arcs; a zero-selection dispatch fails loudly instead of concluding green
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
<!-- COMMENTS:END -->

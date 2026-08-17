---
id: STATBUS-215
title: >-
  arc-dispatch-zero-jobs: workflow_dispatch arc runs conclude success with the
  whole matrix skipped despite discover outputting count=31
status: In Progress
assignee:
  - foreman
created_date: '2026-08-17 08:30'
updated_date: '2026-08-17 20:37'
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
- [ ] #1 Mechanism established empirically (probe run or documented-and-verified GitHub semantics, not assumption) for why run-arc skipped with count=31
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
<!-- COMMENTS:END -->

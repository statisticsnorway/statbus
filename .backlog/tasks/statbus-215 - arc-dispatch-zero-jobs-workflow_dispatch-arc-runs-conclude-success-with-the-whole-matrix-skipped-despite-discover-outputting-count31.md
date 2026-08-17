---
id: STATBUS-215
title: >-
  arc-dispatch-zero-jobs: workflow_dispatch arc runs conclude success with the
  whole matrix skipped despite discover outputting count=31
status: To Do
assignee: []
created_date: '2026-08-17 08:30'
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

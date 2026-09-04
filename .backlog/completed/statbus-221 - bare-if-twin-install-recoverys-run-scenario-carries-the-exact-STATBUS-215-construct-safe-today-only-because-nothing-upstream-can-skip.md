---
id: STATBUS-221
title: >-
  bare-if-twin: install-recovery's run-scenario carries the exact STATBUS-215
  construct, safe today only because nothing upstream can skip
status: Done
assignee:
  - mechanic
created_date: '2026-08-18 08:35'
updated_date: '2026-08-18 11:55'
labels:
  - ci
  - install-recovery
  - quality-gate
dependencies: []
references:
  - .github/workflows/install-recovery-harness.yaml
  - .github/workflows/upgrade-arc-harness.yaml
priority: low
type: enhancement
ordinal: 221000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: install-recovery-harness.yaml discovers its scenario list, then runs one matrix job per scenario. The matrix job is gated so that a run selecting nothing does not try to expand an empty matrix: `run-scenario` declares `needs: discover` and `if: ${{ needs.discover.outputs.count != '0' }}` (:322-323).

WHAT GOES WRONG: that is the byte-shape of the STATBUS-215 defect. A bare `if:` on a job implicitly ANDs `success()`, and `success()` is false when ANY job in the needs chain was skipped — which is how the arc harness silently ran zero arcs on every workflow_dispatch while reporting green. Here it is currently harmless, but only by accident: `discover` has no `needs:` and no `if:` of its own, so nothing in the chain can skip, so `success()` is always true. The construct is one upstream conditional away from the same silent green-skip.

THE DETAIL: the arc harness acquired exactly such an upstream conditional when STATBUS-199 D2 added its `decide` job (skipped by design on workflow_dispatch), and the defect then slept undetected until the first dispatch months later — caught only because the 199 jobs-completeness gate refused the phantom run. The plausible trigger here is the same move: porting the D2 path-sensitivity RIDE to install-recovery, or any orchestrator work that makes discover conditional. STATBUS-214's orchestrator is active in this area now. test-install.yaml was audited at the same time and is structurally immune — a single job, no `needs:`, no `if:`.

THE FIX: give run-scenario the explicit form the arc harness now carries — `!cancelled() && needs.discover.result == 'success' && needs.discover.outputs.count != '0'`. Behaviour is identical today; the difference is that a future upstream conditional cannot silently reopen the class. This is the same treatment STATBUS-218 applied to the arc harness's image-wait, whose bare `if:` was also correct at the time and was made explicit anyway.

WHY THAT HELPS: the one remaining copy of a construct that has already cost this project a phantom green stops being latent. The two fleet harnesses then express the same guard the same way, so an auditor reading either one is reading the same rule rather than judging each on whether its particular upstream happens to be unconditional.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 run-scenario's `if:` names its need's result explicitly and carries !cancelled(), matching the arc harness's post-215 form
- [ ] #2 Behaviour is unchanged on both trigger paths: a tag push and a workflow_dispatch each still run the selected scenarios
- [ ] #3 The comment states WHY the explicit form is used, so it is not simplified back to a bare `if:`
- [ ] #4 Any other bare `if:` on a job with `needs:` in this file is audited in the same pass
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-08-18 09:49
---
Folded into the STATBUS-214 build per team-lead's instruction (architect's ruling) — install-recovery-harness.yaml was already in the 214 diff for its tag-trigger removal, so applied here in the same pass.

run-scenario's `if:` (was `${{ needs.discover.outputs.count != '0' }}`, bare) is now:
```
if: >-
  ${{ !cancelled() &&
      needs.discover.result == 'success' &&
      needs.discover.outputs.count != '0' }}
```
with a comment explaining the STATBUS-215 class and explicitly telling future editors not to simplify it back to a bare if (AC#3).

AC#2 (behavior unchanged): both trigger paths are unaffected — discover has no needs/if of its own so it can only ever be 'success' or 'failure' (never 'skipped'), meaning the explicit check evaluates identically to the old implicit-success() wrap in every reachable case today. Verified this holds for both the orchestrator's gh-dispatch path and a plain manual workflow_dispatch (STATBUS-214 didn't touch install-recovery-harness.yaml's internal discover/run-scenario/cleanup structure, only its top-level trigger).

AC#4 (audit the rest of the file): grepped every job — only 3 exist. `discover` has no needs. `run-scenario` is the fix above. `cleanup` (needs: [discover, run-scenario]) already uses `if: always()`, a status-check function, so it was never subject to the implicit-success() wrap — no change needed there. Nothing else to audit.

test-install.yaml confirmed structurally immune (single job, no needs, no if) — nothing to do, matching your own note.

Validated: `ruby -ryaml` parses clean, `actionlint` exits 0. This edit lives in the same frozen (uncommitted) diff as STATBUS-214 — see that ticket for the full build report.
---

author: foreman
created: 2026-08-18 11:55
---
LANDED at 816bd6ba4 inside the orchestrator unit, architect-approved: install-recovery's run-scenario carries the explicit !cancelled() + result-checked condition, identical behavior today, immune to the 215 poisoning class when anything upstream becomes skippable. Done.
---
<!-- COMMENTS:END -->

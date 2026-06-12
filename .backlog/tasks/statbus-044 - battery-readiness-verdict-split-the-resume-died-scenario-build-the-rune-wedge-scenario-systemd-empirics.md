---
id: STATBUS-044
title: >-
  battery-readiness: verdict-split the resume-died scenario + build the
  rune-wedge scenario + systemd empirics
status: To Do
assignee:
  - architect
created_date: '2026-06-12 21:51'
updated_date: '2026-06-12 21:54'
labels:
  - install-recovery
  - testing
  - battery
  - upgrade
dependencies: []
references:
  - test/install-recovery/scenarios/3-postswap-resume-died-rollback.sh
  - doc/diagrams/upgrade-timeline.plantuml
  - STATBUS-039
  - STATBUS-042
priority: high
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Three items that gate the deferred install-recovery VM battery (post-rune-install window; commits to scenarios must respect the freeze windows — land BEFORE a battery run starts or between runs, never during).

1. SCENARIO EXPECTATION UPDATE (battery-blocking, found in STATBUS-042): test/install-recovery/scenarios/3-postswap-resume-died-rollback asserts the PRE-039 contract — death during Phase=Resuming ⇒ always rolled_back (UPGRADE_DIED_DURING_RESUME). Post-039 (5eacd6305) the Resuming branch is ground-truth-gated: an AT-TARGET fabrication resumes FORWARD and converges to completed; only a POSITIVELY-BEHIND fabrication rolls back to the upgrade's own snapshot. The scenario almost certainly fabricates at-target state (a Resuming flag on a converged box) → RED against rc.02 for the RIGHT reason. Split it: fabricate-Behind → assert rolled_back + identity restore; fabricate-AtTarget → assert forward convergence to completed. Marked in doc/diagrams/upgrade-timeline.plantuml's TEST note.

2. RUNE-WEDGE SCENARIO (STATBUS-039 verification plan item 2): fabricate the rune shape on a VM — in_progress post_swap row + stale proxy container + crash-looping unit (NRestarts past the gate) — and assert: ./sb install takes over (SIGKILL-class, no SIGTERM delivered), resumes forward, recreates the full service set incl. proxy at the flag target, converges the row to completed, no restore ran, flag removed, a subsequent install is nothing-scheduled. Owner: architect (reconstructed the shape in the Go tests).

3. SYSTEMD EMPIRICS (engineer's confirm-empirically items from the 039 review): (a) NRestarts semantics across the exit-42 handoff — confirm the planned restart bumps the counter by exactly 1 and the per-dispatch reset-failed zeroes it (STATBUS-039 F2); (b) `systemctl --user reset-failed` on an ACTIVE unit resets the restart counter on the fleet's systemd version (≥244 behavior) — on older systemd the gate degrades to pre-039-conservative (logged), confirm the degradation is what ships. Both are one-VM checks; fold into the battery prep.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 rune-wedge scenario lands in test/install-recovery/scenarios/ and proves takeover→forward→completed with zero restores on a fabricated rune shape
- [ ] #2 NRestarts-across-exit-42 + reset-failed-on-active-unit confirmed on a VM (or the documented conservative degradation confirmed for older systemd)
- [ ] #3 All scenario commits land outside battery runs (freeze-window discipline)
- [ ] #4 3-postswap-resume-died-rollback rewritten to the four-case verdict matrix (canary-self-heal / transient-forward-succeeds / persistent-forward-loops / behind-rolls-back) ONLY AFTER the King settles the loudness question for the persistent case — on hold until then
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CORRECTION + HOLD (foreman code-trace, 2026-06-12, architect concurs — supersedes the description's item 1 and the original AC#1): the architect's "at-target fabrication converges to completed" model was WRONG for this scenario's shape. Actual post-039 behavior at Phase=Resuming, verdict AtTarget/Unknown: recoverFromFlag → resumePostSwap (forward again) — it does NOT mark completed. resumePostSwap's container canary marks completed ONLY when every version-tracked container is already at the flag target; otherwise applyPostSwap re-runs, and the scenario's kill is PINNED in the unit env through the whole watch window → the kill fires again → die → restart → LOOP: row stays in_progress, NRestarts climbs, the scenario's Phase 6 times out (its own "OLD retry-loop wedge" message). That is the 039 tradeoff BY DESIGN — at-target never rolls back (data loss past maintenance-off); it retries forward, loud (the posture that kept rune at zero data loss for 18 days).

CORRECT VERDICT-AWARE MATRIX (four cases, matched to real behavior):
0. at-target + containers ALREADY at flag target → immediate canary self-heal → completed, applyPostSwap never runs (the rune shape — covered by the rune-wedge scenario, item 2).
1. at-target + TRANSIENT failure (one-shot inject) → forward retry succeeds → completed.
2. at-target + PERSISTENT failure (pinned inject — the current scenario's shape) → loops forward, stays in_progress + loud, NO rollback. WHAT TO ASSERT HERE DEPENDS ON THE KING'S OPEN LOUDNESS DECISION (degraded-state/alert after N clearly-non-transient forward failures vs loop-loud-forever). Architect's input for that decision: any escalation must be OBSERVABILITY-only (named degraded signal / callback after N retries) — never a direction change; rollback stays forbidden at-target regardless of N.
3. behind → one-shot rollback to the upgrade's OWN snapshot (identity-keyed).

STATUS: scenario rewrite ON HOLD until the King settles loudness (foreman carrying the fork to him). Item 2 (rune-wedge scenario) PROCEEDS — it is case 0, independent of the loudness question. Item 3 (systemd empirics) unaffected.
<!-- SECTION:NOTES:END -->

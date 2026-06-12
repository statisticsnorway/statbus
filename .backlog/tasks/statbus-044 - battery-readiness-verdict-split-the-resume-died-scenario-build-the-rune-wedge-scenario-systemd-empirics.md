---
id: STATBUS-044
title: >-
  battery-readiness: verdict-split the resume-died scenario + build the
  rune-wedge scenario + systemd empirics
status: To Do
assignee:
  - architect
created_date: '2026-06-12 21:51'
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
- [ ] #1 3-postswap-resume-died-rollback split per verdict: Behind-fabrication asserts rolled_back via the upgrade's own snapshot; AtTarget-fabrication asserts forward convergence to completed
- [ ] #2 rune-wedge scenario lands in test/install-recovery/scenarios/ and proves takeover→forward→completed with zero restores on a fabricated rune shape
- [ ] #3 NRestarts-across-exit-42 + reset-failed-on-active-unit confirmed on a VM (or the documented conservative degradation confirmed for older systemd)
- [ ] #4 All scenario commits land outside battery runs (freeze-window discipline)
<!-- AC:END -->

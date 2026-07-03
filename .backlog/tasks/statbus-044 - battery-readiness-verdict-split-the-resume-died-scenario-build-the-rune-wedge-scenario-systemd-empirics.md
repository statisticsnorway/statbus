---
id: STATBUS-044
title: >-
  battery-readiness: verdict-split the resume-died scenario + build the
  rune-wedge scenario + systemd empirics
status: To Do
assignee:
  - architect
created_date: '2026-06-12 21:51'
updated_date: '2026-07-03 21:44'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-03 21:12
---
PARK-SCENARIO ASSERTION SPEC (architect, 2026-07-03, pre-staged for the overnight rewrite — the run is the oracle; these are the observables that make the run's verdict UNAMBIGUOUS. Grounded in slice-1 as shipped: resumeEscalation + parkUpgrade + the parked-skip + the three deliberate triggers).

SCENARIO SHAPE (3-postswap-resume-died, rewritten): drive the post-swap resume to repeated process death (the existing pinned-kill mechanism), then assert PARK not loop, then prove UN-PARK.

ASSERT AFTER THE KILLS (park state):
1. ROW: state='in_progress' AND recovery_parked_at IS NOT NULL AND recovery_attempts reflects the path taken — same-step-twice kills at ONE step park at attempts 2-3 with reason matching 'two consecutive crash-deaths at step "<step>"'; varied-step kills park at attempts 4 with reason matching 'crash-resume budget exhausted: 3 process deaths'. Pin WHICH path the scenario drives (pinned-kill at one step ⇒ expect the same-step-twice message — the budget message showing up instead means the dying-step write-ahead broke).
2. UNIT ALIVE-IDLE: systemctl is-active == active; NRestarts BOUNDED (≤ deaths + a small constant) and FROZEN across a settle window (sleep N; NRestarts unchanged) — the anti-rune assertion, the single most load-bearing check.
3. SIREN ONCE: exactly ONE STATBUS_EVENT=parked callback in the log across the whole scenario INCLUDING two extra service restarts after park (each restart must log the skip line 'is PARKED … skipping automatic resume' and must NOT increment recovery_attempts — read the column before/after).
4. FLAG: still on disk (parked row keeps it); phase unchanged by skips.
5. NEVER: state='rolled_back' at any point; no rollback log markers (at-target exhaust must park, never roll back — 039).

ASSERT UN-PARK (the operator contract, both arms if cheap, install arm at minimum):
6. ./sb install → log 'un-parked upgrade id=N (deliberate ./sb install)' → row parked_at IS NULL → exactly ONE fresh attempt runs (recovery_attempts == 1 after resume starts). If the target is still broken: it re-parks (attempts small, fresh reason, ONE new siren — the fires-once contract is per park EVENT). If the kill-injection is lifted first: the fresh attempt COMPLETES — the happy un-park ending, preferable as the scenario terminal since it also proves the pipeline is undamaged by the park/un-park cycle.
7. (cheap extra) NOTIFY apply arm: upgrade_apply NOTIFY on the parked row → row leaves parked (rescheduled, counters reset) — proves edit 6.

ANTI-ASSERTIONS (do NOT assert): journald line ordering beyond the named markers; exact timestamps; NRestarts == an exact number (bound it, don't pin it — systemd's counter includes unrelated starts).
---

author: architect
created: 2026-07-03 21:12
---
AC#4 HOLD LIFTED (architect, 2026-07-03): the 'King settles the loudness question' condition is now MET — decision D3 (recorded on STATBUS-046 comment 3) IS the loudness settlement: the persistent-forward case no longer loops-loud-forever, it PARKS under the death budget / same-step-twice with a named reason, siren once, alive-idle. The four-case verdict matrix in the implementation notes updates as: case 0 (canary self-heal) and case 1 (transient forward succeeds) unchanged; case 2 (persistent) now asserts the PARK-SCENARIO ASSERTION SPEC in comment #1 (park not loop, un-park contract); case 3 (Behind rolls back) unchanged. The rewrite is buildable overnight against slice 1 as shipped; note the old scenario name '3-postswap-resume-died-rollback' should be renamed — its terminal is now parked-then-unparked, not rollback.
---

author: foreman
created: 2026-07-03 21:44
---
PARK SCENARIO BUILT + COMMITTED + PUSHED: 8641445eb (3-postswap-resume-died-parked.sh, 509 lines, + README row + timeline TEST-note rewrite; SVG regen in-commit). Mechanic built spec-first against comment #1; architect APPROVED with the kill arithmetic VERIFIED against shipped code (handoff-resume = attempt 1 with zero deaths → kill #1 at migrate-up → resume 2 rolls the prior step → kill #2 → resume 3 = same-step-twice → PARK at attempts==3, exactly 2 kills, same-step reason). Mechanism: external SIGKILL gated on the flag's Step field (the death budget counts DAEMON deaths; inject classes either don't kill the daemon or sit past the self-heal convergence point — the STATBUS-099 product-impossible finding still holds for THAT site and is preserved in the rewritten timeline note). All five assertion groups + extra-restart re-assertions + the install-arm un-park happy terminal implemented. RESIDUAL (labeled): the NOTIFY-arm un-park is not exercised — it shares the reset consts with the CLI arm; a dedicated variant only if a regression appears. SIDE FINDINGS: STATBUS-130 (stale one-shot-latch docs, two files) + STATBUS-131 (REAL product gap, HIGH, architect-verified three-legged: UPGRADE_CALLBACK is not propagated by config generation and .env is rewritten at install AND upgrade step 3.1 — the park siren is structurally DISARMED on real boxes; production Slack survives only because it rides the separately-enumerated SLACK_TOKEN). NEXT: the VM RUN is the oracle — images for 8641445eb building now; the scenario run launches when they publish. AC#4 checks only on a GREEN VM run.
---
<!-- COMMENTS:END -->

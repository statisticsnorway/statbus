---
id: STATBUS-192
title: >-
  selfheal-serve-proven: completeInProgressUpgrade marks 'completed' without
  serving — the flagless self-heal must converge the BOX, not just the row
status: In Progress
assignee:
  - engineer
created_date: '2026-07-15 08:52'
updated_date: '2026-07-18 12:49'
labels:
  - upgrade
  - install-recovery
  - defect
  - safety-core
dependencies: []
priority: medium
ordinal: 193000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: 'completed' means THIS VERSION VERIFIABLY SERVES (the STATBUS-160 doctrine) — at EVERY writer, including the flagless self-heal. A box must never carry a completed ledger row while its app is down.
> FOUND: 2026-07-15, the flagless-selfheal successor arc's U5 set-difference check (STATBUS-071). The arc kills a real upgrade at-target BEFORE StartServices, truncates the flag, and the flagless boot's completeInProgressUpgrade (service.go:2860) converges the row to 'completed' — with app/worker/rest still DOWN. Code-verified: the routine checks DB health only (waitForDBHealth 30s → 'failed' on miss) + observed-state at-target; it never starts app services and never runs the app health gate. The deleted interim scenario's assert_health_passes was ILLUSORY coverage — it passed because the fabricated row sat on an already-running box, not because the self-heal produced a serving one.
> WHY IT MATTERS: real producers of the flagless state exist (corrupt-flag removal, tmp/ flag loss — the r19-ruling producers) at any pipeline point, including pre-StartServices. A box that self-heals to completed-while-dark lies to the operator AND to STATBUS-170's convergence poll (green = row completed — the poll inherits the lie). Broader than the services-down corner: even with services up, an unparked broken-app at-target row self-heals to completed with zero serving proof.
> COMPLEXITY: engineer, medium — the fix mirrors machinery that already exists.

FIX SHAPE (architect): completeInProgressUpgrade's completed write becomes SERVE-PROVEN — after the existing DB-health + observed-state-at-target gates pass, run the same tail resumeNewSb runs: bring the app set up (compose up), run the SAME app health gate, maintenance off, THEN completed. A health failure routes to the SAME disposition resumeNewSb uses (park-at-target via parkForDeterministicFailure — named reason, one siren, alive-idle) — never a completed lie, never a silent dark box. The 135 parked-skip guard stays first (a parked row is untouched).

ORACLE: the flagless-selfheal successor arc gains the health assert (assert_health_passes after convergence) — the exact assert whose set-difference absence surfaced this ticket; the arc's kill-before-StartServices construction is the natural RED→GREEN proof (red on current code, green with the fix).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 completeInProgressUpgrade brings the app set up + runs the app health gate + maintenance off BEFORE the completed write; DB-health + observed-state gates unchanged; 135 parked-skip stays first
- [ ] #2 Health failure routes to park-at-target (parkForDeterministicFailure: named reason, one siren, alive-idle) — never completed-while-dark, never a silent dark box
- [ ] #3 The flagless-selfheal successor arc gains assert_health_passes after convergence — RED on pre-fix code, GREEN with the fix (the run is the oracle)
- [ ] #4 Architect frozen-diff review before commit (recovery safety-core)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-16 12:55
---
King ruling (2026-07-16): STATBUS-192 GATES the stable cut. Fork resolved as 'finish tail first' — no cut until the serve-proven completed write ships and is proven. Fix as ruled: completeInProgressUpgrade's completed write becomes serve-proven — run resumeNewSb's tail (app setup → app health gate → maintenance off → completed); health failure → park-at-target. RED→GREEN oracle: the flagless-selfheal arc's kill-before-StartServices run. Engineer builds, architect frozen-diff review.
---

author: architect
created: 2026-07-18 12:49
---
FIX SHAPE refinement (architect, 2026-07-18, pre-build — premises verified at writing time). Three additions the build must carry; my AC#4 frozen-diff review checks them.

1. THE TAIL INCLUDES THE READ-ONLY WINDOW LIFT. The window engages at step 2 (service.go:5305) and lifts only at completion (:6213) or rollback (:7524). Every flagless at-target orphan therefore carries window ON. Today's heal completes without lifting it, so the boot backstop clearStaleReadOnlyWindow (:2217) fires ROUTINELY on this path — but its firing is defined as an investigation trigger (:3521 'RECURRENCE INDICTS'), and the tick-belt caller (:2312) has no backstop after it at all. A completed box that rejects every write with 25006 is 'a broken box masquerading as healthy' (:6209). Build: after the completed write lands, run terminalExec(windowOffSQL) with the same COMPLETION_READ_ONLY_WINDOW_LIFTED escalation as :6213-6220. Ordering as in applyNewSbUpgrading — completed UPDATE first (senior truth), then the flip, loud on failure.

2. HEALTH-FAIL PARK MUST END IN THE STANDARD PARKED SHAPE: parked row + flag file on disk + flock free + unit alive-idle. Premise: UnparkByID's sole caller is install_upgrade.go:315, inside runCrashRecovery, reachable only via StateCrashedUpgrade (flag present, flock free). A park from THIS caller writes no flag (parkUpgrade is row-only, :6528), so the parked row would be invisible to the install ladder (box probes nothing-scheduled) — while the park's own operator message (:5628) promises 'run ./sb install for a fresh attempt'. The promise must be kept. Build: on the health-fail path, BEFORE parking, materialize a faithful flag — the synthesized-flag genre already ruled for the flagless rollback (:3001-3019): ID/CommitSHA from the row, Trigger 'recovery', Holder service, Phase PhaseNewSbSwapped (the at-target truth; next boot's recoverFromFlag routes it to resumeNewSb, whose parked-skip holds alive-idle, flag kept), BackupPath from the row (persisted pre-migrate, so populated at-target). Write the file directly (json.MarshalIndent + os.WriteFile), do NOT acquireFlock — the flock is the destructive-work mutex and this pass is going idle; flag-present + flock-free is exactly the un-parkable state, and install's takeover quiesces the unit first by design. Order: flag write, THEN park row — a crash between the two leaves an ordinary crashed-upgrade, never the invisible shape. If the flag write itself fails (ENOSPC is a live park cause), park anyway and warn loudly that install-un-park is unavailable and scheduling a fix release remains the trigger (degrade, don't block the park). Consequence: the unconditional defer removeUpgradeFlag() (:2907) must NOT strip this flag — set a named parkedExit bool on the park path and check it in the defer. Do not re-read park state in the defer (a failed read defaults wrong); the bool is the truth of THIS pass. 135's own principle: parked rows keep their flag.

3. COMPOSE-UP FAILURE MIRRORS THE EXISTING THREE-WAY (:6074-6093): diskPrecheckReason → park; classResource (ENOSPC backstop) → park; anything else → newSbUpgradingFailure, which at-target reduces to recordInProgressFailure — row stays in_progress, forward retry on the next tick/boot. Never completed, never a new hand-rolled disposition.

Build notes (review checklist, not new rulings): (a) the tail runs with a LIVE progress log — today appendLog is closed at :3027 right before the completed write; the health/park narrative must reach the on-disk log served at /upgrade-logs. (b) 135 parked-skip stays first, unchanged. (c) supersede/callback/pruneBackups ordering stays post-completed as today. (d) AC#3: the arc adds assert_health_passes after convergence; compose-up + waitForRestReady warmup now sit inside CONVERGE_BUDGET_S=600 — do not pre-tune, the run is the oracle; if it times out, the budget is the first suspect, not the fix.
---
<!-- COMMENTS:END -->

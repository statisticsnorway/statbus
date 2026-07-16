---
id: STATBUS-192
title: >-
  selfheal-serve-proven: completeInProgressUpgrade marks 'completed' without
  serving — the flagless self-heal must converge the BOX, not just the row
status: In Progress
assignee:
  - engineer
created_date: '2026-07-15 08:52'
updated_date: '2026-07-16 12:55'
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
<!-- COMMENTS:END -->

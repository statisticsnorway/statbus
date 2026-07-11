---
id: STATBUS-147
title: >-
  unpark-repark-daemon-down: an install un-park whose fresh attempt re-parks
  leaves the upgrade daemon STOPPED — alive-idle violated on the
  deliberate-un-park path
status: In Progress
assignee: []
created_date: '2026-07-08 15:23'
updated_date: '2026-07-11 20:20'
labels:
  - upgrade
  - recovery
  - product
  - operator-ux
  - install-recovery
dependencies: []
references:
  - cli/cmd/install_upgrade.go
  - STATBUS-145
  - STATBUS-144
  - STATBUS-046
  - doc-029
priority: high
ordinal: 148000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: park means ALIVE-idle on every path — including the deliberate un-park that fails again. The upgrade daemon is the box's only delivery channel for the eventual fix; no recovery outcome may leave it dead.
> BENEFIT: closes a 144-class hole on the exact path an Albania operator will walk: parked box → run install → still broken → walk away to get the fix — today that sequence leaves the daemon DOWN (no discovery, no scheduled backups, no NOTIFY listener, no future siren) until someone manually starts a systemd user unit they don't know exists.
> STAGE: Stage 1 (recovery/operator-facing).
> COMPLEXITY: mechanic-simple once ruled (the ruling is on this ticket); the health-park arc is the standing oracle.
> DEPENDS ON: nothing. FOUND BY: the health-park arc build (doc-029), builder-flagged 2026-07-08.

THE MECHANISM (verified against cli/cmd/install_upgrade.go): runCrashRecovery quiesces the (possibly looping) upgrade unit SIGKILL-class before recovery (stopRestartUpgradeUnit, :155) and restarts it ONLY via a deferred closure gated on recovered==true (:150-161), which is set only after svc.RecoverFromFlag returns nil (:310). When the un-parked fresh attempt RE-PARKS (target still broken: health-past-warmup → parkForDeterministicFailure returns an error), RecoverFromFlag propagates the error → recovered stays false → the closure never fires → `./sb install` exits non-zero with the daemon unit INACTIVE. The quiesce-then-restart-on-success-only design predates the park regime; its rationale ("a failed recovery must not resurrect the unit into another loop", :148-149) was written for crash-loop recovery and is WRONG for the park terminal: a parked row makes restarting the unit SAFE BY CONSTRUCTION (the parked-skip renders every boot alive-idle — RecoveryBudgetGuard + resumePostSwap skips) and NECESSARY (the 144 ruling's decisive argument applies verbatim: a dead daemon can repair nothing; the alive daemon IS the delivery channel — the fix release arrives via schedule → NOTIFY → daemon claim, which cannot happen with the unit down).

WHY "the operator sees the non-zero exit" does not carry: the Albania frame — the operator's action is install; requiring them to also diagnose an inactive systemd user unit is the class the operator-UX doctrine forbids, and the NEXT siren cannot fire from a dead daemon.

FIX SHAPE (ruled, architect 2026-07-08): after a failed recovery, re-read the row's park state; if PARKED → fire the restart closure anyway, with a loud line ("upgrade re-parked; restarting the upgrade daemon alive-idle — it stays reachable for the fix release"). The conservative no-restart arm REMAINS for non-park failures (a genuinely broken recovery still must not resurrect a loop). Install's non-zero exit is unchanged — the attempt did fail; the box just stays autonomous. One state read + one condition widen; mechanic-simple.

ORACLE: the health-park arc (doc-029) — its step-4 workaround (explicit unit start after observing the inactive unit, traced comment naming THIS ticket) flips to asserting the product behavior (unit ACTIVE after re-park, no arc intervention) when this fix lands. The arc is the fix's regression net by construction.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After an install un-park whose fresh attempt re-parks: the upgrade daemon unit is ACTIVE (alive-idle via parked-skip), install still exits non-zero, and a loud line names the restart decision
- [x] #2 Non-park recovery failures keep today's conservative no-restart behavior
- [ ] #3 The health-park arc's step-4 workaround is removed and replaced by the product assertion (unit active post-re-park), proven on a real VM run
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-11 20:20
---
STATUS SYNC (foreman, 2026-07-11): the fix SHIPPED overnight 2026-07-08 in 16829b65d ('upgrade: a failed un-park no longer strands the daemon stopped') — shouldRestartAfterFailedRecovery re-reads the row's park state after a failed recovery and fires the restart closure when PARKED, with the loud line; the conservative no-restart arm retained for non-park failures and unit-tested (AC#2 checked). ACs #1/#3 (live proof on a real VM + the arc's step-4 workaround flipped to a product assertion) are BLOCKED BY STATBUS-154's final fix: the health-park arc has not yet reached its full green (waves 5-7 each caught a distinct upstream product bug — the arc doing its job). They land on wave 8, dispatched after 154's ruled package ships. Status corrected To Do → In Progress.
---
<!-- COMMENTS:END -->

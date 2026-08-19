---
id: STATBUS-240
title: >-
  preswap-terminal-error-class: the PreSwap double-crash terminal tells a
  healthy box it is degraded — a new error class needs the King's approval
status: To Do
assignee: []
created_date: '2026-08-19 00:15'
updated_date: '2026-08-19 10:08'
labels:
  - upgrade-recovery
  - operator-ux
dependencies: []
references:
  - cli/internal/upgrade/service.go
priority: high
type: bug
ordinal: 233000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An operator whose upgrade died twice before the swap is told their system is degraded and to contact support — about a database the product's own log says was never modified, when running ./sb install (their one tool) is what actually resolves it. The behaviour is right; the label lies, and for a statistical office that converts a self-serviceable state into a support ticket measured in days.

WHAT THE EVIDENCE SHOWS (engineer, rc.05 arc run 32187511838, ruled at STATBUS-228 comments #13-15): service.go:2966-2968 hard-codes error class ROLLBACK_FAILED_DB_RESTORE for the same-step-twice rollback terminal on BOTH routes. On the post-swap route the label is CORRECT (a restore genuinely failed). On the PreSwap route it lies three times: no restore was ever attempted (nothing to restore — the volume was never touched), "the system is in a degraded state" (the same log shows ./sb install completing and the box healthy), and "contact SSB support and involve your IT staff" (the operator can self-serve).

WHY THIS NEEDS THE KING: no existing error class fits. The engineer walked all fifteen (service.go:1946-1980): ErrRollbackDBRestore names a restore that did not happen; ErrResumeDied is post-swap by definition; GitCorrupt/ServicesUp/ServicesNotStopped/BinaryCorrupt each name a sub-step that never ran; ErrInstallPreconditionFailed is already used for the per-attempt reason lines. A NEW operator-facing error class is a change to the operator surface — the King reviews its name and message text before it ships (architect's ruling: one more cycle of a wrong-but-loud message beats an unreviewed 2am invention).

THE SHAPE OF THE FIX once approved: the :2966 terminal branches on whether the route is PreSwap (nothing moved) vs post-swap (restore failed); the PreSwap arm gets the new class with a message that says the truth — the upgrade never changed anything, the previous version is being restored to service, run ./sb install to retry or wait for the service's next attempt.

WHAT IS ACHIEVED: the African-NSO operator frame holds — the error text an unattended box shows is true, names the self-service remedy, and never sends a healthy system to support.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The King approves the new error class name and its operator-facing message text before implementation
- [ ] #2 The :2966 terminal distinguishes the PreSwap route (nothing moved) from the post-swap route (restore failed); the post-swap label is unchanged
- [ ] #3 The corrected arcs' assertions observe the new class on the PreSwap route at a suite run
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 10:08
---
ARCHITECT'S RECOMMENDATION for the King's approval (AC#1). Name and message text below; reasoning after, so he can rule on the words alone if he prefers.

**NAME:** `ErrUpgradeStoppedUnchanged = "UPGRADE_STOPPED_NOTHING_CHANGED"`

**OPERATOR-FACING MESSAGE:**

> The upgrade stopped before it changed anything.
>
> Your data was not modified and your installed version was not replaced. This system is still running the version it was running before, and it is serving normally.
>
> The upgrade was attempted twice and stopped at the same point both times, so it will not be tried again on its own.
>
> To try again: run ./sb install
>
> If it stops here again, the upgrade itself needs a fix. Report this message together with the version you were upgrading to.

**WHY THE NAME BREAKS THE PATTERN ON PURPOSE.** Every one of the fifteen existing classes names a failure of a thing that was attempted: MIGRATION_FAILED, BACKUP_FAILED, ROLLBACK_FAILED_DB_RESTORE (service.go:1961-1980). This one must not, because nothing failed in that sense — the upgrade declined to proceed and left the system exactly as it found it. If it were called UPGRADE_FAILED_PRESWAP it would sit in the list looking like its neighbours, and an operator scanning for damage would assume there is some. **The name should read differently because the operator's next action is different**, and the name is the one surface nobody can skip.

**WHY THE FIRST LINE IS THE REASSURANCE, NOT THE FAULT.** An operator meeting this text is frightened before they are curious — something went wrong with an upgrade to their statistical register. The single most valuable fact we hold is that their data is untouched, so it goes first, in the shortest sentence available. Everything the current text says at that moment ("degraded", "contact support and involve your IT staff") is not merely wrong, it is wrong in the most expensive direction.

**WHY "NOTHING CHANGED" RATHER THAN "PRE-SWAP".** PreSwap is our word for our machinery. It names the internal phase boundary correctly and tells the operator nothing they can act on. The class is read by people who have never heard of a swap.

**ONE THING I DELIBERATELY DID NOT PUT IN.** No estimate of what went wrong and no diagnostic guess. The honest position is that we do not know from this terminal alone, and a speculative cause would send the operator to investigate the wrong thing — which is the same defect as the current text, in a friendlier tone.

**INTERACTION WITH THE OBSERVATION CARD (doc-035, STATBUS-247).** The card's Step 5 asks the operator explicitly whether a failure message told them the system's state, whether data was affected, what to do next, and whether it sent them to support for something self-serviceable. This class is the first thing that question was written to catch. If the King approves both in the same sitting, the card gives us a standing check that the wording keeps working on someone who is not us.
---
<!-- COMMENTS:END -->

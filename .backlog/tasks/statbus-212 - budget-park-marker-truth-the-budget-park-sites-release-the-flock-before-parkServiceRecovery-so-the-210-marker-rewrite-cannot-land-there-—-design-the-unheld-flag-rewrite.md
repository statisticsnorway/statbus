---
id: STATBUS-212
title: >-
  budget-park-marker-truth: the budget-park sites release the flock before
  parkServiceRecovery, so the 210 marker rewrite cannot land there — design the
  unheld-flag rewrite
status: To Do
assignee: []
created_date: '2026-08-16 23:00'
updated_date: '2026-08-18 09:50'
labels:
  - upgrade-recovery
  - park
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - >-
    .backlog/tasks/statbus-210 -
    unpark-rollback-collision-the-un-park-grants-a-fresh-attempt-then-flag-based-recovery-classifies-the-same-row-cannot-reach-new-and-rolls-it-back.md
priority: medium
ordinal: 212000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: same as STATBUS-210 — the marker always describes the box; after a source-restoration, EVERY park class carries a truthful pre-swap marker so un-park's fresh attempt is never rolled back by an honest reader of a lying flag.
> FOUND: 2026-08-17, engineer's flock note during the 210 build (correctly not scope-expanded at the night's last freeze; architect ruled follow-up over extension). The 210 fix rewrites the flag via mutateHeldFlag on the era-permitted restoration success arm — which requires the HELD flock. The resource/deterministic park path (applyNewSbUpgrading) holds the flock throughout, so the rewrite lands — tonight's arc-proven coverage. But the STATBUS-204 BUDGET-park sites (RecoveryBudgetGuard, resumeNewSb same-step-twice) release the flock BEFORE parkServiceRecovery runs: there mutateHeldFlag returns "no flag file held", the Warning fires, and the marker stays lying. A budget-parked, source-restored box that is later un-parked hits the SAME collision 210 kills on the main path.

THE DESIGN QUESTION (architect rules before build): how does a non-flock-holding park site truthfully rewrite the marker? Candidates to weigh: (a) briefly re-acquire the flock (LOCK_NB) at the rewrite moment — must reason about who else could hold it at that instant and the failure arm (can't acquire → leave marker, log, accept the stale-marker risk for that box); (b) restructure the budget sites to call parkServiceRecovery BEFORE releasing the flock (ordering change in the escalation path — must not violate the park-write-first pin or the flock's release contract); (c) an unlocked atomic rewrite with its own safety story (rejected on first look — the flock IS the write-serialization for the flag; do not create a second writer discipline). Frequency context: budget park (rare) × un-park (deliberate operator action) — low likelihood, but the collision when it fires destroys a granted attempt, same severity as 210.

ORACLE: extend the 210 unit set — budget-park + restoration success ⇒ marker rewritten (whatever mechanism is ruled); the un-park-after-budget-park story needs at least a structural unit; the arc-level proof rides whichever suite exercises budget parks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect ruling on the unheld-flag rewrite mechanism (re-acquire vs reorder vs other), with the failure arm named
- [ ] #2 The budget-park sites' successful restorations leave a truthful pre-swap marker; unit-pinned
- [ ] #3 No regression to the park-write-first pin, the parked-skip invariant, or the flock contract
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-18 09:50
---
DESIGN RULED — doc-031. The answer is NONE of (a), (b), (c): it is (d) parkServiceRecovery becomes SELF-SUFFICIENT for the flag hold, adopt-or-acquire at the top, release only what it acquired. Same shape as the STATBUS-204 ruling on this same function — the chokepoint owns its invariant. Every premise re-verified at writing time; ONE OF THIS TICKET'S OWN PREMISES DID NOT SURVIVE.

CORRECTION TO THE FILING — (b) WOULD HAVE FIXED HALF THE BUG SILENTLY. The description says both budget sites "release the flock BEFORE parkServiceRecovery". True at site 1 (RecoveryBudgetGuard acquires at service.go:6835, parks, calls release(), then calls the helper at :6920 — a reorder would work). NOT TRUE at site 2: resumeNewSb (service.go:7062) touches the flock EXACTLY ONCE in its entire body, at ~:7434 — AFTER the same-step-twice park branch has already called the helper at :7380 and returned. On that branch the flock was never acquired at all. Nothing to reorder because nothing was released. Had we ruled (b), site 1 would have gone green, the unit would have passed, and site 2 would have kept lying.

WHY (d) AND NOT (a) PER-SITE RE-ACQUIRE. The helper PROMISES truth-restoration (the 210 rewrite at :5882) but can only deliver it when its caller happens to hold the flock — a contract depending on ambient state it neither owns nor checks, which is the drift class the 196 gate hunts and which 204 comment #2 already ruled against for this exact function ("the chokepoint owns its invariant — every-caller-remembers-a-wrapper is precisely the drift class"). (a) re-creates that for every future park site; (d) fixes both budget sites with NO change at either call site, and every future one for free. (c) stays rejected for the reason the filing gives.

MECHANISM, precisely. Already held (`d.flagLock != nil && d.flagLock.file != nil` — the SAME predicate mutateHeldFlag uses at :599-601, not a new one): use it, do not acquire, do not release — the deterministic path stays byte-for-byte unchanged so 210's arc-proven coverage is untouched. Not held: read the current flag, acquire VERBATIM, defer release of exactly that lock. Note for the builder — acquireFlock TRUNCATES AND REWRITES the file with whatever flag value it is handed (:477-487), so a naive acquire clobbers the flag; the house idiom is read-then-acquire-verbatim, which site 1 already performs (`base := *flag`). Extract it as ONE named function rather than a third copy — an acquisition that must not change the flag's meaning should say so at the call site, and the failure arm then lives in one place. No deadlock risk: verified that parkServiceRecovery, parkEraVerdict and restoreSourceServices contain no acquireFlock and no flagLock reference anywhere in their bodies.

AC#1's FAILURE ARM, NAMED: a CONTENDED flock REFUSES THE WHOLE HELPER — narrate and return BEFORE any service is started. Not "restore anyway, skip the rewrite". A live holder IS the liveness signal that another actor owns box mutations (:461-463, STATBUS-111), and starting source services underneath a possible mid-upgrade actor is exactly the mixed-era guess parkEraVerdict refuses on every other anomaly (:5888-5891: "EVERY anomaly REFUSES ... the fail-safe direction is ALWAYS dark-behind-the-maintenance-page"). Near-unreachable in practice — the only realistic contender is ./sb install crash recovery, which quiesces this unit SIGKILL-class before it could hold the lock — but the arm must be correct, not merely rare.

FOLD IN STATBUS-204's OPEN NIT — THIS IS THE "NEXT TOUCH" IT WAS DEFERRED TO (204 comment #3). Site 1 attempts the restoration only if the progress log opens (:6918-6923), so a missing/unopenable log skips the restoration ENTIRELY and the box stays dark for a bookkeeping failure. Degrade to a discard writer: lose the narrative, never the box. Without it, "every park site leaves an operable box and a truthful marker" is still false at site 1 for a second, unrelated reason, and this ticket would close on a half-truth.

ORACLES (AC#2/#3): the 210 unit set extended to assert Phase == PhaseOldSbUpgrading on disk after a budget park + successful restoration at BOTH sites — site 2 is the arm that proves the ruling did more than reorder site 1. A source-parsing pin in the family that already guards this function: the adopt-or-acquire block precedes the era verdict, so a refactor cannot silently drop it (same protection the cover pin gives the watchdog ticker). A pin on the contention arm: no service start when the flock cannot be taken. Structural unit for un-park-after-budget-park; VM proof rides whichever suite exercises budget parks.
---
<!-- COMMENTS:END -->

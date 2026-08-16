---
id: STATBUS-212
title: >-
  budget-park-marker-truth: the budget-park sites release the flock before
  parkServiceRecovery, so the 210 marker rewrite cannot land there — design the
  unheld-flag rewrite
status: To Do
assignee: []
created_date: '2026-08-16 23:00'
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

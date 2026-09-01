---
id: STATBUS-172
title: >-
  arc-repair-by-follow-up: a migration that SUCCEEDS but leaves bad state,
  repaired by a later migration — the uncovered silent-corruption family
status: Done
assignee: []
created_date: '2026-07-13 10:42'
updated_date: '2026-07-13 11:15'
labels:
  - install-recovery
  - upgrade
  - test-fidelity
  - product
dependencies: []
priority: high
ordinal: 173000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the full "we shipped a migration that succeeded, then discovered it left bad data, and fixed it with a follow-up migration" loop is proven end-to-end on a real box — because this is the ONLY upgrade-failure family with zero arc coverage, and it is the highest-severity one (silent data corruption, not a loud crash).
> FOUND: 2026-07-13 — the King caught that no arc tests repair-by-follow-up when reviewing the STATBUS-034 close. The foreman had suggested this coverage be optional; the King refused, correctly: this whole weekend EVERY real defect (annotated-tag peel, register-fetch gap, PostgREST v14 schema park) was found only by doing the action on a real box, never by reasoning. A committed-but-wrong migration is exactly that class, at its worst.
> STAGE: install-recovery / arc framework. COMPLEXITY: architect designs the arc shape, mechanic/engineer builds, tester runs. THE RUN IS THE ORACLE — a VM arc, not a unit test.
> DEPENDS ON: the 071 arc framework (exists).

THE GAP, precisely: every current arc covers a migration that FAILS LOUDLY (crash, OOM, timeout, health-park) → rollback or park → fix → complete. NONE covers a migration that SUCCEEDS (exit 0, box healthy, upgrade completes) but leaves semantically wrong state — the kind discovered later, in production, by a data check rather than a crash. The repair path for that is a FOLLOW-UP migration that corrects the bad state on the next upgrade. That entire arc — apply-wrong-but-successful → observe bad state persists across the healthy upgrade → apply follow-up → observe state corrected — has no test.

WHY IT MATTERS MORE THAN THE loud families: a crash rolls back and protects the data by construction. A committed-but-wrong migration does the opposite — it commits, the box is green, and the bad data sits there until someone notices. The recovery machinery (rollback, park, terminal-state) does NOTHING for it, because nothing failed. The only defense is (a) catching it in review/test before ship, and (b) a clean repair-by-follow-up path when it slips — and we test neither today.

ARC SHAPE (architect to rule concretely; sketch): base install → migration B that SUCCEEDS but writes deliberately-wrong data (e.g. a backfill with an off-by-one or a wrong default) → upgrade COMPLETES green (the point: no failure signal) → an oracle asserts the bad state IS present (proving the hazard is real and undetected by the upgrade path) → follow-up migration C that repairs it → upgrade to C completes → oracle asserts the state is now correct. Real signed fixture commits, real discovery/procurement, real box — the 034 zero-scaffolding standard.

ORACLE: the arc runs green on a real VM AND its mid-point assertion proves the bad state was genuinely undetected by the healthy upgrade (a RED-half that would fire if we ever pretended completion == correctness), and the end assertion proves the follow-up repaired it.

NON-NEGOTIABLE (King, 2026-07-13): this is NOT optional coverage. It ships as a tested arc, same bar as every other install-recovery scenario.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect rules the concrete arc construction: how a committed-but-wrong migration is authored as a real signed fixture, and the mid-point oracle that proves the bad state is undetected by the healthy upgrade
- [ ] #2 A real-VM arc exists: base → successful-but-wrong migration → completes green → bad state asserted present → follow-up repair migration → completes → correct state asserted
- [ ] #3 The arc runs GREEN on a real Hetzner VM through real discovery/procurement (the 034 zero-scaffolding standard; the run is the oracle, not a unit test)
- [ ] #4 The mid-point RED-half is genuine: the assertion that the bad state persists across the healthy upgrade would fire if completion were ever conflated with correctness
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-13 11:15
---
CLOSED as invented-arc (King's challenge + architect's adversarial steelman, 2026-07-13). The King: a migration that succeeds but leaves bad state has only two cases — already-applied → fixed by a LATER migration (immutability forbids editing it); not-applied → fix the migration pre-release; both ordinary, no special recovery path. The architect steelmanned FOUR gap families before agreeing, each landing in existing coverage: (1) fleet-skew/repair-against-live-writes — REAL but pg_regress's genre (apply-V/write-data/apply-W/assert), an arc proves nothing extra at 100× cost; (2) repair-reaches-every-box — the existing arcs already prove forward-migration convergence from HARDER states (parked/failed/rolled_back); a completed box is the trivial case; (3) bad-state-breaks-machinery-later — already the health-park 145 fixture (a committed-but-wrong migration surfacing at health→park) + the fail-arc family; the machinery-INVISIBLE half is by definition not machinery-testable, only data-equality-testable = pg_regress; (4) the one real human trap — a restamp repairs BYTES not applied STATE. Verdict: the arc framework tests failure→recovery; a successful migration has neither. Foreman's original 'optional if you want it' framing was wrong and retracted at the King's push; the ticket itself was then correctly closed as inventing an arc for a data-correctness concern. RESIDUE MADE DURABLE (1b4e2bbdd, not left as notes): AGENTS.md repair-migration pg_regress pattern + the bless BY DESIGN block point 5 (restamp ≠ state repair). Real coverage was NOT dropped — machinery-visible arc-proven, data-correctness is pg_regress's charter, the human trap has its warning sign.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Closed as an invented arc, not a real gap — the King's challenge, confirmed by the architect's four-family adversarial steelman. The arc framework tests failure→recovery; a migration that SUCCEEDS (exit 0, box healthy, upgrade completes) has neither, so "committed-but-wrong repaired by follow-up" is normal forward migration sequencing, not a recovery scenario. Every steelman landed in existing coverage: data correctness (fleet-skew, repair-against-live-writes) is pg_regress's charter and cheaper there; forward-convergence is already arc-proven from harder states (parked/failed/rolled_back); the machinery-visible committed-but-wrong case is the health-park 145 fixture and the fail-arc family; the machinery-invisible half is by definition not machinery-testable. The two honest residues were made durable in docs (1b4e2bbdd): the repair-migration pg_regress pattern in AGENTS.md, and the restamp-repairs-bytes-not-state caveat as point 5 of the bless BY DESIGN block. Lesson banked: a "close as no-gap" conclusion got adversarial verification before action, not settled on assertion.
<!-- SECTION:FINAL_SUMMARY:END -->

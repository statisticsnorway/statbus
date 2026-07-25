---
id: DRAFT-002
title: >-
  upgrade-docs-coherence: diagrams ↔ code ↔ tests reconciled as one whole —
  timeline + recovery-model carry post-192/193 reality, every cell cross-linked,
  drift gated
status: Draft
assignee: []
created_date: '2026-07-25 19:21'
labels:
  - upgrade
  - install-recovery
  - documentation
  - coherence
dependencies: []
references:
  - doc/upgrade-timeline.md
  - doc/upgrade-recovery-model.md
  - test/install-recovery/arcs/
  - .backlog/tasks/statbus-071
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR (the King's standing directive, 2026-07-23 on STATBUS-071): the install/upgrade scenario diagrams are ONE COHERENT WHOLE with the actual code and tests — (a) the diagrams cover everything that needs covering, (b) a scenario covers what actually went wrong on Rune, (c) 071's own content is covered by the scenarios, (d) diagram ↔ code ↔ test with no drift.
> STAGE: Draft — the King approves or reshapes this entry at the architect's console session.

NAMED DRIFT (probe-verified 2026-07-25):
- doc/upgrade-timeline.md (last substantive touch 2026-07-14) carries ZERO mention of the PARK lifecycle and zero of the serve-proven completed contract — it predates the campaign's two biggest state-machine additions. (It DOES already carry the completed-label trio incl. [completed-self-heal] at :213.)
- doc/upgrade-recovery-model.md (2026-07-12) predates STATBUS-192 (completed = verifiably serves, at every writer), 193 (self-heal parked guard), and 195 (discovery watchdog false-kill).
- The 071 coverage map is the live diagram→run ledger and is CURRENT — the drift is between the PROSE DIAGRAMS and reality, not in the map.

THE WORK:
1. Reconcile doc/upgrade-timeline.md: add the park lifecycle (park → alive-idle → deliberate un-park / fix-release displacement), the serve-proven completed contract at every writer (192), and the completeInProgressUpgrade serve-proof tail. One pass, architect-reviewed.
2. Reconcile doc/upgrade-recovery-model.md: the parked-skip invariant at every automatic resume (135 + 193's self-heal guard), the 195 watchdog-cover principle, terminal-write immunity references current.
3. CROSS-LINK both directions: every diagram element names its covering arc/scenario (or names itself uncovered); every arc/scenario header names its diagram element. The 071 map is the join table — move its durable content into the docs or reference it explicitly.
4. RUNE COVERAGE STATEMENT (the King's point b): one named place in the recovery model states what actually went wrong on Rune in two layers — the extinct wedge (root cause fixed: e76505eec skip --now in fixup during active upgrade + 61e79e265 terminal-UPDATE-before-fixup + cb7344dd6 self-heal net) and the live class 'loops forever, nobody told' (covered by budget/park arcs, NRestarts-bounded asserts, the 069 canary).
5. DRIFT GATE: a structural check (008-genre or harness lib) that fails loudly when a new terminal state, park writer, or recovery dispatch arm lands in cli/internal/upgrade without its diagram line — the gate is on the VISIBLE artifact (the doc diff), per the gate-the-output principle.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 doc/upgrade-timeline.md carries the park lifecycle + the serve-proven completed contract (192) + the serve-proof tail; architect-reviewed
- [ ] #2 doc/upgrade-recovery-model.md carries the parked-skip-at-every-resume invariant (135/193) + the 195 watchdog-cover principle
- [ ] #3 Cross-links both directions: every diagram element names its covering arc/scenario or names itself uncovered; every arc/scenario names its diagram element
- [ ] #4 The Rune two-layer statement (extinct wedge with fix citations; live loop-forever class with its covering arcs) stands in the recovery model
- [ ] #5 Drift gate exists and fires on a probe: a new terminal state / park writer / recovery arm without a diagram line fails loudly
<!-- AC:END -->

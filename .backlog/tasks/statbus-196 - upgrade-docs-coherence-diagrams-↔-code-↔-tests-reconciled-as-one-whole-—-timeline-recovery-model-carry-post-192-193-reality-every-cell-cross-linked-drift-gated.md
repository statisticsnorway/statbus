---
id: STATBUS-196
title: >-
  upgrade-docs-coherence: diagrams ↔ code ↔ tests reconciled as one whole —
  timeline + recovery-model carry post-192/193 reality, every cell cross-linked,
  drift gated
status: To Do
assignee: []
created_date: '2026-07-25 19:21'
updated_date: '2026-07-27 07:45'
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
> NORTH STAR (King, 2026-07-23): the upgrade diagrams, the code, and the tests are one coherent whole. The diagrams cover everything that needs covering. One place states what went wrong on Rune. Everything 071 claims is covered by a scenario. Nothing drifts.

THE PROBLEM TODAY (probe-verified 2026-07-25):
- doc/upgrade-timeline.md does not mention the park lifecycle or the serve-proven completed contract. It predates both. (It already carries the completed-label trio, incl. [completed-self-heal], at :213.)
- doc/upgrade-recovery-model.md predates 192 (completed = verifiably serves, at every writer), 193 (the self-heal parked guard), and 195 (the discovery watchdog false-kill).
- The 071 coverage map is current. The drift is in the prose diagrams, not the map.

THE WORK, five steps:
1. TIMELINE. Add the park lifecycle (park → alive-idle → un-park by the operator, or displacement by a fix release) and the serve-proven completed contract. One pass. Architect reviews.
2. RECOVERY MODEL. Add the parked-skip invariant (every automatic resume skips a parked row — 135, 193) and the watchdog-cover principle (195: the watchdog kills hung daemons, never slow-but-live ones).
3. CROSS-LINK, both ways. Every diagram element names its covering arc or scenario — or says "uncovered", plainly. Every arc and scenario names its diagram element. The 071 map is the join table; reference it, or move its durable content into the docs.
4. THE RUNE STATEMENT. One named place in the recovery model says what went wrong on Rune, in two layers: the extinct wedge (root cause fixed — e76505eec skips --now in the fixup during an active upgrade; 61e79e265 lands the terminal UPDATE before the fixup, so the window no longer exists; cb7344dd6 adds the self-heal net) and the live class — a box that loops forever while nobody is told (covered by the budget/park arcs, the restart-bound asserts, and the 069 canary).
5. THE DRIFT GATE. A structural check that fails loudly when a new terminal state, park writer, or recovery dispatch arm lands in cli/internal/upgrade without its diagram line. The gate watches the visible artifact: the doc diff.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The timeline carries the park lifecycle and the serve-proven completed contract; architect-reviewed
- [ ] #2 The recovery model carries the parked-skip invariant and the watchdog-cover principle
- [ ] #3 Cross-links stand in both directions; "uncovered" is stated, never implied
- [ ] #4 The Rune two-layer statement stands in the recovery model with its fix citations
- [ ] #5 The drift gate exists and a probe proves it fires
<!-- AC:END -->

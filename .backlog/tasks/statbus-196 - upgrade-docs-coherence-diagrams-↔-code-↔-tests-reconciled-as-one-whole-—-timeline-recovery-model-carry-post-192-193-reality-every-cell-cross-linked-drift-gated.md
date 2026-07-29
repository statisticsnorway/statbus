---
id: STATBUS-196
title: >-
  upgrade-docs-coherence: diagrams ↔ code ↔ tests reconciled as one whole —
  timeline + recovery-model carry post-192/193 reality, every cell cross-linked,
  drift gated
status: In Progress
assignee:
  - architect
created_date: '2026-07-25 19:21'
updated_date: '2026-07-29 11:21'
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
- [x] #1 The timeline carries the park lifecycle and the serve-proven completed contract; architect-reviewed
- [ ] #2 The recovery model carries the parked-skip invariant and the watchdog-cover principle
- [ ] #3 Cross-links stand in both directions; "uncovered" is stated, never implied
- [ ] #4 The Rune two-layer statement stands in the recovery model with its fix citations
- [ ] #5 The drift gate exists and a probe proves it fires
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-07-29 11:14
---
GROUNDING RECONCILED (architect, 2026-07-29; operator legwork at tmp/agents/operator-196-142-legwork.md + my term-count verification — two partial records, one truth from the bytes):

TERM COUNTS, verified today: upgrade-timeline.md (last touch 07-14): parked 0, serve-proven 0, read-only-window 0 — but self-heal 7, boot-migrate 3. upgrade-recovery-model.md (07-12): parked 3, read-only-window 3 — but serve-proven 0, self-heal 0. So: the TIMELINE is the big gap exactly as drift-flagged (the park lifecycle, the serve-proven contract, and the window are entirely absent from the operator-facing lifecycle doc); the MODEL is NOT park-blind — it carries park + window and needs UPDATING to post-192/193/195 reality (serve-proven at every writer; the self-heal named inside the decision rules with its 193 parked-guard; the 195 watchdog-cover principle), not fresh authoring. My earlier 'both docs lack park' was overbroad; the operator's 'coherent and current' was too generous on the timeline — the counts are the record.

INVENTORY for step 3's cross-links: 30 real-path arcs + 15 scenarios, each with its one-line purpose, listed in the operator's file — the join-table raw material is gathered; the coverage-map on 071 remains the run-ledger side.

EXECUTION: I write the two doc passes myself (architect-lane — doctrine-heavy, the King's register), one doc per unit, foreman line-reviews + commits each; then the cross-links, the Rune statement, and the drift gate per the description's steps 3-5.
---

author: architect
created: 2026-07-29 11:20
---
UNIT 1 BUILT — THE TIMELINE PASS (architect, 2026-07-29; frozen for foreman line review + commit; one file, doc/upgrade-timeline.md, +125/-61). What the pass found went well beyond the flagged terms — the prose carried THREE eras of drift, all fixed:

1. AC#1 CONTENT, as planned: the PARK LIFECYCLE (a full tier under the renamed 'Complete / rollback / park' section — what parks, the atomic park write, one siren, alive-idle, flag kept, every-resume-skips, the two deliberate exits) + the parked-marker note after the state table (orthogonal to state; a deploy terminal for CI; why 159's displacement exists) + the SERVE-PROVEN completed contract at step 13 naming all three writers + the read-only window (engage at step 3, lift inside serve-proven completion, data-safety rationale).

2. FOUND DRIFT, fixed because a truthful doc can't carry it next to new content: (a) PRE-145 INVERSION — the prose claimed boot-migrate 'applies every upgrade's migration delta' and step 11 is 'normally a no-op'; reality is exactly opposite (floor-bounded boot, delta exactly once in the guarded step 11) — rewritten in both places; (b) PRE-164 NAMES — resumePostSwap/applyPostSwap/Phase=PostSwap/Resuming throughout → resumeNewSb/applyNewSbUpgrading/new-sb-swapped with the legacy-alias note; grep-zero stale refs now; (c) PRE-046 RETRY-FOREVER — the decision tree said an at-target box 'keeps failing forward, stays loud' unboundedly → now the attempt budget, first-occurrence deterministic park, same-step-twice, budget exhaustion; (d) added 144's flagless alive-idle guard + 195's discovery heartbeat to Service boot; (e) the two-row model names all three completed writers as serve-proven; (f) the renamed section's anchors updated everywhere.

3. INVERTED-DRIFT FINDING for step 3's cross-link work: the lifecycle DIAGRAM SOURCE (upgrade-lifecycle.plantuml:42-45) ALREADY carries the park — the diagrams were updated when 046 shipped; only the prose drifted. Step 3 verifies diagram completeness properly, but the assumed diagram-gap is smaller than feared.

AC#1 checks after the foreman's line review + commit. Unit 2 (the recovery-model pass) follows.
---

author: foreman
created: 2026-07-29 11:21
---
UNIT 1 (timeline pass) REVIEWED + COMMITTED 8cc4cca1c (foreman, 2026-07-29). Line review verified every load-bearing claim against code symbols, not prose: DaemonSchemaFloor exists at the boot site (145 floor-bound confirmed — service.go + daemon_floor_bootsite_test.go); PhaseNewSbSwapped='new-sb-swapped' with the post_swap/resuming legacy-alias map at service.go:253-301; resumeNewSb/applyNewSbUpgrading/newSbUpgradingFailure all exist (service.go:5718/5844/6773) and the OLD names are grep-zero in code AND in the doc; PriorDeathStep same-step-twice seam real (recovery_escalation.go:151); read-only window real (exec.go:351-366). Anchor check: zero references to the old #complete--rollback anchor repo-wide, 3 internal refs to the new #complete--rollback--park, heading present, no cross-doc links to the renamed section. AC#1 checked. The inverted-drift finding (lifecycle plantuml already carries the park) is noted for step 3's smaller diagram gap. Unit 2 (recovery-model pass) may proceed.
---
<!-- COMMENTS:END -->

---
id: STATBUS-120
title: >-
  pg-multi-control-test: investigate & add import test for multiple controlling
  relationships
status: Done
assignee:
  - engineer
created_date: '2026-06-30 12:40'
updated_date: '2026-07-14 10:36'
labels:
  - import
  - not-install-upgrade
dependencies: []
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: importing multiple controlling relationships into a power group is covered by tests before the reporting ships.
> BENEFIT: the exclusion constraint (≤1 primary controller per unit per type) and the derivation are proven under batch import — so the power-group reporting the King designed launches on verified import behavior, not assumed behavior.
> STAGE: Domain/import.
> COMPLEXITY: engineer-substantial (verify the real gap against the real test files first — the 117-121 labels in the ticket were written from memory — then author the pg_regress tests).
> DEPENDS ON: nothing.

---

Suspected GAP in test coverage: importing MULTIPLE control units / controlling relationships into a power group. The King flagged this while finalizing the power-group reporting design (see DRAFT-001 / `doc/power-groups.md`).

Existing coverage (test/sql/): 117 power_group_fundamentals, 118 worker_derivation, 119 roller_data, 120 lifecycle (incl. cycle + multi-root), 121 worker_info/ordering. Suspected uncovered: importing several *controlling* (primary) relationships in a way that exercises —
- a single influenced unit targeted by TWO would-be primary controllers of the same type → the exclusion constraint `legal_relationship_influenced_primary_excl` must reject the second;
- multiple control edges arriving in one import batch and the holistic `analyse_power_group_link` / `process_power_group_link` derivation under that load;
- multi-root formation via control (two roots merged), distinct from the percentage-driven path.

INVESTIGATE the precise gap first (don't assume), then add the missing pg_regress test(s). This is import/derivation coverage — separate from the reporting-API work in DRAFT-001.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Identify the specific uncovered scenario(s) for importing multiple controlling relationships (confirm the gap against tests 117-121 before writing)
- [x] #2 Add pg_regress test(s) covering import of multiple control relationships into a power group
- [x] #3 Assert exclusion-constraint behavior (<=1 primary influencer per influenced unit per type) and the process_power_group_link derivation outcome
- [x] #4 Expected .out blessed and the test passes under ./dev.sh test
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-02 18:13
---
DISPATCH-CLARITY NOTE (foreman, 2026-07-02): before relying on the 'existing coverage' list in the description, verify the actual test-file names first-hand (`ls test/sql/ | grep -iE 'power|legal_rel'`) — the 117-121 subject labels above were written from memory in another working copy and may not match the files exactly (e.g. 118 is described elsewhere as power_group_hierarchy). The INVESTIGATE-first instruction (criterion 1) covers this: confirm the real gap against the real files before writing any test.
---

author: foreman (relaying King)
created: 2026-07-14 09:46
---
KING REFRAME (2026-07-14 morning): two issues are mixed in this ticket — (a) real primary seeding (konsern) from custom URL, and (b) loading NON-controlling relationships (delt ansvar: multiple units in equal share control, none >50%) — which he believes today's load does NOT support. Must be discussed more before the 178 fix design is approved.

FOREMAN GROUNDING (verified this morning): primary-ness is per-TYPE config — legal_rel_type.primary_influencer_only, NSO-defined, denormalized onto rows (doc/power-groups.md:99,139-146). Norway's mapping (samples/norway/brreg/seed-legal-rel-types.sql + README): HFOR/EIKM/KOMP = primary TRUE (structurally 1:1 in BRREG); DTPR/DTSO (deltaker pro-rata/solidarisk — the delt-ansvar shapes for ANS/DA/KS) = FALSE. The brreg README's own 'Partnership Structures (Future)' section says DTPR/DTSO 'don't currently form power groups but could in the future via multi-root support' — while doc/power-groups.md:24 says ALL types contribute to formation and non-primary edges cluster into the same component. THE TWO DOCS DISAGREE (or the README predates multi-root support, which test 120 Phase 6 asserts exists). Open questions for the discussion: (1) does an import of only-DTPR/DTSO edges actually form a power group today? — empirically checkable; (2) is BRREG's no-percentage reality correctly modeled by type-only classification, or do we need percentage-bearing equal-share support for other sources; (3) does the 178 both-rows-error detector risk rejecting LEGITIMATE shared-control data that merely got mapped to a primary type?
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Investigation refuted 2 of the 3 suspected gaps ((b) multi-edge batches and (c) multi-root via control were already covered by tests 119/120/403) and confirmed gap (a) — duplicate primary controllers under import — which turned out to hide a real defect: one conflicting row failed the whole batch (STATBUS-178). Closed as one unit with 178 (commit fefa3fc36): test 124 covers the direct-INSERT exclusion rejection, per-row tier-1 errors on duplicate primaries, and mixed-batch isolation. The King's delt-ansvar reframe (equal-share non-controlling relationships, selectable reporting viewpoint) spun off as STATBUS-179.
<!-- SECTION:FINAL_SUMMARY:END -->

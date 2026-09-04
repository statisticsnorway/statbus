---
id: STATBUS-312
title: >-
  seed-path-divergence: full-rebuild and incremental seeds disagree on import
  definitions — 108 red only when someone rebuilds full
status: Done
assignee:
  - '@tester'
created_date: '2026-08-28 22:58'
updated_date: '2026-08-28 23:41'
labels:
  - testing
  - tooling
dependencies: []
priority: high
type: bug
ordinal: 305000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a seed built full-from-migrations and a seed built incrementally must be the same database. Tonight's full rebuild says they may not be — and the disagreement hid because full rebuilds are rare.

THE EVIDENCE (engineer's interim report during the 309 seed rebuild, 2026-08-28 ~23:00): 108_test_code_gen fails with a diff containing ZERO references to the night's new functions — pure import-definition drift: column ordinals shifted by exactly +3 (8,9,10 → 11,12,13) and a 673-line block present in expected, absent in actual. Nothing in any of tonight's units touches import definitions. Context that makes the lead credible: THIS rebuild went full-from-migrations (the cached seed artifact was stale on a February migration and was discarded), whereas the committed expected output was produced against an incrementally-built seed; 108's expected file was last touched by 40cfad0f5 ('clean up orphan import_source_columns after RENAME/DELETE...') — precisely the area where a differently-constructed seed would shift ordinals and drop rows.

THE HYPOTHESIS, stated as a lead not a conclusion (the engineer's framing, kept): full-rebuild and incremental seed paths disagree on import-definition state — a REPRODUCIBILITY gap that only 108 notices and only when someone rebuilds full, which is rare, which is why it lived. If real, anything that rebuilds a seed full (a fresh dev machine, CI seed loss, the fleet's preflight under artifact staleness) inherits a suite red that looks like the current unit's fault — tonight it nearly did.

INVESTIGATION SCOPE (read-only first): reproduce the attribution — diff the full-rebuilt seed's import-definition tables against a known incremental seed (or against what 40cfad0f5's migration SHOULD leave); identify whether the orphan-cleanup migration behaves differently on full replay (e.g., cleanup ran before data existed, or ordinal assignment depends on insertion order the two paths do differently); name the mechanism with bytes. THEN the fix design goes to the architect: make the paths converge, or make 108 order-independent, or both — whichever preserves what 108 exists to prove.

WHAT IS ACHIEVED: seeds are reproducible regardless of construction path, and a full rebuild can never again masquerade as the current unit's failure.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Additional evidence (engineer, 2026-08-29, during 309 verification on the freshly full-rebuilt seed):** the divergence is not confined to 108's mapping ordinals. Two baseline drifts surfaced on the same rebuilt database: (a) test/expected/performance/109_hierarchy_functions.perf cost estimates 5.03→15.72 with identical actual times — trivial statistics drift, discarded per testing rule; (b) the three test/expected/explain/303_* files show a PLAN-SHAPE change (Index Scan using idx_timeline_legal_unit_valid_period → Bitmap Heap Scan on timeline_legal_unit) — flagged, NOT discarded. Hypothesis: same root cause — a full-rebuild seed and an incrementally-built one are not the same database. Disposition: the 303_* changes stay uncommitted in the tree; after the forward repair migration lands and the seed rebuilds again, check whether the plans revert. If they do, that is the repair's second confirmation; if not, the 303 drift has a separate cause and gets its own investigation.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LANDED at 4fa8d5d29. Root cause named with bytes: the released cleanup migration 20260422011930 deletes import_source_column rows whose {name}_raw data column is absent — safe only after every generate-phase column settles, which a full-from-scratch replay does not guarantee; the fleet's incrementally-maintained boxes never take that path and hold the correct state. Architect ruled forward repair (172 shape), with the decisive reframing that this is NOT test-only: install.sh's seed-restore documents a silent full-replay fallback, so a fresh box could silently build the wrong database. Repair: purely reconstructive, calls import.synchronize_definition_step_mappings itself (the correct creator, idempotent by construction) rather than a second copy of its logic; never the cleanup side — replay moves TOWARD the fleet. Derivation verified from definitions BEFORE any SQL (the ruling's required order). Proven on a genuine full replay: zero diff in import_source_column/import_mapping baselines across the whole fast suite. Test 125: wrong-state → shipped-bytes repair via \i → restored + both negatives. Durable rule recorded in the migration header: a migration's data operations must not depend on their position in the replay sequence. The four REMAINING full-replay divergences that run surfaced (098 user ids, 108 import_data_column +6 priority base, 329 seeded upgrade row, 303 plans — all outside this table's scope) are STATBUS-314, with the architect classifying genuine-divergence vs fixture-sensitivity.
<!-- SECTION:FINAL_SUMMARY:END -->

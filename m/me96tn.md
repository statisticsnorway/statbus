---
id: me96tn
title: "Quality part 1: intarray, check catalogue table, empty relation tables"
state: "done"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzzzzy"
created: 2026-11-27
updated: 2026-11-27
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_b"
done_at: "2026-11-27T11:15"
---

## Goal
intarray is installed with int[] GIN indexes rebuilt, quality_check is a table with integer ids, and the two relation tables exist empty.

## Purpose
The parts of h9mhxe that touch neither statistical_unit_def nor the comparison view, so they can be built while the counting branch is rebased.

## Principle
Additive only: no change to statistical_unit, quality_finding_def, legal_unit_establishment_stat_comparison or derive_quality. Existing readers keep working unchanged.

## Details
1) intarray: add to the migrate runner's tracked extensions (cli/internal/migrate/extensions.go); migration rebuilds idx_statistical_unit_data_source_ids with gin__int_ops (verified: after CREATE EXTENSION intarray, int[] && resolves to intarray's operator and the array_ops index is skipped, a full scan; rebuilt it is used, 2 s on Norway). 2) public.quality_check_catalogue table (name to be settled against the existing quality_check view, which part 2 replaces): id int never reused, rule quality_rule, stat_definition_id FK NULL for row checks, kind (row|relation enum), priority; fixed row ids 1 missing_region, 2 missing_activity_category, 3 missing_physical_location, 7 secondary_activity_equals_primary; relation ids: 4 establishment_activity_differs, and one id per summed variable for each per-variable rule, kept by the stat_definition lifecycle callback. 3) Empty tables quality_establishment_activity_differs (legal unit row key unit_type, unit_id, valid_range; existence_from, existence_until, hash_slot, check_id FK, primary_establishment_id FK, legal_unit_activity_category_id FK, establishment_activity_category_id FK) and quality_legal_unit_establishment_stat (row key, existence dates, hash_slot, check_id FK, stat_definition_id FK, legal_unit_value, establishments_sum, establishment_count), RLS like quality_finding. Full spec and measurements: h9mhxe and its attached report.

## Depends on

## Acceptance
- [x] A SQL test shows the Data source filter's plan uses idx_statistical_unit_data_source_ids after intarray is installed, and fails on the migration's parent
- [x] A SQL test lists the catalogue's ids for the row checks and one per summed variable per relation rule, and a new summed variable gets its ids
- [x] Fast suite green; doc/db, types and the security report regenerated

## Notes

file:0pn35h-architecture.md (18977 bytes, sha256:dba4c962) Measured design report (owner decided 2026-11-27)


check 1: test/sql/415 EXPLAIN shows Bitmap Index Scan on idx_statistical_unit_data_source_ids; on parent (migration down, intarray installed) Seq Scan: tmp/test-me96tn-415-on-parent.log. Commit 3ac36cfc9
check 2: test 415 lists ids 1,2,3,4,7 and 101-104 (2 summed vars x 2 rules); new int var gets 105/106, string var none, delete removes, re-add gets 107/108 (no reuse)
check 3: migrate-and-test fast: 143/147 then the 4 generated tests (002/008/015/016) regenerated; 008 remaining diff only sql_saga 1.6 slot-image drift line kept as on master. doc/db, types, security report regenerated in 3ac36cfc9
Branch quality/part-1-catalogue-intarray @3ac36cfc9 pushed, not merged. Proposed final table name: quality_check (replacing the view in part 2); staging name quality_check_catalogue. Relation tables have no FK to statistical_unit (TRUNCATE CASCADE in statistical_unit_refresh would cascade); part 2 must add them to that refresh truncate.


## History
- 2026-11-27T10:12 todo -> doing/active (take)
- 2026-11-27T10:33 handed to rabbit: shrimp's session went silent (last seen 2026-11-18 15:18)
- 2026-11-27T10:52 doing/active -> doing/review (review: shrimp ticked the last own check)
- 2026-11-27T10:52 review 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-27T10:52 review 1 acknowledged by rabbit
- 2026-11-27T10:53 answered review, by rabbit, for rabbit (doing/review -> doing/active):
  > review by rabbit
  Looks right, one change: test 415 collides with the counting branch's test/sql/415_legal_unit_total_rollup_and_existence.sql (origin/counting/birth-date-and-lu-es-rollup), which lands first. Renumber yours to 417_quality_check_catalogue_and_intarray (sql and expected), rerun it, push, and I fast-forward after the counting branch. Everything else reviewed and accepted: the runner's tracked intarray with its Go tests; data_source_ids and the three timeline related_*_ids GIN indexes rebuilt with gin__int_ops; the catalogue with fixed ids 1,2,3,4,7 and identity from 101, never reused, kind and variable checks, lifecycle callbacks; the two relation tables with check-fixing CHECKs, (check_id, stat_definition_id) FK, NOT ENFORCED temporal FK to establishment; RLS and the security report; the note that part 2 must add the relation tables to statistical_unit_refresh's TRUNCATE.
- 2026-11-27T11:15 doing/active -> done (done); was doing_since: 2026-11-27T10:12

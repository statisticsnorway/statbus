---
id: me96tn
title: "Quality part 1: intarray, check catalogue table, empty relation tables"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzzzzy"
created: 2026-11-27
updated: 2026-11-27
doing_since: "2026-11-27T10:12"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_b"
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
- [ ] A SQL test lists the catalogue's ids for the row checks and one per summed variable per relation rule, and a new summed variable gets its ids
- [ ] Fast suite green; doc/db, types and the security report regenerated

## Notes

file:0pn35h-architecture.md (18977 bytes, sha256:dba4c962) Measured design report (owner decided 2026-11-27)


check 1: test/sql/415 EXPLAIN shows Bitmap Index Scan on idx_statistical_unit_data_source_ids; on parent (migration down, intarray installed) Seq Scan: tmp/test-me96tn-415-on-parent.log. Commit 3ac36cfc9


## History
- 2026-11-27T10:12 todo -> doing/active (take)
- 2026-11-27T10:33 handed to rabbit: shrimp's session went silent (last seen 2026-11-18 15:18)

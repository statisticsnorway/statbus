---
id: h9mhxe
title: "Quality checks: row checks on statistical_unit, a table per relation check"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzt"
created: 2026-11-27
updated: 2026-11-27
---

## Goal
Store each quality check where its kind fits, keyed by integer check ids.

## Purpose
Owner decision 2026-11-27 after measuring three designs on the Norway copy (attached report on 0pn35h). Row checks cost nothing extra on the statistical_unit write and are current with every edit; quality_finding (2.3 M rows, 946 MB) and about 40 s of every full derive go away; relation tables are typed, carry foreign keys and are written concurrently.

## Principle
Two kinds of check. A row check is decided by one statistical_unit row and is a generated element of that row's int[]. A relation check compares a unit with others and has its own table with typed columns and FKs, one row per check, a scalar check_id. intarray is installed and every GIN index on an int[] is rebuilt with gin__int_ops. Build after the counting branch (f2gx3m, s465ff) lands: both change statistical_unit_def and the comparison view.

## Details
Catalogue: public.quality_check becomes a table (id int stable never reused, rule quality_rule slug, stat_definition_id FK NULL for row checks, kind row|relation, switched_on boolean replacing quality_check_switched_on, priority). Row-check ids fixed: 1 missing_region, 2 missing_activity_category, 3 missing_physical_location, 7 secondary_activity_equals_primary; per-variable relation checks get an id per variable from the stat_definition lifecycle callback. statistical_unit: quality_check_ids int[] GENERATED from the row (same expressions as today's quality_finding_def row branch); GIN (quality_check_ids gin__int_ops); partial covering index (existence_from, existence_until) INCLUDE (quality_check_ids) WHERE quality_check_ids <> '{}' for the dashboard. statistical_unit_staging and the flush MERGE carry it. Migration rewrites statistical_unit once: 11 min on Norway. Relation tables: quality_establishment_activity_differs (legal unit row key, existence dates, hash_slot, check_id, primary_establishment_id FK, legal_unit_activity_category_id FK, establishment_activity_category_id FK); quality_legal_unit_establishment_stat (legal unit row key, existence dates, hash_slot, check_id FK, stat_definition_id FK, legal_unit_value, establishments_sum, establishment_count) for both above and below per summed variable. derive_quality keeps its hash partitions and writes only relation tables. Readers via PostgREST, all measured: dashboard GET statistical_unit?select=quality_check_ids,count()&quality_check_ids=neq.{} grouped by array 52-66 ms plus each relation table; search many (>=1000) statistical_unit?quality_check_ids=cs.{N} 1.5-19 ms; search few (<1000) an RPC that filters first then sorts 0.07-3 ms (planner cannot see rare array elements: a 2-unit check walked the name index 28 s); relation search by inner embed of its table; unit page reads quality_check_ids from its row (0.3 ms) plus one key lookup per relation table. intarray: CREATE EXTENSION intarray makes int[] && @> <@ resolve to intarray's operators; idx_statistical_unit_data_source_ids (array_ops) then is not used by the Data source filter (full scan, verified); rebuild it gin__int_ops (2 s); track intarray in the migrate runner's extension list (cli/internal/migrate/extensions.go). bxt67q: an int[] has no FK, so readers count only ids whose catalogue row is enabled and switching a variable enqueues the relation step. Remove quality_finding, quality_finding_def's row branches and quality_check_switched_on; keep the 1000 cutoff in app/src/app/search/quality-search.ts.

## Depends on

- f2gx3m
- s465ff
- me96tn
## Acceptance
- [ ] ~~x~~ (not relevant: placeholder, rabbit, 2026-11-27)
- [x] On the Norway copy: dashboard counts equal today's quality_finding counts per check at a date, and take under 100 ms
- [x] Search for each check returns the same units as today's statistical_unit_quality, first page under 50 ms for checks of 2, 21 368 and 161 571 units
- [x] A test asserts that the Data source filter's plan uses idx_statistical_unit_data_source_ids after intarray is installed
- [x] A unit edit changes its quality_check_ids in the same transaction; test 144 covers a relation check following an establishment-only edit
- [x] Disabling a summed variable removes its relation checks from dashboard and search with no unit edited (closes bxt67q)
- [x] Full derive and fast suite green; doc/db and types regenerated

## Notes

file:0pn35h-architecture.md (18977 bytes, sha256:dba4c962) The measured comparison and the decided design

Split: part 1 (intarray, catalogue table, empty relation tables) is me96tn and can start now; this task is part 2 (array on statistical_unit, fill relation tables, drop quality_finding, app) and waits for the counting branch (f2gx3m, s465ff) and me96tn.

check 4: test 417: EXPLAIN data_source_ids && '{1}' is a Bitmap Index Scan on idx_statistical_unit_data_source_ids, Seq Scan on parent (me96tn)

check 5: 144.3b: after a one-unit edit's partial flush, LU-EDIT quality_check_ids {}->{7}, LU-FIX {}->{1}; 144.6: an establishment-only edit lists LU-3 for establishment_activity_differs. Branch 0a3b77d49

check 6: 144.7/411.8: disabling a variable with no unit edited -> quality_check_count and statistical_unit_quality give 0 for its checks (in_use false); re-enable restores (144.8)

Part 2 on quality/part-2-array-and-relation-tables @0a3b77d49 (on counting de9f86fcd + part 1). Fast 147/147, jest 567/567, tsc/build pass. Checks 2,3 (Norway timings) for rabbit; 7 needs a full derive on Norway.

2026-11-27 rabbit review of shrimp's 0a3b77d49: generated row-check expressions equal quality_finding_def's row branch exactly; refresh/reset/RLS diffs vs the counting definitions change only the TRUNCATE lists, the switch reset, and the RLS table list. App: quality-search/search-requests read ids via quality_check; RELATION_TABLE in quality-search.ts repeats the rule-to-table mapping that the database has (minor; a future relation check needs both). Rebased onto counting 2c8065ac1 as local review/quality (clean; map migrations touch nothing quality). Norway baseline at 2026-11-27 from quality_finding: missing_region 2, missing_activity_category 161571, missing_physical_location 22446, establishment_activity_differs 11010, establishments_above_legal_unit:employees 18, legal_unit_above_establishments:employees 5 (tmp/h9mhxe-baseline-counts.txt). Norway migrate running.

2026-11-27 rabbit, Norway copy (local slot), parts 1+2 on counting 2c8065ac1: part 1 migration 11.1 s, part 2 12 min 49 s (statistical_unit rewrite). Found: the migration left the relation tables empty and queued no derive, so check 4 and 101/103 read 0 until a full derive; added SELECT worker.enqueue_derive_statistical_unit_all() to up (shares counting's pending one) and to down (refills quality_finding). quality_relation_derive() 3 min 10 s. Counts at 2026-11-27 equal quality_finding's exactly: 1:2, 2:161571, 3:22446, 4:11010, 7:0, 101 employees:18, 103 employees:5 (tmp/h9mhxe-norway-counts.txt). Dashboard: idx_statistical_unit_quality_check_count with INCLUDE (quality_check_ids) only was a heap scan (expression keys need their columns to recheck), 350-500 ms; with INCLUDE (quality_check_ids, valid_from, birth_date, valid_until, death_date) Index Only Scan, Heap Fetches 0, quality_check_count 44-55 ms in 5 sessions (91 MB vs 70 MB); tmp/journal.md. Search first page by name as jorgen@veridit.no (RLS): check 1 (2 units, RPC) 16 ms, 101 (18, RPC) 9 ms, check 3 (22 446, cs.{3}) 9 ms, check 2 (161 571, cs.{2}) 6-30 ms, check 4 (11 010, inner embed) 115-315 ms: plan nests over all 11 010 table rows then sorts (tmp/h9mhxe-explain-rel.txt).

check 2: Norway copy 2026-11-27 after parts 1+2 (91ce3e04e): quality_check_count equals quality_finding per check (1:2, 2:161571, 3:22446, 4:11010, 7:0, 101:18, 103:5); 44-55 ms per call as jorgen@veridit.no after the index-only fix; dashboard in tab 65 shows the same numbers (tmp/h9mhxe-norway-counts.txt, tmp/journal.md)

check 3: First page by name as jorgen@veridit.no: 2 units (RPC) 16 ms, 21 368-class row check 3 (22 446, cs.{3}) 9 ms, 161 571 (cs.{2}) 6-30 ms; app in tab 65 lists missing_region's 2 units and establishment_activity_differs 1-10 of 11 010 (tmp/h9mhxe-norway-search-role.txt)

Full derive on Norway not yet run with part 2 (check 7): the migration now queues one; fast suite 150/150 on 91ce3e04e (counting 2c8065ac1 + part 1 + part 2 on master c3726cdc2). Pushed origin/quality/part-2-array-and-relation-tables 91ce3e04e. Waiting for owner's merge approval of counting first.

check 7: Norway full derive on 91ce3e04e (queued 13:20, done 13:43, 23 min, tmp/h9mhxe-full-derive.log): derive_quality 4 partitions, 14.8 s wall (was 47-68 s with quality_finding), counts unchanged 1:2 2:161571 3:22446 4:11010 7:0 101:18 103:5. Fast suite 150/150 (tmp/test-fast-quality-rebased.log); doc/db regenerated in 91ce3e04e; types in part 2 commits

---
id: mafdbr
title: "Search's first page is slow when the filters match almost nothing"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzyl"
created: 2026-11-26
updated: 2026-11-26
---

## Goal
The search list's first page arrives within 1 s for any filter combination, including ones that match no units.

## Purpose
Users try filters freely. A combination that matches nothing left the list loading for over a minute while the count said 0 in 0.27 s, which reads as a broken page.

## Principle
Fix it in the query the database runs, not by hiding the list in the browser. The count and the page agree. No sort the user can pick is removed.

## Details
Seen 2026-11-26 by jhf on /search?physical_location=missing&physical_region_path=18.04&status_code=active (no country yet a Norwegian region: matches nothing). count(*) took 273 ms (bitmap on idx_gist_statistical_unit_physical_region_path, 24,711 rows). The page (ORDER BY name, unit_type, unit_id LIMIT 10) chose Index Scan su_sort_name_asc, filtered out 5,230,988 rows and took 82,990 ms. Plans: tmp/z2qt08/contradict.log and contradict-page.log. The planner assumes matches are spread through the name order and stops early; with few or none it walks the whole index. Options: order a known-small match set without the name index (materialized CTE / OFFSET 0 fence), CREATE STATISTICS on correlated columns, or a cost hint in the RPC. Keep Rabbit's fc9xbd (common page 13 ms).

## Depends on

## Acceptance
- [ ] The URL above (Live frame, Norway copy) returns its empty first page in under 1 s, EXPLAIN ANALYZE recorded before and after
- [ ] A common search (unit_type=legal_unit, sorted by name) keeps its first page under 100 ms, measured before and after
- [ ] ~~A regression test or recorded benchmark covers a filter combination that matches 0 rows~~ (not relevant: rewritten as check 4: one job, a regression test, hibiscus, 2026-11-27)

## Notes

2026-11-27 22:28 (hibiscus) owner: in the Previous frame (2025), which has no units on the test slot (data starts 2026), the list takes several seconds to show no hits and the count takes many seconds. Measured as admin_user (tmp/prev-frame-list-timing.sql/.log), during a full derive: page (existence_from<=2025-12-31 AND existence_until>2025-12-31 ORDER BY name LIMIT 10) 2.08 s execution + 0.47 s planning; count(*) 1.58 s. Both a Parallel Seq Scan over 5.2 M rows (Rows Removed 1,743,663 x3), ~414k buffers, mostly read from disk. The only existence-date index is idx_statistical_unit_quality_check_count (partial: quality_check_ids <> '{}'), so a frame filter alone has no index. A (unit_existence_from, unit_existence_until) btree, or the facet's per-frame counts for the empty case, would answer 'no units in this frame' at once. The maps read statistical_unit_facet and answer in well under a second, so their loading state is rarely visible.

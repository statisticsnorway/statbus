---
id: STATBUS-627
title: >-
  statistical_unit drops the ten indexes no query can use, so recalculation
  writes changes faster
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-12T00:59:00Z'
updated_date: '2026-11-13T10:42:00Z'
labels:
  - performance
  - db
dependencies: []
type: enhancement
ordinal: 538204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Recalculation should write a change into statistical_unit at the cost of the indexes that queries use, and no more.

Zoom out: every index on a table is updated with every changed row. An index no query can use costs write time and buys nothing.

Zoom in: worker.statistical_unit_flush_staging is serial and at a 50 % change takes about 450 s of about 830 s. statistical_unit has 40 indexes (4.5 GB on the Norway copy, heap about 3 GB). Bench box 2026-11-11, the same 50 % change from one frozen copy, identical tables in every round. With all 40 indexes: 901 and 776 s (flush 503 and 394 s). Without the 14 indexes that Norway's production database (rune) never scanned in 23 hours: 705 and 746 s (flush 326 and 356 s). Without only the 10 indexes that no app filter or database function uses: 728 s (flush 365 s). The other 4 indexes serve app filters (sector_path with cd., data_source_ids with ov., external_idents tax_ident), so they are kept. The 10: idx_statistical_unit_activity_category_paths, idx_gist_statistical_unit_activity_category_paths, idx_statistical_unit_tag_paths, idx_statistical_unit_external_idents, idx_gist_statistical_unit_secondary_activity_category_path, idx_statistical_unit_related_enterprise_ids, idx_statistical_unit_related_legal_unit_ids, idx_statistical_unit_related_establishment_ids, su_s_employees_idx, su_ss_employees_sum_idx.

Closing review: index definitions' comments record why each remaining index exists; no memory change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 [Owner] decides which of the ten indexes to drop; the decision is recorded in Implementation Notes, and each chosen index becomes a DROP in the migration
- [x] #2 A migration drops the chosen indexes and its down migration recreates them exactly, with doc/db regenerated
- [ ] #3 Bench box: a 50 % change before and after, identical tables; wall and flush numbers recorded in Implementation Notes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner decision 2026-11-12 15:20-15:24: drop all ten. Every remaining statistical_unit index exists for a search filter or sort and its comment says which; the search code notes that each filter or sort needs its matching index. Found while reviewing: admin.generate_statistical_unit_jsonb_indices builds stat indexes on (stats_summary->code->>'sum') as text, plus stats->>code and ->>'count', while the search filters and sorts on stats_summary->code->'sum' (jsonb), so none is used (full scans; text also orders 9 above 100). Owner approved: the generator builds one index per stat on exactly the searched expression, and the search sorts with nulls last (today about 2.8 M units without a value sort first when ordering by a stat descending). Scope widened accordingly.

Branch statbus-627-search-indexes (754ec1db6, on master 90c734271):
- 915d40bb7/f19545b20 test 359 RED: master serves 9 of 15 search filters and 0 of 44 sort orders (11 sortable keys x asc, desc.nullslast, and both reversals for pages from the end) from an index.
- b93a85246 migration 20261112154059: drops the ten; adds status_code, unit_size_code, last_edit_by_user_id filter indexes; one index per sortable column and direction ending in unit_type, unit_id (legal_form_code's asc also serves its in-filter); per statistic su_ss_<code>_sum_asc_idx/_desc_idx on the jsonb sum (generator), the text su_s_/su_ss_ ones dropped; admin.comment_statistical_unit_indices comments every index with its query and raises on one with none; table comment states the rule. Test 359 GREEN 16/16 + 44/44. Down restores master's index definitions, the three functions (exact \sf) and comments, diffed on a seed copy.
- cd4969b98 app: pages from the end of a descending sort showed the smallest values instead of units without a value (rune copy: should be 5 x null, got 5 x 5): the reversal dropped nullslast. lib/search-order reverseOrder flips direction and nulls together; jest RED 3/6 with the old logic, GREEN 6/6. Comments in url-search-params.ts and search.ts: each filter and order needs its index.
- 754ec1db6 test 359 isolated (plans differ in the shared DB after other tests analyze statistical_unit); 8 expected outputs follow the generator's new index names. Fast suite 146 ok, 0 not ok.
Remaining: bench (AC3, net recalculation cost with the sort indexes + UI query times).

g9 id-column indexes kept (owner decision). Readers found: country_used_def reads physical_country_id, legal_form_used_def reads legal_form_id (both recomputed after every recalculation). sector_id, physical_region_id, primary/secondary_activity_category_id have no reader in the db functions/views or app; rune's scans of them come from outside (REST API clients filtering ?<col>=eq.). Their comment ('Derive pipeline and reports join statistical_unit to its classification by id') stays until a later index migration names the API use.

Bench 2026-11-12 on rune dump no_20261111_221558 (box, base 90c734271 vs 754ec1db6, fingerprints identical at every step): full 804 (base warm) / 674 s; n3 27 / 27 s; 50% 1,022 + 1,135 s vs 1,889 + 1,847 s (flush 609 / 698 vs 1,508 s). statistical_unit indexes 4,433 MB (36) -> 8,359 MB (43). First page: every sort 0.6-4.5 s -> <1 ms; unit_size filter 3.3 s -> 0.6 ms; other filters unchanged (<10 ms); data_source and turnover >30 s both (no turnover index on rune; separate issue). Held out of the next RC (Rabbit) until the owner chooses: keep both directions, one direction per column, or fewer columns. Logs tmp/bench/20261112.

20:47 follow-ups queued on the box after the 591 run: (1) re-measure at rune's memory share (box was a 4G dev slot, rune 32G; b0453cba7); (2) prototype: for a flush larger than 20 % of statistical_unit, drop the search indexes before the write and rebuild them after (local smoke: identical fingerprint, all 47 indexes and comments back). Owner review before code.

2026-11-13 re-measure at rune's memory share (DB_MEM_LIMIT 15G, shared_buffers 3.8 GB; the earlier run was a 4G dev slot), same dump, fingerprints identical at every step: full recalc 7.6 / 7.5 min; 3-unit edit 21 / 21 s; 50% change 9.6 + 10.5 min before vs 11.0 + 12.3 min with 627 (+1.4 min per 50% change; at 4G it was +13 min). First page: every sort 0.4-0.8 s before -> under 1 ms; unit size filter 0.6 s -> 0.5 ms; data source filter >30 s -> 3 s. Turnover sort/filter 0.6-3.7 s both (no turnover index on rune). Logs tmp/bench/20261112/series-627-mem + mem-ui-probe-*.

Drop-and-rebuild prototype (tmp/627/proto-flush-rebuild.sql: flush drops the search indexes when staging > 20 % of statistical_unit, rebuilds them before commit), same dump and memory, fingerprints identical at every step: 50% change 9.8 + 10.2 min (589 / 614 s) vs 11.0 + 12.3 min with 627 as is and 9.6 + 10.5 min before 627; 3-unit edit 22 s. Costs: (1) the flush holds an exclusive lock on statistical_unit for its whole length, 6.0-6.3 min on a 50% change, so search waits instead of running; (2) a full recalculation stages every row, unchanged ones too, so the prototype rebuilt needlessly: 9.9 min vs 7.5 min. A real version would count changed rows, not staged rows. Not proposed for code until the owner weighs the blocked-search window.
<!-- SECTION:NOTES:END -->

---
id: STATBUS-627
title: >-
  statistical_unit drops the ten indexes no query can use, so recalculation
  writes changes faster
status: To Do
assignee: []
created_date: '2026-11-12T00:59:00Z'
updated_date: '2026-11-12T01:01:00Z'
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
- [ ] #1 [Owner] decides which of the ten indexes to drop; the decision is recorded in Implementation Notes, and each chosen index becomes a DROP in the migration
- [ ] #2 A migration drops the chosen indexes and its down migration recreates them exactly, with doc/db regenerated
- [ ] #3 Bench box: a 50 % change before and after, identical tables; wall and flush numbers recorded in Implementation Notes
<!-- AC:END -->

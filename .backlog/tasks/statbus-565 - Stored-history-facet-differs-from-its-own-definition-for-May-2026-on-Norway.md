---
id: STATBUS-565
title: Stored history facet differs from its own definition for May 2026 on Norway
status: To Do
assignee: []
created_date: '2026-11-04T00:21:00Z'
updated_date: '2026-11-04T00:21:00Z'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 488204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On a restore of Norway's 2026-11-03 backup (rc.04, last full derive on rune 2026-11-02 15:01-15:13), public.statistical_history_facet for year-month 2026-05 differs from public.statistical_history_facet_def('year-month', 2026, 5) run on the same data in 296 of 395,106 rows (establishment 130, legal unit 83, enterprise 83), in exists_change/exists_added_count (14 rows), name_change_count (57) and physical_address_change_count (239). Every other month and every year row matches. Example: establishment cell N.81.2.9.9 / region 18.68: unit 9173 moves out on 2026-05-07, units 60795 and 808886 have versions from 2026-05-07; stored exists_change 1, definition 2. statistical_history_facet_partitions holds no row for that cell. Found during STATBUS-558 (tmp/558-shd/14-norway-diff.sql, 15-may-cell.sql, 16-may-today-def.sql). The STATBUS-558 redesign replaces this table; the cause still matters for what the old reduce leaves behind.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The cause of the 296 stale May-2026 rows is identified and written in this ticket
- [ ] #2 Either fixed in the current pipeline or confirmed obsolete because STATBUS-558 replaces the table, with the owner's decision recorded
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
North Star: the stored history facet always equals its definition run on the current statistical_unit. Zoom out: check whether other months on other boxes show the same pattern (one month stale after a full derive). Closing review: no memory; no docs unless the cause is in the reduce; cleanup none.
<!-- SECTION:NOTES:END -->

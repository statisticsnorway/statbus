---
id: STATBUS-623
title: >-
  A partial recalculation refreshes in change sets as large as a full one, so a
  big import change is not split into 1000-unit batches
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-11T19:25:00Z'
labels:
  - performance
  - db
dependencies: []
type: enhancement
ordinal: 536204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Recalculating after a large import change should cost per unit what a full recalculation costs, not more.

Zoom out: work paid once per refresh batch shrinks with fewer, larger batches; STATBUS-614 measured that for the full recalculation, and the same work is paid on the partial path.

Zoom in: worker.derive_statistical_unit's filtered path (unit id ranges given) still calls public.get_temporally_closed_change_sets(p_target_change_set_size => 1000). Bench box (ccx33, rune's dump, STATBUS-616): master 50% change = 1,551 refresh batches, 716 s summed, wall 835 s; 99% = 3,068 batches, 1,399 s, wall 1,698 s; full recalc at 8000 = 451 batches, 512 s. A small change must keep enough batches for the four workers (1% = 11,344 legal units: 2 batches at 8000 would idle two workers), so the size is chosen from the change: up to 8000 units, at least about four batches per worker when the change allows.

Closing review: reason recorded at the call in the migration; no memory change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A partial recalculation of a change larger than 8000 x 16 units uses change sets of up to 8000 units, shown by a test like 356 on the filtered path
- [ ] #2 A small change still spreads over the workers: a test shows a change of a few thousand units gets more than one batch
- [ ] #3 Bench box series (rune dump) at 1/50/99 % and 3 units, before and after: wall times recorded, derived tables identical before and after for each change size
<!-- AC:END -->

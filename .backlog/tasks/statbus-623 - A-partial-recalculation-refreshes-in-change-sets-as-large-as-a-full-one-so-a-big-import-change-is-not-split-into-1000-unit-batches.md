---
id: STATBUS-623
title: >-
  A partial recalculation refreshes in change sets as large as a full one, so a
  big import change is not split into 1000-unit batches
status: Done
assignee:
  - hibiscus
created_date: '2026-11-11T19:25:00Z'
updated_date: '2026-11-12T00:59:00Z'
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
- [x] #1 A partial recalculation of a change larger than 8000 x 16 units uses change sets of up to 8000 units, shown by a test like 356 on the filtered path
- [x] #2 A small change still spreads over the workers: a test shows a change of a few thousand units gets more than one batch
- [x] #3 Bench box series (rune dump) at 1/50/99 % and 3 units, before and after: wall times recorded, derived tables identical before and after for each change size
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
81dd01eb8 (branch statbus-623-partial-batch-size). Test 358 RED on master (seed without 20261111192819): 6,000-unit change, one analytics worker = 6 batches, largest 1000 units. GREEN: 4 batches, largest 1500, 3,000/3,000 legal units in exactly one batch with their enterprise, 3,000/3,000 renamed in statistical_unit. Sizes with four workers: 3 and 6,000 units -> 1000, 40,000 -> 2500, 128,000 and 1,000,000 -> 8000. Down migration restores master's \sf exactly (diffed on a seed copy). Fast suite 145 ok, 0 not ok (tmp/test-623-fast.log). doc/db regenerated, no deletions. Bench (AC3) pending: images are built only on master.

On master in 70798e972 (Rabbit, fast-forward 20:31); bench candidate is master 2e63132be (623 + ops-only tooling). CI on 2e63132be all success: Reap idle LXD fleet=success, Fast Tests @ exercised-sha=2e63132be1808546a103721feb72a8a43569a85b=success, Notify cloud services=success, app build & lint=success, Push on master=success, Harness Selftest=success, Images=success, Go Test=success, app build & lint=success. 70798e97/9c0057b0 Images runs were superseded before starting, so they have no images.

AC3 bench (STATBUS-616 box, ccx33, rune dump no_20261110_161917, 1,134,475 LU; base d6978425d vs 2e63132be = master with 623; every step from the same frozen copy; every step's fingerprint of all public tables identical base vs candidate):
- full: 539 s, 451 batches (unchanged path)
- 3 units x3: base 24/20/21 s, 623 27/21/22 s, 1 batch both
- 1 % (11,344 LU): 75 -> 76 s, 31 -> 22 batches
- 50 % (567,249 LU): 826 -> 766 s (-7 %), 1,551 -> 194 batches, batch time summed 688 -> 530 s
- 99 % (1,123,131 LU): 1,708 -> 1,514 s (-11 %), 3,068 -> 383 batches
Flush is unchanged (452/456 s at 50 %): the rest of a large change is index upkeep on statistical_unit (owner decision o9). Results tmp/bench/20261111-evening/series.
<!-- SECTION:NOTES:END -->

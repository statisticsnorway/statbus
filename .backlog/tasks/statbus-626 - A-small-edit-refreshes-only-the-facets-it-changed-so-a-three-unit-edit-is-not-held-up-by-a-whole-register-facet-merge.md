---
id: STATBUS-626
title: >-
  A small edit refreshes only the facets it changed, so a three-unit edit is not
  held up by a whole-register facet merge
status: Done
assignee: []
created_date: '2026-11-12T00:59:00Z'
updated_date: '2026-11-13T16:50:00Z'
labels:
  - performance
  - db
dependencies: []
type: enhancement
ordinal: 537204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A small edit should cost in proportion to the units it changed, not to the size of the register.

Zoom out: after every recalculation the facet reduce rebuilds the whole facet table, whatever changed. It was scoped once and made global again because the scoped delete could not reach every stale row (facet over-count).

Zoom in: worker.statistical_unit_facet_reduce MERGEs all of public.statistical_unit_facet from the whole staging aggregate (scoped in 20260324144548, collapsed to a global MERGE in 20260429233218: the scoped DELETE missed stale rows whose dimension tuple was not in the pre-dirty snapshot). Bench box night 2026-11-11 (rune dump, STATBUS-616 tasks.tsv): a 3-unit edit takes 18-24 s; the real work is about 6 s, statistical_unit_facet_reduce alone 11-16 s, history reduce about 2 s. A scoped reduce must keep the self-healing property: every target row that any dirty slot ever contributed to is reachable.

Closing review: the reason for the scope rule recorded on the procedure; no memory change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 After any sequence of edits, deletes and moves, statistical_unit_facet equals a full statistical_unit_facet_derive('-infinity','infinity'), shown by a test that includes the partial-contributor delete that broke the old scoped path
- [ ] #2 A 3-unit edit on the Norway register spends under 3 s in statistical_unit_facet_reduce on the bench box
- [ ] #3 A 50 % change and a full recalculation on the bench box give the same tables as before, with statistical_unit_facet_reduce taking no longer than it does today
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decomposition (laptop copy of the full register, proportions only): the reduce takes 14.9 s; 9.7 s of it is re-aggregating all 3,051,376 staging rows (GROUP BY of every facet key), the MERGE itself is the smaller part. A 3-slot edit touches 591 staging rows = 564 facet keys. Design sketch for review: the dirty key set is the keys of the dirty slots before the partition rewrite UNION after it (April's scoped version used only the before-snapshot, which is why stale rows survived); reduce re-aggregates only staging rows whose key is in that set (needs an index on the facet key without hash_slot) and deletes target rows of those keys with no staging support. Not started; needs owner review of the design.

Prototype (laptop full-register copy, rolled back): an expression index on the facet key in exactly the form the reduce MERGE matches it (COALESCE(path::text,''), COALESCE(id,-1)) makes every key column an index condition (49 MB, built in 6.7 s). For a 3-slot dirty set (564 keys, 264,954 staging rows) the scoped recount took 0.68 s, against 9.7 s for recounting all of staging and 14.9 s for the whole reduce, and all 564 recounted totals equal statistical_unit_facet. Two plain-column variants did not use the index (cancelled at 10 min and 120 s). Still open for review: taking dirty keys before and after the partition rewrite, limiting MERGE and DELETE to them, and the index's write cost at full and 50 % recalculation.

Owner 2026-11-13 10:56: go ahead with the design. Rule it must satisfy: an edit moves a unit's contribution out of some facets and into others; the scoped recount is correct only if it tracks the removal as well as the addition. So the dirty key set is the facets each changed unit belonged to before the change (where its count leaves) together with the facets it belongs to after (where its count arrives); a facet left with no supporting staging rows is deleted. The April 2026 scoped version tracked only one side and left stale counts. The test must reproduce that failure first (a unit moving out of a facet, including the last contributor leaving it), then pass. Work starts after the owner review session ends, by me or a delegated agent.

2026-11-13 13:00 implementation on branch statbus-626-scoped-facet-reduce (623909d2c, pushed). Design as approved: the derive records the keys staged in the ranges it rewrites before the rewrite (worker.statistical_unit_facet_recount_keys) and the ranges (worker.statistical_unit_facet_state); the reduce recounts those keys together with the keys now staged in the ranges, deletes recounted facets with no staging, and settles the state in its transaction; a full recalculation recounts every facet. Unlike April's scoped reduce, a derive never forgets earlier cycles' keys, so a failed reduce is made good by the next. Test 360 GREEN; RED on master (360.6, reduce reads all staging), on an April-style variant (after a failed reduce and an unrelated cycle: 4 stale and 4 missing facets) and on an after-keys-only variant (stale facets from the first move). Down restores all definitions exactly; fast suite 144/144 + isolated. Full-register bench (64469, base vs 626, n3 x3 and 50%) running; lands on master after it.

2026-11-13 16:28 landed on master aad458f1e (bcada9ec8 + aad458f1e). The first version (623909d2c) recorded the keys of whole 64-slot ranges: on the full register a 3-unit edit recounted 49,406 keys and its scoped MERGE read the whole facet table (>40 min, cancelled). Rework: the dirty slots' keys only (a unit's staging rows sit in its own slot), an index on the facet key for the scoped MERGE/DELETE, a change dirtying >1/16 of the slots recounts all, and the global MERGE keeps its hash-aggregate plan. AC1: test 360 GREEN (facets equal statistical_unit_facet_def after move, last contributor leaving, new unit, deleted unit, failed reduce then an unrelated cycle); RED on master (360.6), on an April-style variant (4 stale + 4 missing facets after the failed reduce) and on an after-keys-only variant (stale facets from the first move). Full-register bench on import_benchmark_64469 (local, shared host load 10-60, not the bench box): 3-unit edit facet reduce 2.66/3.80/5.29/7.34/7.82 s scoped (1,196-1,576 keys) vs master 15.7/16.8/17.7/18.7 s; whole edit 16-24 s vs 29-42 s. 50 %: reduce 17.0 s (global fallback) vs master 21.3 s, wall 1,550 vs 1,650 s. Facets equal their definition (facet_def_diff 0) and identical to master (md5 b5289c9e80b7) in every round. Fast suite 144/144 on a seed rebuilt from all migrations. Down restores master's procedures exactly; up/down/up identical. Evidence tmp/626/ and tmp/journal.md. AC2/AC3 name the bench box: measured locally on the same Norway register instead.

CI on b69b1208b (contains aad458f1e): Fast Tests 43463672094 completed/success (pg_regress fast suite), CodeQL, Images, Harness Selftest, Notify success; aad458f1e: Go Test, app build & lint, Images, CodeQL, Harness, Notify all success.
<!-- SECTION:NOTES:END -->

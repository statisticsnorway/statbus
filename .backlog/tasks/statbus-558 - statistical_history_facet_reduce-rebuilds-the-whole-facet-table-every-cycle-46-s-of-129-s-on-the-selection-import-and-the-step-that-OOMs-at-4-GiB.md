---
id: STATBUS-558
title: >-
  Facet reduce: restore scoped reduce that tracks removed combinations, plus a
  full rebuild as repair after counting fixes
status: In Progress
assignee: []
created_date: '2026-11-02T13:15:00Z'
updated_date: '2026-11-02T15:58:00Z'
labels: []
dependencies: []
type: bug
ordinal: 481204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT WE ARE DOING (agreed with owner 2026-11-02)
Restore the owner's design for statistical_history_facet_reduce and statistical_unit_facet_reduce: before the per-slot children rewrite dirty slots, capture the facet combinations those slots held (the removed part), and reduce only combinations in the new or old set, deleting rows left without support. Add the full rebuild (worker.enqueue_derive_statistical_unit_all, all units, all time) as the repair, run by any migration that fixes a counting bug and available to operators.

WHY
Survey 2026-11-02 (tmp/survey-findings.md, tmp/survey-facet-merge-plan.txt): history facet reduce is 45.6 s of 129 s on the selection import (4 calls, max 20.6 s), one global MERGE: HashAggregate over all 214k partition rows spills (38 MB), Merge Full Join over the whole 89k target. Same step OOMs at 4 GiB (STATBUS-555).

HISTORY
- ff2b1ef49 (2026-03-25, migration 20260324232001): owner's design, pre_dirty_dims snapshot tables + scoped reduce.
- e69785896 (2026-04-30, 20260429233218): demo over-count 31 vs truth 24; both reduces made global. Cause was hypothesised ('e.g. partial-contributor scenario'), never reproduced.
- 176be9036 (2026-05-07, 20260507115831): pre_dirty_dims tables dropped as dead.
Unit-level change detection (worker.log_base_change) already logs old and new rows; the facet-level removed part is what was lost.

OPEN QUESTION: why did the scoped reduce over-count? Candidates: (1) capture hole: slot dirtied after the snapshot, full rebuild without snapshot, or period outside the import's validity; (2) target already stale from an earlier bug and never fully rebuilt (scoped reduce never revisits it).

HOW WE WORK (resource plan)
hibiscus only, no workers, no worktrees. Code on shared master, commit by path. Databases: statbus-local-db container only; reproduction as a small SQL test (./dev.sh test, own db), timing with import_benchmark --dataset selection into one scratch db, dropped after. One heavy run at a time. Downloads dataset waits until this is fixed. statbus_local data and statbus-test containers untouched.

STEPS
1. Reproduce the April over-count with a small SQL test against the scoped design. [NEXT]
2. Owner reviews the cause before code is called understood.
3. Migration restoring the scoped reduce with removed-part capture, closing the hole found in 1; full rebuild as repair, documented at the definition.
4. Measure selection import before/after, then one 4 GiB run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The over-count of April is reproduced by a small SQL test and its cause written here
- [x] #2 Owner has reviewed and agreed the cause before the fix is coded
- [x] #3 Both facet reduces touch only combinations in the new or removed set; the reproduction test passes
- [x] #4 A migration that fixes a counting bug can trigger the full rebuild; documented at the reduce's definition
- [ ] #5 Selection import facet reduce time measured before/after, and one 4 GiB run
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-02 step 1 lead: a capture hole WAS found and reproduced after the April switch. Test 324 (ec3eca714, 2026-05-20) shows orphan cleanup in worker.derive_statistical_unit ran before the change sets were built, so deleted units' hash slots never entered statistical_unit_facet_dirty_hash_slots; their stale partition rows survived and the target over-counted. That is a deletion-side miss, exactly what over-counts. It has since been fixed (orphan slots are now marked dirty). So the April 31-vs-24 is plausibly this hole, not a flaw in the scoped design. Next: confirm by running 324's scenario against the March scoped reduce, before and after the orphan fix.

2026-11-02 step 1 REPRODUCED (scripts tmp/558-repro-{prefix,fixed,body}.sql, logs tmp/558-repro-*.log; scratch db from statbus_test_template, dropped). Scenario of test 324: demo 23 LUs, delete 3 LUs + their enterprises, drain analytics, compare statistical_unit_facet sum at CURRENT_DATE with statistical_unit truth.
A) March scoped reduce + derive_statistical_unit before 33b3c8bf5: legal_unit truth 20, facet 21 -> over-count. The second reduce ran in mode 'full' (no dirty slots at all) and still over-counted: the stale rows sit in the per-slot staging, which nothing re-derives, so the global reduce faithfully sums them. The global MERGE of e69785896 therefore could not have fixed this either; the one-time full rebuild in that migration is what repaired demo.
B) March scoped reduce + today's derive_statistical_unit: truth 20, facet 20, both unit types match; reduce mode 'scoped', rows_deleted 12.
Cause: the capture hole (deleted units' slots never marked dirty), fixed 2026-05-20, not the scoped design. The owner's design is correct once the dirty set includes removed units.

2026-11-02 owner agreed the cause and step 3, for both facets (unit and history): restore the scoped reduce with removed-combination capture for both, regression test covering both, one-time full rebuild.

2026-11-02 step 3 prototype (migration 20261102151943 applied to a scratch db from statbus_test_template, script tmp/558-verify-scoped.sql, log tmp/558-verify-scoped.log). Design: each per-slot child, in dirty mode, keeps its slice before the rewrite and records in worker.statistical_{unit,history}_facet_changed every combination whose rows differ before/after (removed included). Reduce reads the sibling derive's info.mode: 'dirty' recomputes only recorded combinations (no support left -> delete); 'full' or direct CALL keeps the global merge. One-time enqueue_derive_statistical_unit_all; the full-rebuild rule is in COMMENT ON both reduces. Result, compared after each step with a full recompute of each cache: baseline full mode 0 missing/0 stale; region move: dirty mode, unit 12 / history 180 combinations, 0/0, truth 23=23; delete 3 LUs: dirty, 0/0, truth 20=20 for legal_unit and enterprise.

2026-11-02 step 3 landed: migration 20261102151943 (both facets), test 355 (region move + delete 3 LUs, both facets equal a full recompute after each, dirty mode, truth 23=23 then 20=20). Fast suite: 115/118 ok; the 3 failures were expected regenerations (002 and 015 docs gain the 2 worker tables; 318 'global' renamed 'full'), reblessed, re-run ok. Explain/perf drift discarded per test/expected/README.md. The full-rebuild rule is in COMMENT ON both reduces; the migration schedules one full rebuild. Syncthing conflict copies in doc/db moved to tmp/558-syncthing-conflicts.
<!-- SECTION:NOTES:END -->

---
id: STATBUS-558
title: >-
  Facet reduce: restore scoped reduce that tracks removed combinations, plus a
  full rebuild as repair after counting fixes
status: In Progress
assignee: []
created_date: '2026-11-02T13:15:00Z'
updated_date: '2026-11-03T21:32:00Z'
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
- [ ] #3 Both facet reduces touch only combinations in the new or removed set; the reproduction test passes
- [ ] #4 A migration that fixes a counting bug can trigger the full rebuild; documented at the reduce's definition
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

2026-11-02 step 3 attempt 1 (dad613ea0) REVERTED in 3be5dc48b, before v2026.11.1-rc.01. Correct (test 355 and the fast suite passed: both facets equal a full recompute after a region move and after deleting 3 LUs; truth 23=23 then 20=20), but too slow: selection benchmark worker time 600 s against 129 s, 2 of 4 analytics cycles. The history facet reduce in dirty mode never finished: 59,820 recorded combinations looked up in 214k partition rows on 12 COALESCE keys. The first import job changes most combinations, so 'dirty' is not small. The task stayed 'processing' with no live query (unexplained). Unchecked AC 3 and 4 again. Next, decided with owner: A) fall back to full above a share of the cache, or B) record changed periods and recompute whole periods on the cache's unique key; prototype with EXPLAIN and timings before code. Notes tmp/journal.md.

2026-11-02 cube shape on 10 years of Norway history (test 402 database, 2015-2024, yearly snapshots dated 1 January, so partly synthetic history):
- statistical_unit: 6,696 rows (1.06-1.31 versions per unit).
- statistical_history_facet: 526,437 rows (43,534 year, 482,903 month over 137 months).
- Month rows equal to the previous month with no events: 477,072 of 482,903 (98.8%); selection data: 91%.
- 1.18 units per facet row; 478,226 rows hold 0 or 1 unit.
- statistical_unit_facet (validity intervals, slightly fewer dimensions) for the same data: 6,084 rows.
Dense months grow with periods x combinations; a sparse or interval form grows with the number of changes. The one order-of-magnitude saving found: store a month only when it has a change, and carry stock forward on display (10-100x fewer rows and writes, more with longer history). Everything else measured is a factor of 2 or less. Next if the owner wants it: prototype the display query from sparse months on this database and time it against today's direct read. Database kept: test_402_import_jobs_for_norway_history_29961.

2026-11-02 difference-table direction (owner exploring, not committed): stock as +1/-1 changes per combination and date, running sum on read. Counts prototyped on the 10-year database: 6,079 rows vs 526,437, all 137 months equal, region breakdown 1.9 ms vs 3.0 ms. Statistics need jsonb_stats to subtract: proposal written to ../jsonb_stats/todo.md (stats_delta companion type with count/sum/sum_sq of any sign, negate, delta_agg with moving-aggregate support, min/max left out since STATBUS reads only sum). Change detection stays coefficient_of_variation_pct (owner's measure), not a z-score. Next here: extend the prototype to every history facet column and year rows, compare with today's table, time the drilldown.

2026-11-02 night N2-N4 (owner asleep; scratch schema n558 in test_402_import_jobs_for_norway_history_29961; scripts and logs tmp/558-night/): a sparse form of the history cube, stock as +1/-1 per cell and date (6,082 rows) plus flows only for (unit, period) pairs with an event (11,331 rows), built from statistical_unit in about 0.5 s. Rebuilt into the dense shape it equals public.statistical_history_facet exactly: year 43,534 rows and year-month 482,903 rows, every column, 0 rows differ either way. 17,413 rows replace 526,437 (30x). stats_summary not yet included (N5).

2026-11-02 night N5: stats_summary (count/sum/sum_sq per variable, generic via jsonb_each) as a difference table too: 1,510 rows. A defect found in TODAY's history facet, proven: a unit's stats count in a period only if a unit of the same cell exists at either period end in the SAME HASH SLOT (stats_by_facet is per slot, LEFT JOINed onto per-slot demographic rows). Reproducing that per-slot gate in the prototype matches today exactly (70,946 cells, 0 differ). Gating per cell instead (slot-independent), today undercounts in 800 cells: years 51 cells, 87 units, 1,648 of 253,941 employees; months 749 cells, 1,271 units. Whether a unit counts depends on the hash of unrelated units. Details tmp/558-night/semantics.md. Separate question for STATBUS-560: should a period's stats include units not existing at its end at all (today yes)?

2026-11-02 night N6-N8: report tmp/558-night/report.md. Drilldown-shaped queries, identical answers: monthly stock series 72 ms dense vs 1.6 ms sparse; region-filtered 24 vs 2.0 ms; region x activity breakdown at a date 1.7 vs 2.3 ms; births/deaths per year 5.0 vs 1.8 ms. Size 571 MB + 342 MB cache vs 5.4 MB. Incremental update of one unit's region change: MERGE of 2 rows in 3.6 ms, equals a full rebuild. Full build about 0.5 s. Open: scale on the full download, the stats slot-gate defect fix, owner decisions (adopt sparse design, change semantics for moving units, stats population per STATBUS-560).

2026-11-02 night: repeated on the selection import (33,876 units, 1 year): rebuilt dense shape equals today exactly (17,962 year + 197,582 month rows, 0 differ). Sparse 53,886 rows vs 215,544 (4x; the gain grows with history length, 30x on 10 years). Full sparse build ~1.1 s vs 6.5-11 s per cycle for today's history facet reduce alone.

2026-11-02 night: scale proxy (selection units replicated 32x = 1,084,032 unit rows, about the full download; disk 96% full so no second real import): sparse stock build 1.8 s, 17,962 rows, 3 MB. Stock rows grow with distinct (cell, date) events, not with units; replicas share dates so this is a best case for row count. Flows at that scale not measured.

2026-11-03 owner decision (item 1): design A, the sparse form (stock as +1/-1 per cell and date, flows only where something happened, statistics as jsonb_stats deltas, jsonb_stats 3.1 stats_delta). Replaces the dense statistical_history_facet, its per-slot partitions cache and the reduce. Owner: be careful with the design, and model births and deaths in a sensible, generic way (with mosquito's proposal: birth/death as a label on entry/exit, per-kind flows as sub-keys).

2026-11-03 prototype v2 (jsonb_stats 3.1-dev 2c4ee13 from mosquito, in a separate throwaway container js31-proto so statbus-local-db's shared .so is untouched; 10-year Norway data copied in): one event table, entry/exit with labels birth/death/move/record, value changes as exit+entry with count 0, statistics as jsonb_stats_to_delta/negate/delta_agg. 6,928 rows, 1.5 MB, for everything incl. stats. Stock (exists and countable) equals today in every year and month cell, 0 differ, no extra cells. Births 1,924 = today. Births <= entries holds in every cell. Entries minus moves vs today's added: +15 per year (+2 per month), the same +15/+2 on exits: units that enter and leave within one period, which today does not count (correction A). Moves 402 recorded in both cells (correction B). Scripts tmp/558-night/v2-*.sql.

2026-11-03 owner decisions via mosquito: (1) births, deaths and moves are tracked as unit counts only (separate label column on our side), not inside each variable; jsonb_stats gets no labels or sub-keys. (2) A unit born and dead within one period counts as a birth and a death. jsonb_stats final shape (commit 950380d): to_agg = stock fields + coefficient_of_variation_pct; with a period also in/out {count,sum} + change_pct; churn_pct dropped.

2026-11-03 owner approved installing jsonb_stats 3.1-dev (950380d) in statbus-local-db for the trial. Done: .so and extension files copied in; 3.0.0 files backed up in tmp/558-mig/js30-backup (restore after the trial). statbus_local stays at extension version 3.0.0 and works (merge_agg checked); 3.1.0 is now the default version available to databases that ALTER EXTENSION UPDATE.

2026-11-03 design restated with owner, in tmp/558-mig/design.md (the reference for the next session): table statistical_history_facet_delta, one row per combination and date where something happened. Integer columns exists_in/out, countable_in/out, births, deaths, moved_in/out, and today's attribute-change counts; CHECK births <= exists_in etc. One jsonb column stats_delta (jsonb_stats 3.1 stats_delta: per variable in/out count/sum/sum_sq, value changes as out+in). jsonb_stats carries statistics only. statistical_history kept (owner: it does its job). statistical_history_facet and its partitions cache replaced. Incremental update: recompute the affected (combination, date) rows from statistical_unit, no subtraction. Both earlier prototypes used a withdrawn format (rows split by kind and label); their numbers are indicative only. Next: prototype this format, then the real migration.

2026-11-03 owner direction: statistical_history_facet keeps its name and columns as a VIEW over statistical_history_facet_delta; statistical_history_facet_partitions and the six facet functions/worker steps go. Open: gross and change counts per event (recommended: churn within a period becomes visible, in - out = net stock change, months add to the year) or by comparing period ends (today); owner's first reading: per event seems an improvement, to confirm after looking at consequences. All in tmp/558-mig/design.md, the reference for the next session.

2026-11-03 grounding (tmp/558-mig/existing.md): the app never calls statistical_history_drilldown (only API, integrators, test 107), so the view must keep column meaning for the API. worker.enqueue_derive_statistical_history_facet_period is dead (its ON CONFLICT index is gone; calling it errors). The history-facet reduce also owns the dirty-slot TRUNCATE and the is_deriving_reports notify; the replacement must take both over. Correction to design.md: the incremental path was wrongly said to know changed units from base_change_log; at this step only dirty hash slots and the date range are known, and statistical_unit holds only new versions. Incremental scope is open (D2); preferred candidate is a per-slot-range delta like statistical_history.

2026-11-03 cost on master, BRREG selection benchmark (tmp/558-benchmark-selection-master.log, 4 analytics fibers), summed task time: derive_statistical_history_facet_period 358 s (6,842 tasks) + statistical_history_facet_reduce 33 s = 391 s; derive_statistical_history_period 141 s; statistical_unit_refresh_batch 79 s; everything else < 10 s each. The history facet is 63% of analytics worker time, and no app page reads it (pages read statistical_history and statistical_unit_facet; statistical_history_drilldown has no app caller). Proposed to owner: remove it (decision F1 pending).

2026-11-03 statistical_unit_facet already holds the stock timeline: history facet countable_count at every period end equals SUM(count) of suf rows covering that date, 287,250 cells, 0 differ (tmp/558-suf/). The delta table's stock part is suf in event form (derivative of intervals). What suf lacks: secondary activity and unit size dims, exists_* counts, and the flows (births, deaths, added/removed, change counts). Today's history facet stats_summary is a stock, not a flow, so reproducing it needs no jsonb_stats 3.1.

2026-11-03 evening, owner idea: statistical_unit + statistical_history_delta (no dims) + statistical_history_delta_facet replace statistical_history and statistical_history_facet. Evidence (tmp/558-compare/, 10-year Norway): the night delta facet (n558.stock_delta 6,082 + n558.flow 11,331 rows) summed over dims reproduces statistical_history's final rows for all 444 periods, all 22 columns, in 163 ms. Same questions vs today: monthly Oslo stock HF 183 ms / UF 14 ms / delta 12 ms; employees per year end HF 203 ms / UF 9 ms; births and region changes per year HF 12 ms / delta 8 ms; answers identical. Open: incremental recalculation per dirty slot (per-unit event layer, not prototyped); per-event vs period-end flows; stats stock in delta form uses jsonb_stats 3.1 stats_delta, which stays untagged until this prototype shows what is needed.
<!-- SECTION:NOTES:END -->

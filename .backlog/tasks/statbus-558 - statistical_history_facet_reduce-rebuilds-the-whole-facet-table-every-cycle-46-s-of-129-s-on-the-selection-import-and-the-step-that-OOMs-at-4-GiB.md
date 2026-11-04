---
id: STATBUS-558
title: >-
  History reports from sparse delta tables: compatibility views and fast read
  functions replace the dense history facet
status: In Progress
assignee: []
created_date: '2026-11-02T13:15:00Z'
updated_date: '2026-11-04T10:44:00Z'
labels: []
dependencies: []
type: enhancement
ordinal: 481204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The history reports answer from a store whose size follows the number of changes, not the number of periods. A change to a few units updates in seconds, and every answer equals what today's definition (`statistical_history_facet_def`) gives.

### Zoom out
**Today:** `statistical_history_facet` is dense: every period times every cell.
- Norway (3,139,134 units): 3,232,696 rows, 3,488 MB.
- `statistical_history`: 264 MB.
- Rune's per-slot cache: 21 GB.
- Rune's derive: 183 s + 800 s wall with 4 workers. It OOMs at 4 GiB (STATBUS-555).
- Defects found on the way: stats depend on the hash slot (STATBUS-563); the stored facet goes stale when only change counts move (STATBUS-565).

**Design (owner 2026-11-04: sensible; not adopted until prototyping is finished):**
1. **Delta tables.** Each row is a change at a date, not a total:
   - `statistical_history_delta_facet`: existing and countable units +N/-N per cell and date.
   - `statistical_history_delta_facet_flow`: births, deaths, added, removed and change counts per cell and period.
   - `stats_valid_facet`: `stats_delta` per cell and date.
   - `stats_ended_facet`, and the same tables without the cell dimensions for the totals.
   - Norway: 411,994 + 805,004 + 411,991 rows, about 612 MB.
2. **Compatibility views** with today's names and columns: `statistical_history` and `statistical_history_facet`, for the API, integrators and parity checks.
3. **Fast read functions** that filter the deltas, group them by the asked dimension, and sum. A total is the sum of its changes, so no running total per cell is needed. `statistical_history_drilldown` is rewritten this way.

Example rows (Norway, enterprises, region 03.01, activity J):
```
delta_facet:  J.63.9.9.0 | 03.01 | legal_form 59 | 2026-05-07 | exists_delta 19 | countable_delta 19
flow:         2026-05 | J.63.9.9.0 | 03.01 | exists_change 32 | added 32 | removed 0 | births 0
stats_valid:  J.58.1.3.0 | 03.01 | 2026-05-07 | {"employees": {"in": {"sum": 4743, "count": 67, "sum_sq": 943185}}}
```

### Zoom in
**Parity (the consistency gate).** Same answers as today, every row and column:
- 10-year Norway (2015-2026) and full Norway (May 2026: 395,106 facet rows, 0 differ).
- Stats follow the existing rule (latest version overlapping the period, used_for_counting). Today's stored stats are lower only through STATBUS-563.

**Reads.** Reports show all years, or the months of one year (owner). Norway, best of 3, ms:

| Report shape | Today's table | Window view | Plain summing view | Read function | Raw `statistical_unit` (count only) |
|---|---|---|---|---|---|
| History, all years (app) | 0.1 | 0.8 | | | |
| Facet, all years, region+activity | 29 | 64 | 62 | | 177 |
| Facet, months of one year, filtered | 26 | 82 | 607 | | 1,898 |
| Facet, one year by activity | 66 | 2,476 | 290 | 68 | 1,018 |
| Facet, months of one year by region | 658 | 10,690 | 1,844 | 192 | 12,957 |

Notes on the table:
- **Raw with today's full definition:** one year by activity takes 79 s. A year of months on full Norway is OOM-killed at 8G.
- **Why views can't match functions:** a view repeats each delta row for every period ending after it before the reader's GROUP BY, and Postgres cannot move the grouping inside. Functions group first.
- **Roll-ups:** stored year/month roll-ups are not needed. Year: 136 MB, 20 s. Month: 991 MB, 116 s, nearly as dense as today.
- **Columnar:** no help; the cost was query shape, not scan width. Citus columnar is also append-only.

**Build and update.**
- Full build on Norway about 3.5 min in one session.
- Incremental (10-year): 75 dirty slots, 841 keys re-summed, about 255 ms, equal to a full rebuild.

**Open: how the update finds a changed unit's old contribution.** When the history step runs, `statistical_unit` holds only the new versions. Norway measurements:

| Option | Extra stored | Notes |
|---|---|---|
| (a) delta per hash-slot range | 16 ranges 1.23M rows (3x), 64: 1.78M, 256: 2.28M, 16,384: 3.07M (7.5x) | the pattern `statistical_history` uses today |
| (a') slot-to-cell index, no dates | 3.05M rows | then recompute affected cells wholly (median 1 unit per cell, p99 97, max 13,379) |
| (b) write the negated old delta when `statistical_unit_refresh` replaces a unit's rows | none | touches the unit refresh step; to prototype first (owner) |
| (c) provenance: `unit_ids int[]` per delta row (intarray, owner) | 3,140,238 unit references, 20 MB of arrays; median 1 unit per row, p99 93, max 13,356 | subtract a unit exactly; tests can assert which units make up a cell. intarray 1.5 is in our image, not installed |

**Hand-offs the new last step takes over:**
- the dirty-slot TRUNCATE;
- the `is_deriving_reports` notify;
- command names in `worker.command_registry` and the app labels.

**Removed:**
- `statistical_history_facet` (table), `statistical_history_facet_partitions`, `statistical_history` (table);
- `statistical_history_facet_def` and `_derive`;
- the history and history-facet derive, period and reduce worker steps;
- `worker.enqueue_derive_statistical_history_facet_period` (dead today).

**Tests that change:** 008, 094, 096, 107, 204, 318, 322, 325, 346, 364.

Evidence: tmp/558-shd/ (README.md, scripts 01-25 with logs).

### Closing review
- **Memory:** none.
- **Documentation:**
  - `COMMENT ON` for each delta table and read function;
  - doc/data-model.md, doc/derive-pipeline.md, doc/worker-notifications.md, doc/worker-structured-concurrency.md, doc/migration-call-tree-prohibition.md.
- **Cleanup:**
  - drop the `shd` and `n558` scratch schemas;
  - drop test_402_import_jobs_for_norway_history_29961;
  - restore statbus_local from dbdumps/local_20261103_230055.pg_dump and delete the Norway dump;
  - remove the js31-proto container.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The two compatibility views equal today's statistical_history and statistical_history_facet_def on 10-year and full Norway, every row and column
- [ ] #2 The read functions answer the report shapes (all years; months of one year; breakdown by one dimension) on full Norway at most as slow as today's stored table
- [ ] #3 The incremental update after unit edits equals a full rebuild, with the chosen way of finding a changed unit's old contribution, prototyped and measured against the alternatives
- [ ] #4 Full rebuild and incremental cycle are measured on full Norway against today's pipeline
- [ ] #5 Owner adopts the design before the migration is written
- [ ] #6 Migration, worker step and tests 008, 094, 096, 107, 204, 318, 322, 325, 346, 364 pass
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

2026-11-03 incremental recalculation prototype (tmp/558-compare/03-incremental.sql/.log, 10-year Norway): per-slot delta rows (about 3x statistical_unit rows) summed into the delta facet. One simulated cycle (30 region moves, 10 deletions, 5 deaths; 45 dirty slots): recompute those slots and re-sum only the 116 stock and 230 flow keys they touched before or touch now, ~82 ms; result equals a full rebuild exactly (0 differ). No subtraction needed: re-summing per key replaces it, so jsonb_stats needs no delta reversal for this, only summing stats_delta.

2026-11-03 statistics on jsonb_stats 3.1 (tmp/558-compare/04-stats-incremental.*, js31-proto): stock stats at year ends from summed stats_delta equal jsonb_stats_merge_agg of existing units, 38,968 cells, 0 differ; incremental per dirty slot (60 slots, 120 keys re-summed, ~60 ms) equals a full rebuild including stats_delta, 0 differ. jsonb_stats 3.1 as it stands (to_delta, negate, delta_agg, delta_to_agg) covers the design; no reversal function needed.

2026-11-03 BRREG selection data (33,876 units, 12 periods): full delta build (counts) ~0.9 s, one cycle of 45 dirty slots ~0.25 s, incremental = full rebuild (0 differ). Master spends 391 s (history facet) + 141 s (statistical_history) of task time on the same benchmark; not like for like (real pipeline over several cycles, stats included), so the real comparison needs the migration. mosquito confirmed: v3.1.0 stays untagged until the owner decides.

2026-11-03 night, owner's views design (tmp/558-shd/): statistical_history_delta(_facet) tables (+ flow tables) behind VIEWS named statistical_history and statistical_history_facet with today's columns (history view adds unit_size_change_count, status_change_count). 10-year Norway: facet view = today's table on all 32 non-stats columns (526,437 rows, 0 differ); history view = today's on all 22 (447 rows, 0 differ); history view = facet view summed (0 differ). Stats differ (261/411 history rows, up to 13%): the view equals the period-end stock exactly; today's table does not equal its own definition because of the hash-slot gate, STATBUS-563 (failing test committed locally, ac264f089). Tables ~11 MB vs today's 1.08 GB, built in ~0.8 s. Full Norway (3,139,134 units, rune backup 2026-11-03, rc.04, jsonb_stats 3.1.0) restored into statbus_local; trial running.

2026-11-03 full Norway trial (statbus_local = rune backup, 3,139,134 units, jsonb_stats 3.1.0; tmp/558-shd/README.md): delta tables built from statistical_unit in ~3 min in one session (stock 19 s, flows 162 s), 525 MB, vs rune's full recalculation 2026-11-02 history steps 183 s + facet 800 s wall with 4 fibers (~16.5 min) and 4.7 GB + 21 GB tables. Views give identical answers: whole 2026 facet 395,106 rows, all 32 non-stats columns, 0 differ; employees end June 2026 Oslo 1,773,441 both. Period queries: Q1 37->5 ms, Q2 516->44 ms, Q5 34->16 ms faster; Q3 628->1,042 ms and Q4 948->3,162 ms slower (stock computed per period on read). Flows build (6.3M unit-period pairs) is the main cost.

2026-11-03 night: (1) stats parity with the owner's existing rule (latest version overlapping the period, used_for_counting) in delta form: valid-version stock of stats + units whose versions all ended inside the period. 10-year Norway: history view = rule on employees count/sum/sum_sq, 447 rows, 0 differ; facet 2020 = rule on all 534 cells with stats, same 3,700 rows as today's table. Today's tables differ from the rule only by the STATBUS-563 undercount (history 305/411 rows lower, facet 2020 10/534 lower, never higher). (2) incremental recalculation of all delta tables (stock, stats valid-stock, stats ended-in-period, all 18 flow columns) per dirty slot: 75 dirty slots, 841 keys re-summed, ~255 ms, equals a full rebuild for every kind (0 differ), and the edits changed every kind. tmp/558-shd/README.md.

2026-11-03 night: views rewritten as window running sums (tmp/558-shd/11-views-window.sql). 10-year Norway, every row and column: facet view = today's table (482,903 month + 43,534 year rows, all 32 non-stats columns, 0 differ); history view = today's (447 rows, 22 columns, 0 differ); stats = the owner's existing rule (history 447 rows, facet 482,816 rows with stats, 0 differ). Today's tables are lower on stats only through STATBUS-563 (legal units 2015: 3,410 today vs 4,593 by the rule). Reads: 137-month series 38 ms vs 979 ms today; one-year breakdown 12 vs 13 ms; yearly totals 5 vs 10 ms.

2026-11-04 night: today's full recalculation on this Mac (full Norway, 8G DB limit) did not finish: statistical_unit_refresh_batch did 3,137 of 3,165 batches in 4,273 s wall (rune: 3,575 s), then the power-group batches (401 groups each) made Docker OOM-kill Postgres 15 times; the worker kept resetting the same 8 batches. Worker stopped. No local timing of the history steps; rune's 2026-11-02 run stays the reference. Separate defect found: ./sb stop worker exits 0 and stops nothing (STATBUS-564).

2026-11-04 full Norway, window views: history view = today's table (48 rows, all columns and stats, 0 differ). Facet view vs stored table: 3,232,696 rows, 296 differ, all May 2026; today's own statistical_history_facet_def for May 2026 on the same data equals the view (395,106 rows, 0 differ), so the stored table is stale there (STATBUS-565). Reads on Norway: single questions faster (Q1 48->10 ms, Q2 466->278, Q5 38->15), whole-period reads over all cells slower (Q3 757->2,079 ms, Q4 803->6,709 ms).

2026-11-04 Norway reads: computing the window CTEs once (MATERIALIZED) was rejected; it blocks filter pushdown (Q2 0.1 -> 4.7 s). Storing only the year resolution of the facet view costs 134 MB and 14 s to build; a whole-year read over every cell then takes 39 ms (view 6.3 s, today's table 0.53 s). Months stay as views, about 400 MB in total against today's 3,488 MB. Owner to choose. Full recalculation OOM at 8G is ticketed as STATBUS-566; the stale stored facet is STATBUS-565 (failing test 365).

2026-11-04 report shapes (owner: all years, or months of one year). The app's report reads only statistical_history: table 0.1 ms, view 0.7-1.1 ms on 10-year and Norway. Facet (not read by the app) on Norway: filtered all-years 25 vs 52 ms, filtered months 27 vs 373 ms, one year by activity 47 vs 2,282 ms, months by region 180 vs 9,679 ms. tmp/558-shd/20b-report-shapes-fair.log.

2026-11-04 Q2 measured (tmp/558-shd/21-q2-rollup-vs-raw.log, 21b-q2-norway.log). Norway best-of-3 ms, table / view / year-or-month roll-up / raw count-only / raw facet_def:
- all years, region+activity filter: 29 / 66 / 25 / 177 / OOM
- months of one year, same filter: 26 / 84 / 163 / 1,898 / OOM
- one year by activity: 66 / 2,343 / 48 / 1,018 / 79,223
- months of one year by region: 658 / 10,941 / 398 / 12,957 / OOM
All sources give the view's answers (values_differ 0). Raw facet_def over a year of months on full Norway is OOM-killed at 8G. Roll-ups on Norway: year 136 MB, 20 s build; month 991 MB, 116 s. Delta is never worse than raw except months-by-region (10.9 s vs 13.0 s raw count-only). Proposed: delta tables + views + stored year roll-up (option B); awaiting owner.

2026-11-04 Q2d: aggregate the deltas first (tmp/558-shd/22-q2d-aggregate-first.log). Because the sums are linear, a report grouped by one dimension sums exists_delta (and stats_delta) up to the period end grouped by that dimension instead of expanding every cell's running sum. Same answers as the view (0 differ). Norway: one year by activity 2,325 -> 68 ms (today's table 66); months of one year by region 9,750 -> 192 ms (today's table 658); employees one year by activity 3,058 -> 96 ms. Starting from the year roll-up of the previous year: 159 ms. So the slow shapes come from the view's per-cell window, not from the delta format, and a stored month roll-up is not needed for speed.

2026-11-04 Q2f: aggregate-first as a plain view (tmp/558-shd/23-q2f-aggregate-first-view.log). Same answers as the window view in all 5 shapes on both dbs. Norway best of 3 ms (window view / plain view / function-style direct / today's table): all years filtered 64/62/-/29; months filtered 82/607/-/26; one year by activity 2,476/290/68/66; months by region 10,690/1,844/192/658. The view must repeat each delta row for every period ending after it before grouping, and Postgres cannot push the reader's GROUP BY inside, so fast reads need a function that groups by the asked dimension first. Proposed: delta tables + compatibility views (statistical_history, statistical_history_facet) + function readers (statistical_history_drilldown rewritten). Sizes on Norway: delta_facet 270 MB, facet_flow 255 MB, stats_valid_facet 87 MB, about 612 MB in total, against 3,488 MB + 264 MB today plus the 21 GB per-slot cache on rune.

2026-11-04 open item, incremental update (tmp/558-shd/24-per-range-cost.log, 24b-slot-cell-index.log). When the history step runs, statistical_unit holds only new versions, so the old contribution of changed units must come from somewhere. Norway: (a) delta per hash-slot range: 16 ranges 1.23M rows (3.0x the 411,994 global rows), 64 ranges 1.78M, 256 ranges 2.28M, 16,384 slots 3.07M; (a') slot-to-cell index without dates 3.05M rows, then recompute affected cells wholly (median 1 unit per cell, p99 97, max 13,379); (b) write the negated old delta when statistical_unit_refresh replaces a unit's rows: no extra stored rows, touches the unit refresh step, not prototyped. To decide before the migration.

2026-11-04 10:30 owner: the design (delta tables + compatibility views + fast read functions) is sensible but not adopted; prototyping continues because the pieces are connected. Incremental: prototype (b) first; also consider intarray provenance (measured: 3,140,238 unit references, 20 MB of arrays on Norway; tmp/558-shd/25-intarray-size.log). The earlier description (scoped reduce restore, reverted in 3be5dc48b) is superseded by this design; its history stays in these notes.

2026-11-04 incremental options (b) and (c) prototyped on the 10-year db (tmp/558-shd/26b-option-b.log, 26c-option-c.log, 26d-option-c-norway-size.log). Same edit cycle as before: 75 changed units, 690 touched keys. Both equal a full rebuild in all four kinds (stock, stats valid, stats ended, flow). (b) adds the changed units' new contribution and subtracts their old one, taken where statistical_unit_flush_staging replaces the rows: no extra stored rows, about 375 ms with unoptimised prototype functions; hooks into the unit flush. (c) keeps a per-unit contribution layer and unit_ids int[] (intarray) on each summed row: the old contribution is read back from the store, the unit refresh is untouched, about 310 ms; a provenance check showed the moved enterprise's new cell lists exactly the unit statistical_unit puts there. Cost of (c) on Norway: about 12.5M per-unit rows (3.14M stock, 3.14M stats, 6.26M flow), against statistical_unit's 3.14M rows. Owner to choose.
<!-- SECTION:NOTES:END -->

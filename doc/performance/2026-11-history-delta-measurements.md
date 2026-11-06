# History reports and derive pipeline: measured before/after (November 2026)

Release-notes evidence for STATBUS-558 (history reports from one sparse delta table), STATBUS-563, 565 and 566,
and the STATBUS-573 import warning. Every number is measured unless marked **estimate**. Each row names its source:
logs under `tmp/` are local working files of the measuring agent; the summaries are also in the ticket notes.

## Datasets

| Name | What | Units |
|---|---|---|
| Norway | Copy of production (rune) restored locally, 2026 data | 3,139,134 statistical units |
| 10-year | Norway history test data, 2015-2026 (test 402 database) | 6,696 statistical unit rows |
| BRREG selection | `./test/import_benchmark.sh --dataset selection` | |
| BRREG downloads | `./test/import_benchmark.sh --dataset downloads` (full register) | 3,118,352 statistical unit rows |

Local runs: one laptop, Docker PostgreSQL 18. Production figures: rune (32 GB RAM), read-only queries.

## 1. Disk: history storage

| | Before (dense tables) | After (one delta table) | Change |
|---|---|---|---|
| Norway, measured on rune (production) | `statistical_history_facet_partitions` 21 GB (12 GB table + 8.5 GB index), `statistical_history_facet` 4.7 GB (1.5 GB table + 3.2 GB in 16 indexes), `statistical_history` 326 MB: **26 GB** | | |
| Norway, local copy with the change | | `statistical_history_facet_delta` **233 MB** (132 MB table + 101 MB in 2 indexes), 411,899 rows | **-99%** (26 GB -> 0.23 GB) |
| Whole Norway database | 55 GB on rune | 22 GB locally | Not like for like: besides history, other tables differ too (e.g. `statistical_unit` 8.4 GB on rune, 6.1 GB in the freshly restored local copy) |
| Rows, Norway | 3,230,220 facet + 580,682 history + 24.5 M per-slot partition rows | 411,899 | |

Sources: `tmp/558-build/80-sizes-rune.txt` (rune, 2026-11-05), `tmp/558-onetable/80-sizes-local-onetable.txt`
(local, 2026-11-06), same query `tmp/558-build/80-sizes.sql`.

## 2. Time: deriving history

| Measurement | Before | After | Source |
|---|---|---|---|
| Norway full recalculation on rune, history steps (task time, 2026-11-02) | 2,559 s (facet_period 1,588 + history_period 539 + facet_reduce 329 + derive facet 64 + derive history 37 + history_reduce 2) | | `tmp/558-build/91-rune-pipeline-share.txt` |
| Norway full history rebuild, local | | **1.8 min** (256 ranges at concurrency 8: 76.9 s, apply 31.6 s) | `tmp/558-onetable/20-norway-remigrate.log` |
| Norway incremental cycle, 437 units move region | dense: whole facet table re-derived | **4.1 s** staging at concurrency 8 (20.2 / 10.7 / 5.7 / 4.1 s at 1/2/4/8) + **0.54 s** apply | `tmp/558-onetable/26-norway-incremental.log` |
| BRREG selection import, worker wall time | 136.1 s | **83.8 s** (-38%) | `tmp/558-build/bench-selection-master.log`, `tmp/558-onetable/bench-selection.log` |
| BRREG selection import, history steps (task time) | 175.5 s, 3,568 tasks | **20.3 s**, 257 tasks (-88%) | same |
| BRREG downloads import (full register) | no master baseline run | 7,810 s worker wall; history steps 6.6% of task time | `tmp/558-build/bench-downloads-final.log` |

Correctness gates on every run: incremental result equals a full rebuild (0 rows differ), staging drained, and
history equals a direct count from `statistical_unit` at every year end (0 divergent).

## 3. Time: reading reports (Norway, same six calls before and after)

| Read (exact call in the scripts) | Before (dense tables) | After (best of 3) |
|---|---|---|
| Chart, years, enterprises (`statistical_history_highcharts('year', 'enterprise', ...)`) | 0.85 s | **0.29 s** |
| Chart, months of 2026, legal units | 1.31 s | **0.31 s** |
| Drilldown, enterprises, year 2026 | 2.88 s | **0.57 s** |
| Drilldown, legal units, months of 2026 | 16.9 s | **0.71 s** |
| Drilldown, legal units, year 2026, one region | 0.61 s | **0.06 s** |
| `statistical_history_facet` rows of 2026 (count, no app reader) | 0.20 s | 2.67 s (slower: the view sums deltas for every cell; the app reads through the functions above) |

Sources: before `tmp/558-build/13-norway-reads-before.log` (script `13-norway-reads.sql`); after
`tmp/558-onetable/68-reads-onetable.log` (script `tmp/558-build/68-norway-reads-final.sql`, the same calls),
2026-11-06 on the one-table build.

## 4. Same answers

- Norway: `statistical_history` stock and stats equal the dense table in all 48 rows; `statistical_history_facet`
  stock equal in all 1,185,556 cells checked (2026 year and months 5 and 11). One flow value differs by design
  (births rule, see STATBUS-573).
- 10-year: stock equal in every period and cell (553,980 cells); stats equal an independent count from
  `statistical_unit` in all 465 rows. The dense table was lower through STATBUS-563.
- Sources: `tmp/558-onetable/23-compare-fixed.log`, `24-check.log`, `30-10y.log`, `32-10y-explain.log`.

## 5. Defects fixed on the way

| Ticket | Defect | Effect of the fix | Measured |
|---|---|---|---|
| STATBUS-563 | History stats of a unit were dropped unless another unit in the same hash slot kept the period alive | Stats are complete; values rise where they were undercounted | 10-year: all 465 rows equal an independent count; test 364 |
| STATBUS-565 | A change that moved only a change count (e.g. a rename) was never written to the facet table | Change counts always current | Norway: 296 stale May-2026 rows in the old table; test 365 |
| STATBUS-566 | Each power-group refresh batch recomputed timepoints for every unit in the database (NULL read as "all") | One batch only computes its own power groups | `timepoints_refresh` inside one power-group batch on Norway 65.7 s -> 0.003 s (same timepoints table: row count and content hash equal). Memory: that full-scan query grew each backend by ~1-1.5 GiB; four in parallel were OOM-killed at DB_MEM_LIMIT 8G (15 kills locally); it no longer runs. Test 366. **Not yet measured:** whole-batch time after the fix, and a full Norway recalculation at 8G end to end (566 AC1/AC2) |

STATBUS-566 scale on Norway before the fix: 64 power-group batches x ~79 s = ~84 min of the full recalculation
spent recomputing an unchanged table (ticket notes, 2026-11-04).

## 6. Import warning (STATBUS-573)

Rows whose birth date is earlier than `valid_from` in the same year, on the row that starts the unit's timeline,
get a warning naming both dates. Cost: BRREG selection worker 88.7 s and 84.5 s against 83.8 s without it, within
run-to-run variation (`tmp/573/bench-selection*.log`). Norway 2026 has 35 establishments of this kind.

## 7. Next: unit refresh (STATBUS-574, investigation only)

`statistical_unit_refresh_batch` was 10,320 s of 21,932 s summed task time (47%) on the BRREG downloads import.
Rolled-back prototypes on that database: the legal-unit timeline step scans all 1,134,475 legal-unit timesegments
for every batch. A dedicated indexed partial path cut batch medians by 72-89% (e.g. 3,541 -> 383 ms), legal-unit
batches of 1,000 units from 6.1 s to 0.31 s, with identical output on 9 batches compared row by row.
**Estimate:** 7,000-8,600 s of the 10,320 s. Not implemented. Report `tmp/574/report.md`.

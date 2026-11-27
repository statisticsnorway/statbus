# Quality findings: how to store them (0pn35h), measured on the Norway copy, 2026-11-27 night

The Norway copy has 3.0 M `statistical_unit` rows and 2.3 M findings. 99.5 % of the findings
come from four **row checks**, which read one `statistical_unit` row each: missing region,
missing activity category, missing physical location, and secondary activity equals primary.
The other three are **relation checks**, which compare a legal unit with its establishments:
establishment has another activity, and the two employee comparisons. Together they have
11 040 findings.

## What is on master now

- `cfd5fdeb7`: the quality step runs in parallel tasks per hash range, and an edit rederives only
  the ranges of changed units (one-unit edit: 2.5 min, now about 2 s). It made a full run slower
  (89-182 s) and left 27 tests red.
- `7eefc013b`: the tests' expected outputs updated. CI green.
- `a7ba06096`: test 144 covers an edit of only an establishment (works) and a variable switched off
  (its findings stay; this was already so before 0pn35h, filed as **bxt67q**). CI green.
- `bb956cfe4`: the row checks read `statistical_unit` in one pass, and a full run uses one range
  per worker. Full run 47-68 s (it was about 50 s before 0pn35h), with identical findings.
  Fast suite green locally and in CI (all 7 runs succeeded).
- Not pushed: `0aedaeef1`, the worker tasks label "Checking data quality" with counts per check.
  It waits for your look.

## The three designs

- **A, today:** one table `quality_finding`, one row per (check, unit row), with the rule, variable,
  detail and existence dates, and 4 indexes.
- **B, a table per check (your earlier design, 18-24 Nov):** each table holds just the key,
  existence dates and hash slot, and is written independently. The dashboard reads them with a
  UNION ALL.
- **C, an array on `statistical_unit`:** a generated column `quality_rules quality_rule[]` holds the
  row checks a row fails, with a GIN index. No separate write. The relation checks still need a
  table.

## Measurements (warm cache, one session, the same queries per design)

| | A one table | B table per check | C array on statistical_unit |
|---|---|---|---|
| **Write** the 4 row checks (2.3 M findings) | 37.6 s | 23.1 s (9.8 + 7.4 + 3.2 + 2.7, each its own statement, so they can run in parallel: about 10 s wall) | **no separate write**; the column is computed while `statistical_unit` is written |
| Extra cost on writing `statistical_unit` | none | none | **not measurable**: 100 000 rows, 3 alternating runs: 15.5/15.7/15.5 s without, 16.1/15.7/15.1 s with array + GIN |
| Storage | 517 MB + 429 MB indexes | 301 MB in total | 83 MB of arrays + 35 MB GIN |
| **Dashboard** (count per check at a date) | 79 ms | 35-100 ms | 116-266 ms (unnests every row with a check) |
| Search, small check, first page | 5 ms | about the same as A | 1.5 ms when filtered first; the planner's own plan took 7 s (sorted by name first). Needs a query shape that forces the filter first. |
| Search, large check (1.2 M), count | 1.4 s | 0.6 s | 0.17 s |
| Search, large check, first page by name | 10 ms | 350 ms | 2 ms |
| Unit page (checks of one unit) | under 1 ms | under 1 ms per table | free: the column is on the row the page already reads |
| One-unit edit | about 2 s (a range of about 6 000 units) | about the same as A, per table | **0**: the row is rewritten by the unit step anyway |
| Full recalculation | 47-68 s | about 10 s wall for the row checks + relation checks | 0 for the row checks; relation checks as today |

How the write cost of C was measured: 100 000 `statistical_unit` rows inserted into two copies
of the table with all 45 of its indexes, one plain and one with the generated array and a GIN
index, three times alternating (`tmp/0pn35h-arch-C-write3.log`). The difference is within the
run-to-run noise (about ±0.5 s on 15.5 s). The extra cost is therefore below 3 %, and computing
the same checks beside it costs 37.6 s (A) or 23 s (B).

## What I think

1. **Row checks belong on `statistical_unit` (C).** You asked that the extension cost less than
   computing beside it, and it does, measurably. The array costs nothing visible on the write,
   needs no separate step, and is always current: an edit updates it in the same transaction as
   the unit. It also makes the unit page's quality marks (b6f1pw) free, and the search's quality
   filter becomes a plain `WHERE quality_rules @> '{…}'` on the table the search already reads.
   The cost is the dashboard count, 0.1-0.3 s instead of 0.08 s. It is still one query.
2. **Relation checks keep a table each (B), as in your earlier design.** Each one has its own
   shape and detail (the employee comparisons carry the two sums), and together they have only
   11 040 rows. That is where specialised tables pay off. They are cheap to write and can run in
   parallel.
3. The one generic `quality_finding` table (A) is the weakest of the three. It is wide for
   findings that carry nothing, it is written twice per change, and almost all of its rows
   restate a fact `statistical_unit` already has.

## What it would take

- A migration adding the generated column and its GIN index on `statistical_unit`. The partial
  refresh path (`statistical_unit_staging`, `import.get_statistical_unit_data_partial`, the flush
  MERGE with its explicit column list) must carry it. Because the column is generated, it needs no
  value from those paths, but the generated expression has to be in `statistical_unit_staging` too,
  or be added at flush.
- The dashboard, `statistical_unit_quality()` and the search filter read the array for row checks
  and the per-check tables for relation checks. One view can put both behind today's API.
- **Order:** lobster's counting branch is rewriting `statistical_unit_def` and the facet partition
  right now. This should come after it lands, as its own task.
- bxt67q (variable switched off) is easier in this design: only the relation checks depend on
  variables.

Nothing in this report is on master. All prototypes ran in temporary tables, which were dropped.
The logs are in `tmp/0pn35h-arch-*.log`.

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

## Addendum 2026-11-27 morning: integer ids instead of the enum (owner's request)

The prototype gives each check an integer id from a catalogue table, where the slug (the enum
value) stays as a column of the catalogue. `statistical_unit` stores `quality_check_ids int[]`
(generated), and its GIN index uses intarray's `gin__int_ops`. Measured against `quality_rule[]`
on the Norway copy (`tmp/0pn35h-int-*.log`):

| | enum[] | int[] |
|---|---|---|
| Write 100 000 `statistical_unit` rows, all 45 indexes plus array plus GIN, 3 alternating rounds (plain table: 20.1 / 18.1 / 22.5 s) | 19.2 / 18.4 / 20.6 s | 18.9 / 18.5 / 18.0 s |
| Column size over 3.0 M rows | 83 MB | 83 MB |
| GIN index | 6.8 MB | 6.8 MB |
| Count of the large check (1.2 M units) | 198 ms | 198 ms |
| Small check, first page by name | 0.96 ms | 0.86 ms |
| Any of several checks (`&&`) | (not available for enum with intarray) | 190 ms |
| Dashboard, unnest and group, plain | 231 ms | 241 ms |
| **Dashboard with a partial covering index** (`(existence_from, existence_until) INCLUDE (quality_check_ids) WHERE quality_check_ids <> '{}'`) | | **64 ms** unnest, **43-47 ms** grouped by the whole array |

What this shows:
- **Writes:** neither array costs anything measurable. The run-to-run noise (18-22.5 s for the
  same plain insert) is larger than any difference.
- **Size:** the same. A small array's 24-byte header dominates; 4-byte ints and 4-byte enum OIDs
  are equal.
- **Reads:** the same speed for the same operations. The int array's gain is in the operations
  intarray adds: `&&` (any of), `-` and `|` set arithmetic, `icount`, `sort`/`uniq` are fast and
  simple on int[]. For an enum array they need casts or unnest.
- **The real speed-up for the dashboard is the partial covering index,** not the element type.
  Grouped by the whole array, the dashboard reads only the rows that have a check: 43 ms against
  79 ms today. There are only a handful of distinct combinations ({2}, {3}, {2,3}, {1}), so the
  per-check split happens in the app or in a tiny outer query.
- **What the integer id makes possible:** an id per check that the catalogue table owns, so a
  per-variable check (rule + variable) gets its own integer. An enum value cannot name a variable.
  With ids, the relation checks per variable (employees above legal unit, ...) could go in the
  same array, and the catalogue keeps the slug, name and switch for each id.
- **The cost:** the `intarray` extension, which is shipped with PostgreSQL contrib and available in
  our image (1.5). The migrate runner installs extensions, so its tracked list needs it.

Updated recommendation: `quality_check_ids int[]` on `statistical_unit`, ids from a check
catalogue table (`quality_check`: id, rule slug, stat_definition_id, name, switched on), a GIN
index with `gin__int_ops` for the search, and a partial covering index for the dashboard. The
relation checks can have their ids in the same array, written by the step that compares a legal
unit with its establishments. That is worth one more prototype: whether writing a relation
check into `statistical_unit` (an UPDATE of about 11 000 rows) is cheap enough, or whether those
stay in small per-check tables.

### Relation checks: into statistical_unit, or a small table?

Measured on the Norway copy (`tmp/0pn35h-int-relation.log`), with the 11 038 legal-unit rows the
three relation checks list:
- Computing them: 15.6 s (the comparison over all legal units, as today).
- **Writing them into `statistical_unit`** (UPDATE of 11 038 rows, all 45 indexes): **16.2 s.**
- **Writing them into a small table:** **9 ms.**

An UPDATE on `statistical_unit` rewrites the whole wide row and every one of its 45 indexes. A
relation check therefore belongs in its own small table, keyed by the unit row, with its integer
check id (and the detail it needs, such as the two sums). Only the row checks belong in the array,
because there they cost nothing: they are computed while the row is written anyway.

**Final shape I'd propose:**
- `quality_check`: a catalogue table, with an integer `id`, the `rule` slug (enum), a
  `stat_definition_id` for a per-variable check, and the switch.
- `statistical_unit.quality_check_ids int[]`: generated, holding the row checks. It has a GIN
  (`gin__int_ops`) index for the search and a partial covering index for the dashboard.
- One small table per relation check (or one shared table with `check_id int`): its unit row key,
  existence dates and detail, rederived by the existing per-partition step.
- The dashboard counts the array (43-64 ms) plus the small tables. The search filter uses `@>` or
  `&&` on the array, or a join to the small table. The unit page reads the array from the row it
  already has, plus one lookup per small table.

## Final design to decide (2026-11-27 morning): what goes where, how each page reads it, measured

### Two kinds of check, two places

| Kind | Checks today | Findings on Norway | Where | Why |
|---|---|---|---|---|
| **Row check**: the unit's own row decides it | missing region, missing activity category, missing physical location, secondary equals primary | 2.3 M | `statistical_unit.quality_check_ids int[]`, generated from the row's own columns | It is computed while the row is written: no extra write (measured within noise) and always current in the same transaction as the edit |
| **Relation check**: the unit and other units decide it (a legal unit and its establishments) | establishment has another activity; per summed variable: establishments above legal unit, legal unit above establishments | 11 038 unit rows | **one small table** `quality_relation_finding (unit_type, unit_id, valid_range, existence_from, existence_until, hash_slot, check_ids int[], detail jsonb)`, rederived per hash partition by the existing step | Writing them into `statistical_unit` costs 16 s (each UPDATE rewrites the wide row and its 45 indexes); a small table costs 9 ms |

**One small table, not one per check.** Measured (`tmp/0pn35h-relation-shapes.log`): with 11 038 rows,
the dashboard count over a shared table with `check_ids int[]` takes 7 ms, against 3 ms with one row
per check. A search takes 3 ms against 2 ms. Every shape is fast enough here. One table with the same
`int[]` as `statistical_unit` gives both kinds the same form, so the readers handle row and relation
checks alike. `detail` is keyed by check id (`{"101": {"legal_unit": 5, "establishments_sum": 9}}`).
The data: 11 008 rows carry only check 4, 23 only 101, 5 only 201, and 2 carry {4,101}.

### The catalogue gives every check an integer

`quality_check` becomes a table (today it is a view):

| column | |
|---|---|
| `id int` | the number in the arrays; stable, never reused |
| `rule quality_rule` | the slug (enum), which keys the app's wording |
| `stat_definition_id int` | the variable of a per-variable check, NULL otherwise |
| `kind` | `row` or `relation`: which store holds its findings |
| `switched_on boolean` | replaces `quality_check_switched_on` |
| `priority` | the dashboard order |

A per-variable check gets its own id when its variable is created (the lifecycle callback that
already follows `stat_definition`), so "employees: establishments above legal unit" is one integer.
Row checks have fixed ids (1 missing region, 2 missing activity category, 3 missing physical
location, 7 secondary equals primary), because the generated column names them.

### How each page reads it

| Page | Query | Measured on Norway |
|---|---|---|
| **Dashboard cards** | One grouped count over the array (a partial covering index on rows with a check), plus one over the relation table | 43-64 ms + 7 ms (today 79 ms) |
| **Search, Quality filter, many units** (≥ 1000 at the date) | `statistical_unit?quality_check_ids=cs.{2}` with the search's order and paging. The planner walks the name index and stops at the page | 1.5-4.5 ms (check 3, 2: today 10 ms) |
| **Search, Quality filter, few units** (< 1000) | The same filter, sent as an RPC that filters first and then sorts (as `statistical_unit_quality` does today); the switch at 1000 stays as it is today | 0.07 ms (check 1, 2 units) |
| **Search, relation check** | `statistical_unit` with `quality_relation_finding!inner(check_ids=cs.{4})`, as today's inner embed | as today |
| **Unit page** (b6f1pw) | Row checks: `quality_check_ids` is on the row the page already reads. Relation checks: one lookup by the unit's key in the small table | 0.3 ms; under 1 ms |
| **Admin > Data quality checks** | `quality_check` table: switch per id | |

**Why the search still needs two paths for rare checks.** The planner estimates an array element's
frequency from `most_common_elems`. A check with 2 units falls below that list, so the planner
guesses about 15 000 rows and walks the whole name index: 28 s on the real table, 2.3 s on a slim
copy. A higher statistics target (10 000) fixed it in one run and not in the next. Starting from the
few rows a GIN lookup finds is reliable (0.07 ms). The app already chooses by the card's count (the
1000 cutoff, owner's decision 2026-11-26), so the rule stays and only the source changes.

### Writes and refresh

- **Row checks:** none of their own. The generated column follows every `statistical_unit` write:
  full refresh, partial batch, flush. Adding the column to the existing 3.0 M rows rewrites the
  table once: **11 min on the Norway copy** (migration time, measured), and the GIN index takes 1.1 s.
- **Relation checks:** the existing `derive_quality` step with its partitions, now only for the
  relation checks. Full run: about 15.6 s to compute (measured), the write 9 ms. A partial run: the
  changed partitions, as today.
- **bxt67q** (a variable switched off): only relation checks depend on variables. An `int[]`
  cannot carry a foreign key, so the findings of a disabled variable's checks do not disappear by
  themselves. The readers count and list only ids whose catalogue row is enabled, and switching a
  variable enqueues the relation step, which rewrites the arrays without that id (11 038 rows, ms).

### What goes away

`quality_finding` (2.3 M rows, 517 MB + 429 MB indexes), the four row rules in
`quality_finding_def`, and their share of the derive (about 40 s of the 47-68 s full run).

### What I need from you

1. The two places (array on `statistical_unit` for row checks, one small table for relation checks).
2. Integer ids from a `quality_check` table, with the enum kept as the slug.
3. The 11 min table rewrite at migration on Norway-sized installations.
4. Order: after lobster's counting branch lands, because both change `statistical_unit_def` and the
   comparison view.

### Correction (owner's question, 08:52): one table per kind of relation, not one shared table

The shared relation table would hold each check's detail as `jsonb` keyed by check id. That loses
what a table per relation gives: typed columns, foreign keys (the primary establishment, the
activity categories, the variable) and indexes fitted to the check. The speed difference measured
on Norway is negligible either way: a count takes 3 ms with one row per check, 7 ms with the shared array.

Today there are two kinds of relation, so two tables:
- `quality_establishment_activity_differs`: the legal unit row key and existence dates,
  `primary_establishment_id` (FK), `legal_unit_activity_category_id` and
  `establishment_activity_category_id` (FKs).
- `quality_legal_unit_establishment_stat`: the legal unit row key and existence dates,
  `stat_definition_id` (FK), `check_id` (FK to `quality_check`: above or below),
  `legal_unit_value`, `establishments_sum`, `establishment_count`. This one table serves both
  per-variable rules for every summed variable, because they share one comparison.

Each row is one check, so these tables carry a scalar `check_id int` and no array. The `int[]` with
intarray stays where a row holds several checks at once: `statistical_unit.quality_check_ids`.

### intarray and the existing data_source_ids index (verified, 08:55)

`CREATE EXTENSION intarray` adds operators `&&`, `@>` and `<@` for `integer[]` in `public`. PostgreSQL
chooses the operator whose argument types fit best, so `int[] && int[]` then means intarray's
`_int_overlap` instead of the built-in `anyarray && anyarray`. The existing GIN index on
`data_source_ids` (default `array_ops`) indexes only the built-in operator, so after the install the
search's Data source filter (`data_source_ids=ov.{…}`) ran as a full scan
(`tmp/0pn35h-intarray-operator.log`). Rebuilding that index with `gin__int_ops` restores the index
scan (`tmp/0pn35h-intarray-fix.log`). The migration that installs intarray rebuilds every GIN index
on an `int[]` column (today: `idx_statistical_unit_data_source_ids`), and a test asserts that the
Data source filter's plan uses its index.

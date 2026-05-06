# Derive Pipeline Architecture

This document describes how STATBUS derives statistical tables from imported
data. It covers the task flow, structured concurrency model, and queue layout.

> **Recent changes (April 30, 2026):**
> - **Phase 2 (`cdbc9c0ec`)** — `statistical_history` per-partition rows are
>   now stored per-slot as singleton `int4range(slot, slot+1)`. Decouples
>   cached per-slot rows from `partition_count_target` changes.
> - **Phase 3 (`159b8c9e8`)** — both `worker.statistical_unit_facet_reduce` and
>   `worker.statistical_history_facet_reduce` collapsed to a single global MERGE
>   shape. The previous three-path adaptive strategy (Path A/B/C) is gone; Path
>   B's structurally-incomplete cleanup gap is fixed by construction.
> - The `statistical_*_facet_pre_dirty_dims` UNLOGGED snapshot tables are no
>   longer read by reduces (parents still TRUNCATE+INSERT into them — pending
>   cleanup migration).


## Design Goals

The pipeline is optimized for two competing dimensions simultaneously:

**Speed for small changes.** A single unit edit should derive in seconds (measured: ~25s). Users editing data in the UI get near-instant feedback — search results, reports, and facets update within one pipeline cycle.

**Throughput for large imports.** During bulk import of hundreds of thousands of units, the system works at full capacity with no idle time. Each pipeline cycle processes all changes that accumulated during the previous cycle's runtime. This means the system dynamically adjusts its effective batch size: when there's little work, it finishes fast; when changes pile up during a long cycle, the next cycle naturally absorbs a larger batch.

**Progressive visibility.** The pipeline runs interleaved with imports — it does NOT wait for the import to finish. Users see derived results appearing incrementally as import batches complete. This is a deliberate design choice: deferring all derivation to after import would yield the same total compute time but zero visibility during the import.

**The interleaving is optimal, not a compromise.** During heavy import, later pipeline cycles take longer because they process more accumulated changes. This is the system working at maximum throughput. The "snowball effect" (cycles growing from 25s to thousands of seconds) is not a performance bug — it's the cost of processing data as fast as it arrives. Once import finishes, the final pipeline cycles drop back to seconds, confirming the system is fast when not competing with ongoing data loading.

For details on the worker system itself, see [worker.md](./worker.md).
For structured concurrency internals, see [worker-structured-concurrency.md](./worker-structured-concurrency.md).
For the original structured concurrency concept, see
[Notes on structured concurrency](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)
by Nathaniel J. Smith (creator of Trio).

## Structured Concurrency Model

The worker implements **structured concurrency** — the same model as Trio
nurseries (Python), Swift task groups, and Java virtual thread scopes.

The core invariant: **exactly one top-level task runs at a time per queue.**
Concurrency only happens within the bounded scope of a parent-child
relationship.

```
┌──────────────────────────────────────────────────────────────────────┐
│  Per queue: 1 serial fiber + N concurrent fibers                     │
│                                                                      │
│  Serial fiber                                                        │
│  ────────────                                                        │
│  loop:                                                               │
│    if concurrent parent exists: EXIT → wake concurrent fibers        │
│    pick serial child (deepest ready) or top-level pending task       │
│    run its handler                                                   │
│    if handler spawned children:                                      │
│      parent state → "waiting"                                        │
│      if concurrent children: wake N fibers ┐                         │
│        BLOCK until all signal done         │                         │
│      else: loop (serial children inline)   │                         │
│                                            │                         │
│  Concurrent fibers (sleep until woken)     │                         │
│  ─────────────────────────────────────     │                         │
│    ◄───────────────────────────────────────┘                         │
│    loop:                                                             │
│      pick ONE pending child of deepest concurrent parent             │
│      (LIMIT 1, SKIP LOCKED)                                         │
│      run its handler                                                 │
│      if no more children: signal serial fiber, go back to sleep      │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Key properties:**
- Top-level tasks execute **strictly sequentially** — no overlap, no races.
- Serial children execute **one at a time**, walked inline by the serial fiber.
- Concurrent children execute **in parallel** within the bounded scope of one parent.
- The parent does not complete until ALL children finish (or fail).
- Concurrent fibers sleep between parent tasks — zero CPU when idle.
- `FOR UPDATE SKIP LOCKED` prevents two concurrent fibers from claiming the same child.


## Queue Layout

The worker has three independent queues. Each runs its own serial + concurrent
fiber group. The queues are fully independent — work on one queue never blocks another.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                           WORKER PROCESS (Crystal)                               │
│                                                                                  │
│  ┌─────────────────────┐  ┌────────────────────────────┐  ┌───────────────────┐ │
│  │   import queue       │  │   analytics queue           │  │ maintenance queue │ │
│  │   1 serial + 1 conc  │  │   1 serial + 4 concurrent   │  │ 1 serial + 1 conc │ │
│  │                      │  │                              │  │                   │ │
│  │  ┌──┐ ┌──┐           │  │  ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ │  │  ┌──┐ ┌──┐         │ │
│  │  │S │ │C1│           │  │  │S │ │C1│ │C2│ │C3│ │C4│ │  │  │S │ │C1│         │ │
│  │  └──┘ └──┘           │  │  └──┘ └──┘ └──┘ └──┘ └──┘ │  │  └──┘ └──┘         │ │
│  └─────────────────────┘  └────────────────────────────┘  └───────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────┘
```

Each queue spawns **1 serial fiber + N concurrent fibers** where N is
`worker.queue_registry.default_concurrency` (verified by
`cli/src/worker.cr:288-309`). The registry value is the *concurrent* count; the
serial fiber is always present in addition.

| Queue        | default_concurrency | Total fibers |
|--------------|---------------------|--------------|
| import       | 1                   | 2            |
| analytics    | 4                   | 5            |
| maintenance  | 1                   | 2            |

**Import queue** (2 fibers): Processes `import_job` parents, each with serial
`import_job_process` children (one per state transition). When an import modifies
data, it triggers `collect_changes` on the analytics queue.

**Analytics queue** (5 fibers = 1 serial + 4 concurrent): Derives all statistical
tables. The serial fiber walks each pipeline stage; when a stage spawns concurrent
children, the 4 concurrent fibers process them in parallel.

**Maintenance queue** (2 fibers): Runs `task_cleanup` and `import_job_cleanup`.

Because the queues are independent, imports and analytics run **truly
concurrently** — a long-running analytics pipeline does not block new imports
from being processed.


## The Derive Pipeline

When data changes (via import or direct edit), the analytics pipeline derives
all downstream tables. `collect_changes` pre-spawns the **entire task tree** —
no handler enqueues the next step. The tree has two phases, each represented by
a wrapper task. All children execute under structured concurrency: serial
siblings run one-at-a-time; concurrent children (batches/periods) run in
parallel on the child fibers.

- **Phase 1** (`derive_units_phase`): steps ①–③
- **Phase 2** (`derive_reports_phase`): steps ④–⑨

```
 IMPORT QUEUE                      ANALYTICS QUEUE
 ════════════                      ═══════════════

 import_job (parent)             ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄
 └─import_job_process
    │ batch processing                Phase 1: Statistical Units
    │ inserts/updates              ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄
    │ base tables (LU, EST, LR)
    │                             ┌─────────────────────────────────────────────┐
    │ holistic steps run after    │ collect_changes                        ①    │
    │ all batches:                │  Drains base_change_log accumulator and     │
    │ • power_group_link creates  │  enqueues derive_statistical_unit.          │
    │   PG records, sets          └──────────────────┬──────────────────────────┘
    │   power_group_id on LR                         │ (strictly sequential)
    │                                                ▼
    │ change-detection triggers   ┌─────────────────────────────────────────────┐
    │ fire on each committed      │ derive_statistical_unit             ②       │
    │ statement:                  │                                     PARENT  │
    │ • log_base_change →         │  Computes "closed groups" of affected       │
    │   base_change_log           │  enterprises, spawns batch children:        │
    │ • ensure_collect_changes →  │                                             │
    │   enqueue collect_changes   │  ┌────────┐ ┌────────┐       ┌────────┐   │
    │   (idempotent dedup)        │  │batch 1 │ │batch 2 │  ...  │batch N │   │
    ▼                             │  │~1000 e.│ │~1000 e.│       │~1000 e.│   │
                                  │  └────────┘ └────────┘       └────────┘   │
                                  │  statistical_unit_refresh_batch             │
                                  │  (4 concurrent fibers process in parallel)  │
                                  │                                             │
                                  │  Also enqueues uncle tasks:                 │
                                  │  • statistical_unit_flush_staging            │
                                  │  • derive_reports                           │
                                  │                                             │
                                  │  Parent state → "waiting"                   │
                                  │  Serial fiber BLOCKED until children done   │
                                  └──────────────────┬──────────────────────────┘
                                                     │ (parent completes, serial fiber resumes)
                                                     ▼
                                  ┌─────────────────────────────────────────────┐
                             ③    │ statistical_unit_flush_staging      SERIAL  │
                                  │  Merges UNLOGGED staging table into         │
                                  │  main statistical_unit table.               │
                                  └──────────────────┬──────────────────────────┘
                                                     │
                                ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄
                                  Phase 2: Reports
                                ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄
                                                     │
                                                     ▼
                                  ┌─────────────────────────────────────────────┐
                             ④    │ derive_reports                      SERIAL  │
                                  │  Starts the reporting chain.                │
                                  │  Enqueues → derive_statistical_history      │
                                  └──────────────────┬──────────────────────────┘
                                                     │
                                                     ▼
                                  ┌─────────────────────────────────────────────┐
                             ⑤    │ derive_statistical_history          PARENT  │
                                  │                                             │
                                  │  Enqueues → derive_statistical_unit_facet   │
                                  │  Enqueues → statistical_history_reduce      │
                                  │                                             │
                                  │  Spawns period children (parallel):         │
                                  │  ┌──────────┐ ┌──────────┐ ┌──────────┐   │
                                  │  │ year '24 │ │ mo '24-1 │ │ mo '24-2 │...│
                                  │  └──────────┘ └──────────┘ └──────────┘   │
                                  │  derive_statistical_history_period          │
                                  │                                             │
                                  │  Parent "waiting" → children → done         │
                                  └──────────────────┬──────────────────────────┘
                                                     │
                                                     ▼
                                  ┌─────────────────────────────────────────────┐
                            ⑤b    │ statistical_history_reduce          SERIAL  │
                                  │  Aggregates partition entries into root      │
                                  │  entries for statistical_history.            │
                                  └──────────────────┬──────────────────────────┘
                                                     │
                                                     ▼
                                  ┌─────────────────────────────────────────────┐
                             ⑥    │ derive_statistical_unit_facet       PARENT  │
                                  │                                             │
                                  │  Spawns partition children (parallel):      │
                                  │  ┌──────────┐ ┌──────────┐ ┌──────────┐   │
                                  │  │ part 0   │ │ part 1   │ │ part N   │...│
                                  │  └──────────┘ └──────────┘ └──────────┘   │
                                  │  derive_statistical_unit_facet_partition    │
                                  │                                             │
                                  │  Enqueues → statistical_unit_facet_reduce   │
                                  │  Enqueues → derive_statistical_history_facet│
                                  │                                             │
                                  │  Parent "waiting" → children → done         │
                                  └──────────────────┬──────────────────────────┘
                                                     │
                                                     ▼
                                  ┌─────────────────────────────────────────────┐
                            ⑥b    │ statistical_unit_facet_reduce       SERIAL  │
                                  │  Merges partition staging data into         │
                                  │  main statistical_unit_facet table.         │
                                  └──────────────────┬──────────────────────────┘
                                                     │
                                                     ▼
                                  ┌─────────────────────────────────────────────┐
                             ⑦    │ derive_statistical_history_facet    PARENT  │
                                  │                                             │
                                  │  Enqueues → statistical_history_facet_reduce│
                                  │                                             │
                                  │  Spawns period children (parallel):         │
                                  │  ┌──────────┐ ┌──────────┐ ┌──────────┐   │
                                  │  │ year '24 │ │ mo '24-1 │ │ mo '24-2 │...│
                                  │  └──────────┘ └──────────┘ └──────────┘   │
                                  │  derive_statistical_history_facet_period    │
                                  │                                             │
                                  │  Parent "waiting" → children → done         │
                                  └──────────────────┬──────────────────────────┘
                                                     │
                                                     ▼
                                  ┌─────────────────────────────────────────────┐
                            ⑦b    │ statistical_history_facet_reduce    SERIAL  │
                                  │  Aggregates partition entries into root      │
                                  │  entries for statistical_history_facet.      │
                                  └──────────────────┬──────────────────────────┘
                                                     │
                                                     ▼
                                  Pipeline complete.
                                  Frontend detects is_deriving_reports()
                                  transitioning true → false, invalidates caches.
```

**Reading the diagram:** Each numbered step (①–⑦b) is a serial task that
runs to completion before the next one starts. Steps marked PARENT spawn
concurrent children that run in parallel on the concurrent fibers; the serial
fiber blocks until all children finish. This is structured concurrency —
concurrency is scoped inside the parent, never between serial tasks.


## Staging Pattern and Race Safety

Step ② (`derive_statistical_unit`) writes to an UNLOGGED staging table
(`statistical_unit_staging`) via batch children, then step ③
(`statistical_unit_flush_staging`) merges staging into the main table and
TRUNCATEs staging.

**Why there is no TRUNCATE at the start of derive_statistical_unit:**
An earlier version TRUNCATEd staging at the start of each derive cycle to
"clean up interrupted runs." This created a latent race: if `collect_changes`
enqueued a new `derive_statistical_unit` before the previous cycle's
`flush_staging` ran, the TRUNCATE would destroy all staged data. The race was
nearly triggered in concurrent testing (priority gaps as small as 2 sequence
values). The TRUNCATE was removed because:

1. Batch children already do `DELETE FROM staging WHERE unit_type/unit_id`
   before inserting — stale data from a previous cycle gets overwritten
2. `flush_staging` TRUNCATEs at the end after merging staging → main
3. UNLOGGED tables auto-truncate on unclean shutdown (PostgreSQL guarantee)


## Partitioning derive_statistical_unit_facet

The three derived tables have different data models:

| Table                      | Keyed by                               | Natural partition |
|----------------------------|----------------------------------------|-------------------|
| `statistical_history`      | `(resolution, year, month, unit_type)` | period            |
| `statistical_history_facet`| `(resolution, year, month, ...dims)`   | period            |
| `statistical_unit_facet`   | `(valid_from, valid_until, ...dims)`   | `(unit_type, unit_id)` |

`statistical_history` and `statistical_history_facet` use period-based keys
(`year`, `month`), so each period child touches **disjoint rows** — perfect
for parallel splitting.

`statistical_unit_facet` uses **date ranges** (`valid_from`, `valid_until`).
A facet row with `valid_from=2020, valid_until=2025` would overlap **65
periods** (5 year + 60 month). Splitting by period would cause each child to
redundantly DELETE and re-INSERT the same row. Correct but 65x wasteful.

Instead, DSUF partitions by `(unit_type, unit_id)` using a **map-reduce**
pattern: each partition child writes partial aggregations to an UNLOGGED
staging table, then `statistical_unit_facet_reduce` merges and swaps the
results into the main table in a single transaction.

Only **dirty hash slots** (those with changed data tracked in
`statistical_unit_facet_dirty_hash_slots`) are recomputed at the partition-derive
level. The reduce step does a global MERGE over the full staging-aggregate (see
the *Reduce strategy* section below); incremental savings come from skipping
non-dirty slots' partition derives, not from scoping the reduce.


## Production Performance (1.1M LU + 826K ES = 3.1M stat units)

Measured on `no.statbus.org`, **March 2026**, predating the Phase 2
slot-keyed `statistical_history` aggregation (commit `cdbc9c0ec`, April 30) and
the Phase 3 facet-reduce collapse (commit `159b8c9e8`, April 30). The numbers
below are historical baseline. The Phase 3 reduces no longer use the scoped
Path B; expect different (likely slightly higher) `*_facet_reduce` self-times
on subsequent measurements. Re-measure on the next 2M-row test cycle.

### Scaling behavior during heavy import

| Pipeline scale | Wall time | Batch count | Context |
|---|---|---|---|
| Tiny (post-import) | 25-150s | 45-586 | Single-edit responsiveness |
| Medium (during import) | 100-500s | ~2300 | Steady-state import processing |
| Large (accumulating) | 1000-3000s | 2500-2700 | Changes accumulate faster than processed |
| Peak (largest) | ~10000s | 753-3251 | Maximum accumulation, still progressing |
| Post-import cleanup | 150-250s | 45 | System fast again once import stops |

### Bottleneck ranking (total self-time across 19 pipeline runs)

| Step | Total self (s) | Avg self (s) | Max self (s) | Role |
|---|---|---|---|---|
| `statistical_unit_flush_staging` | 2702 | 142 | 734 | Serial MERGE staging→main |
| `derive_statistical_unit` | 1527 | 80 | 727 | Parallel batch spawner |
| `statistical_history_facet_reduce` | 1111 | 58 | 141 | Scoped MERGE facet aggregation |
| `statistical_unit_facet_reduce` | 338 | 18 | 53 | Scoped MERGE facet partitions |
| `derive_statistical_history_facet` | 253 | 13 | 56 | Parallel period spawner |
| `derive_statistical_history` | 55 | 3 | 15 | Parallel period spawner |
| `derive_statistical_unit_facet` | 47 | 2 | 6 | Parallel partition spawner |
| `statistical_history_reduce` | 1 | 0.03 | 0.1 | Near-instant aggregation |


## Performance Optimizations Applied

These optimizations were applied in March 2026 to improve pipeline throughput:

**Join strategy: COALESCE sentinels replacing IS NOT DISTINCT FROM.**
`IS NOT DISTINCT FROM` prevents PostgreSQL from using hash/merge joins, forcing
nested loop joins. With large tables (800K × 750K rows), this caused 37+ minute
queries. Fix: `COALESCE(col, sentinel) = COALESCE(col, sentinel)` enables hash
joins while preserving NULL equality semantics. Applied across MERGE ON clauses
and timeline view joins.

**Incremental partition derives + global reduce.**
At the partition-derive level: only dirty hash slots' staging rows are
recomputed. Non-dirty slots' staging is reused as-is (the cache).

At the reduce level (after Phase 3, migration `159b8c9e8`): both
`worker.statistical_unit_facet_reduce` and `worker.statistical_history_facet_reduce`
collapse to a single global MERGE shape with `WHEN NOT MATCHED BY SOURCE THEN
DELETE`. The previous three-path adaptive strategy (scoped MERGE for ≤128 dirty,
full MERGE for >128, TRUNCATE+INSERT for full refresh) had a structural cleanup
gap in the scoped path (Path B's DELETE was gated by `dim_tuple IN
pre_dirty_dims`, so stale target rows whose dim+temporal wasn't in any
subsequent drain's pre_dirty couldn't self-heal). The global MERGE is
self-healing by construction; the per-slot cache in staging still provides
the aggregation-side incremental property. Cost is bounded by aggregated
cardinality (`distinct_dim_combos × distinct_slice_count`), not raw row count.

**Filtered batching from affected enterprises.**
For single-unit changes, the old approach joined all 3 base tables to find
affected groups (380K × 1.1M × 824K). The fix starts from the affected
enterprises (via `base_change_log`) and expands outward, reducing the query
from 8 seconds to 16 milliseconds (500x improvement).

**MERGE replacing DELETE+INSERT for `_used_derive` functions.**
Six `_used_derive` functions were converted from DELETE+INSERT to MERGE,
avoiding unnecessary row churn when the derived data hasn't changed.

**Timesegments short-circuit.**
`timesegments_years_refresh_concurrent` checks MIN/MAX year before running.
If the year range hasn't changed, the refresh is skipped entirely.

**Snapshot tables for pre-dirty dimension combos (legacy; no longer read).**
Two UNLOGGED snapshot tables (`statistical_unit_facet_pre_dirty_dims`,
`statistical_history_facet_pre_dirty_dims`) were used by the old Path B scoped
MERGE to detect disappeared dim combos. After Phase 3's collapse to global MERGE
(migration `159b8c9e8`), the reduces no longer read these snapshots; the global
MERGE's `WHEN NOT MATCHED BY SOURCE THEN DELETE` catches disappeared combos by
construction. The parent `derive_*_facet` procedures still TRUNCATE+INSERT into
the snapshots — dead state pending a follow-up cleanup migration that drops the
tables and the parent's snapshot writes.

**Temp tables replacing CTE chains.**
Large CTE chains don't optimize well in PostgreSQL. Breaking into sequential
temp tables with indexes allows independent optimization of each step.

**UNLOGGED staging tables.**
Fast writes with no WAL overhead. Automatically truncated on unclean shutdown
(PostgreSQL guarantee), which is safe because the pipeline does a full refresh
on crash recovery.

**Configurable partition modulus with auto-tune.**
`partition_count_target` adapts to the data size via
`admin.adjust_partition_count_target()` called during `statistical_unit_flush_staging`.
Targets bands roughly: ≤100 units → 4, ≤10000 → 16, ≤100000 → 64, ≤1000000 → 128,
larger → 256. After Phase 2 (`cdbc9c0ec`), `statistical_history` per-slot rows
are stored as singleton `int4range(slot, slot+1)` regardless of target — the
target only controls compute batch grain at derive time, not storage geometry.
This decouples cached per-slot rows from target changes; no invalidation
needed when auto-tune adjusts.


## Command Registry

All commands, their queue assignments, and pipeline phase:

| Queue       | Command                                   | Role        | Depth | Phase                       | Notes                        |
|-------------|-------------------------------------------|-------------|-------|-----------------------------|------------------------------|
| analytics   | `collect_changes`                         | root        | 0     | —                           | Drains base_change_log, pre-spawns tree |
| analytics   | `derive_units_phase`                      | phase       | 1     | `is_deriving_stat_units`    | Serial wrapper for unit derivation |
| analytics   | `derive_statistical_unit`                 | parent      | 2     | `is_deriving_stat_units`    | Spawns concurrent batch children |
| analytics   | `statistical_unit_refresh_batch`          | child       | 3     | `is_deriving_stat_units`    | Parallel batch processing    |
| analytics   | `statistical_unit_flush_staging`          | leaf        | 2     | `is_deriving_stat_units`    | Merge staging → main table   |
| analytics   | `derive_reports_phase`                    | phase       | 1     | `is_deriving_reports`       | Serial wrapper for reports   |
| analytics   | `derive_statistical_history`              | parent      | 2     | `is_deriving_reports`       | Spawns concurrent period children |
| analytics   | `derive_statistical_history_period`       | child       | 3     | `is_deriving_reports`       | Per-period aggregation       |
| analytics   | `statistical_history_reduce`              | leaf        | 2     | `is_deriving_reports`       | Aggregate history partitions |
| analytics   | `derive_statistical_unit_facet`           | parent      | 2     | `is_deriving_reports`       | Spawns concurrent partition children |
| analytics   | `derive_statistical_unit_facet_partition` | child       | 3     | `is_deriving_reports`       | Per-partition facet compute  |
| analytics   | `statistical_unit_facet_reduce`           | leaf        | 2     | `is_deriving_reports`       | Merge partitions → main      |
| analytics   | `derive_statistical_history_facet`        | parent      | 2     | `is_deriving_reports`       | Spawns concurrent period children |
| analytics   | `derive_statistical_history_facet_period` | child       | 3     | `is_deriving_reports`       | Per-period facet aggregation |
| analytics   | `statistical_history_facet_reduce`        | leaf        | 2     | `is_deriving_reports`       | Terminal — notifies complete |
| analytics   | `derive_reports`                          | (legacy)    | —     | —                           | No-op stub for old task refs |
| import      | `import_job`                              | parent      | 0     | —                           | Wrapper per import job       |
| import      | `import_job_process`                      | serial child| 1     | —                           | One state transition at a time |
| maintenance | `task_cleanup`                            | top-level   | 0     | —                           | Clean old tasks              |
| maintenance | `import_job_cleanup`                      | top-level   | 0     | —                           | Clean expired imports        |


## Round-Based Priority

All tasks in a pipeline round share the **same priority** — the priority of
the `collect_changes` task that started the round. This prevents interleaving
of stages from different rounds.

### How it works

1. `collect_changes` reads its own `priority` from `worker.tasks` as
   `round_priority_base`.
2. Every downstream enqueue/spawn call receives `round_priority_base` and uses
   it as the task priority. The value is also stored in the payload so handlers
   can read and propagate it further.

No sequence reservation is needed: the priority sequence is monotonically
increasing, so any *new* `collect_changes` triggered during this round
naturally gets a higher priority number (= runs later).

### ORDER BY priority ASC, id invariant

`process_tasks` picks tasks with:
```sql
ORDER BY t.priority ASC NULLS LAST, t.id
```

With all tasks in a round sharing the same priority, the tiebreaker is `t.id`
(BIGSERIAL, monotonically increasing). Since each stage creates the next
sequentially, **creation order = pipeline order = id order**. This means:

- **Between rounds:** Round 1 (priority P) runs entirely before Round 2
  (priority Q > P).
- **Within a round:** Stages run in creation order (ascending `t.id`).

### Pre-spawned tree eliminates uncle tasks

Previously, handlers enqueued "uncle" tasks (flat top-level tasks that ran
after the current parent completed). This created ordering fragility — uncle
tasks relied on priority ordering and `ON CONFLICT` dedup to avoid
interleaving between pipeline rounds.

The new tree structure eliminates this entirely: `collect_changes` pre-spawns
the full tree, and serial `child_mode` on phase wrappers enforces execution
order structurally. No dedup indexes are needed for pipeline steps (only
`collect_changes` retains its dedup index for idempotent triggering).

### Cascade-fail safety

When a task fails mid-execution and has pre-spawned children (which are
still `pending`), those children would become orphans. The
`cascade_fail_descendants()` function recursively marks all descendant tasks
as `failed` with error `'Parent task failed'`.


## Frontend Status Detection

The frontend receives pipeline state via two mechanisms:

1. **`pg_notify` events** — `worker.notify_task_progress()` sends real-time
   push notifications with `{type: 'pipeline_progress', phases: [...]}`.
   Each phase object contains `phase`, `step`, `total`, `completed`,
   and effective entity counts (`effective_establishment_count`, etc.).
   Called automatically by `process_tasks` after each
   analytics-queue task completes.
2. **`is_deriving_statistical_units()` / `is_deriving_reports()`** — SQL
   functions that query the **task tree** (`worker.tasks`) to determine if
   a pipeline phase is active. Used for initial page load and reconnection.

Both functions query `worker.tasks` directly — progress is intrinsic to the
task tree. A phase is `active` when there are `processing` or `waiting` tasks
for the relevant commands.

When a phase completes (no more active tasks), the frontend clears the
phase status and invalidates its caches (search results, base data) to pick
up the newly derived data.

See [worker-notifications.md](./worker-notifications.md) for the full
notification architecture.

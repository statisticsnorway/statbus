# Derive Pipeline Architecture

This document describes how STATBUS derives statistical tables from imported
data. It covers the task flow, structured concurrency model, and queue layout.

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
│  Per queue: 1 top fiber + N child fibers                             │
│                                                                      │
│  Top fiber                                                           │
│  ─────────                                                           │
│  loop:                                                               │
│    pick ONE top-level pending task (LIMIT 1, SKIP LOCKED)            │
│    run its handler                                                   │
│    if handler spawned children:                                      │
│      parent state → "waiting"                                        │
│      wake N child fibers ──────────────┐                             │
│      BLOCK until all children done     │                             │
│      parent auto-completes             │                             │
│    pick next top-level task            │                             │
│                                        │                             │
│  Child fibers (sleep until woken)      │                             │
│  ────────────────────────────────      │                             │
│    ◄───────────────────────────────────┘                             │
│    loop:                                                             │
│      pick ONE pending child (LIMIT 1, SKIP LOCKED)                   │
│      run its handler                                                 │
│      if no more children: signal top fiber, go back to sleep         │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Key properties:**
- Top-level tasks execute **strictly sequentially** — no overlap, no races.
- Children execute **concurrently** within the bounded scope of one parent.
- The parent does not complete until ALL children finish (or fail).
- Child fibers sleep between parent tasks — zero CPU when idle.
- `FOR UPDATE SKIP LOCKED` prevents two child fibers from claiming the same child.


## Queue Layout

The worker has three independent queues. Each runs its own top + child fiber
group. The queues are fully independent — work on one queue never blocks another.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WORKER PROCESS (Crystal)                          │
│                                                                             │
│  ┌─────────────────────┐  ┌──────────────────────┐  ┌───────────────────┐  │
│  │   import queue       │  │   analytics queue     │  │ maintenance queue │  │
│  │   1 top + 0 child    │  │   1 top + 3 child     │  │ 1 top + 0 child  │  │
│  │                      │  │                        │  │                  │  │
│  │  ┌────────────────┐  │  │  ┌──┐ ┌──┐ ┌──┐ ┌──┐ │  │  ┌────────────┐ │  │
│  │  │ top fiber      │  │  │  │T │ │C1│ │C2│ │C3│ │  │  │ top fiber  │ │  │
│  │  └────────────────┘  │  │  └──┘ └──┘ └──┘ └──┘ │  │  └────────────┘ │  │
│  └─────────────────────┘  └──────────────────────┘  └───────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Import queue** (1 fiber): Processes `import_job_process` one at a time.
When an import modifies data, it triggers `collect_changes` on the analytics queue.

**Analytics queue** (4 fibers = 1 top + 3 child): Derives all statistical
tables. The top fiber runs each pipeline stage sequentially; when a stage
spawns children, the 3 child fibers process them in parallel.

**Maintenance queue** (1 fiber): Runs `task_cleanup` and `import_job_cleanup`.

Because the queues are independent, imports and analytics run **truly
concurrently** — a long-running analytics pipeline does not block new imports
from being processed.


## The Derive Pipeline

When data changes (via import or direct edit), the analytics pipeline derives
all downstream tables. Each box below is a **top-level task** — they run
**strictly one at a time**, in order:

```
 IMPORT QUEUE                      ANALYTICS QUEUE
 ════════════                      ═══════════════

 import_job_process
    │ data changes fire
    │ lifecycle trigger
    ▼
                          ┌─────────────────────────────────────────────┐
                     ①    │ collect_changes                             │
                          │  Drains base_change_log accumulator and     │
                          │  enqueues derive_statistical_unit.          │
                          └──────────────────┬──────────────────────────┘
                                             │ (strictly sequential — next task)
                                             ▼
                          ┌─────────────────────────────────────────────┐
                     ②    │ derive_statistical_unit             PARENT  │
                          │                                             │
                          │  Computes "closed groups" of affected       │
                          │  enterprises, spawns batch children:        │
                          │                                             │
                          │  ┌────────┐ ┌────────┐       ┌────────┐   │
                          │  │batch 1 │ │batch 2 │  ...  │batch N │   │
                          │  │~1000 e.│ │~1000 e.│       │~1000 e.│   │
                          │  └────────┘ └────────┘       └────────┘   │
                          │  statistical_unit_refresh_batch             │
                          │  (3 child fibers process in parallel)      │
                          │                                             │
                          │  Also enqueues uncle tasks:                 │
                          │  • statistical_unit_flush_staging            │
                          │  • derive_reports                           │
                          │                                             │
                          │  Parent state → "waiting"                   │
                          │  Top fiber BLOCKED until all children done  │
                          └──────────────────┬──────────────────────────┘
                                             │ (parent completes, top fiber resumes)
                                             ▼
                          ┌─────────────────────────────────────────────┐
                     ③    │ statistical_unit_flush_staging      SERIAL  │
                          │  Merges UNLOGGED staging table into         │
                          │  main statistical_unit table.               │
                          └──────────────────┬──────────────────────────┘
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
                          Pipeline complete.
                          Frontend detects is_deriving_statistical_units()
                          transitioning true → false, invalidates caches.
```

**Reading the diagram:** Each numbered step (①–⑦) is a top-level task that
runs to completion before the next one starts. Steps marked PARENT spawn
children that run in parallel on the child fibers; the top fiber blocks until
all children finish. This is structured concurrency — concurrency is scoped
inside the parent, never between top-level tasks.


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

Only **dirty partitions** (those with changed data tracked in
`statistical_unit_facet_dirty_partitions`) are recomputed.


## Production Performance (1.1M LU + 826K ES = 3.1M stat units)

Measured on `no.statbus.org`, February 2026. Since top-level tasks run
strictly sequentially, the total wall clock is the **sum** of all stages:

```
Step  Pipeline stage                            CPU time   Children
─────────────────────────────────────────────────────────────────────────
 ②   derive_statistical_unit (batches)          120 s      2337 batches
      └─ statistical_unit_refresh_batch total   25.2k s    ~3.7x parallel
 ③   statistical_unit_flush_staging             1,038 s    —
 ④   derive_reports                                6 ms    —
 ⑤   derive_statistical_history (periods)           2 s    3 period children
      └─ derive_statistical_history_period         <3 s    ~3x parallel
 ⑥   derive_statistical_unit_facet               178 s     —
 ⑦   derive_statistical_history_facet (periods)     1 s    3 period children
      └─ derive_statistical_history_facet_period  <11 s    ~3x parallel
─────────────────────────────────────────────────────────────────────────
     End-to-end wall clock (incremental):       ~2.5 hours
```

The dominant cost is the batch work (`statistical_unit_refresh_batch` at
25.2k seconds CPU), which computes timeline views and `statistical_unit`
rows for each enterprise's closed group. With 3 child fibers achieving ~3.7x
effective parallelism, the wall clock for step ② is ~6,800 seconds (1h 53m).

The staging flush (step ③, ~17 minutes) and DSUF (step ⑥, ~3 minutes) are
the next-largest costs. The reporting stages (DSH, DSHF) take seconds.


## Command Registry

All commands and their queue assignments:

| Queue       | Command                                   | Role        | Notes                        |
|-------------|-------------------------------------------|-------------|------------------------------|
| analytics   | `collect_changes`                         | top-level   | Drains base_change_log       |
| analytics   | `derive_statistical_unit`                 | parent      | Spawns batch children        |
| analytics   | `statistical_unit_refresh_batch`          | child       | Parallel batch processing    |
| analytics   | `derive_statistical_unit_continue`        | top-level   | ANALYZE sync point           |
| analytics   | `statistical_unit_flush_staging`          | top-level   | Merge staging → main table   |
| analytics   | `derive_reports`                          | top-level   | Enqueues DSH                 |
| analytics   | `derive_statistical_history`              | parent      | Spawns period children       |
| analytics   | `derive_statistical_history_period`       | child       | Per-period aggregation       |
| analytics   | `derive_statistical_unit_facet`           | parent      | Spawns partition children    |
| analytics   | `derive_statistical_unit_facet_partition` | child       | Per-partition facet compute  |
| analytics   | `statistical_unit_facet_reduce`           | top-level   | Merge partitions → main      |
| analytics   | `derive_statistical_history_facet`        | parent      | Spawns period children       |
| analytics   | `derive_statistical_history_facet_period` | child       | Per-period facet aggregation |
| import      | `import_job_process`                      | top-level   | One import at a time         |
| maintenance | `task_cleanup`                            | top-level   | Clean old tasks              |
| maintenance | `import_job_cleanup`                      | top-level   | Clean expired imports        |


## Frontend Status Detection

The frontend polls `is_deriving_statistical_units()` and
`is_deriving_reports()` to detect when derivation is active. These functions
check for tasks in `'pending'`, `'processing'`, or `'waiting'` states.

When the function transitions from `true` → `false`, the frontend invalidates
its caches (search results, base data) to pick up the newly derived data.

See [worker-notifications.md](./worker-notifications.md) for the full
notification architecture.

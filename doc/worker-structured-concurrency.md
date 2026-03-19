# Worker Structured Concurrency

This document describes the structured concurrency model used in the STATBUS worker system, inspired by [Trio's nurseries](https://trio.readthedocs.io/en/stable/reference-core.html#tasks-let-you-do-multiple-things-at-once) and similar patterns.

## Overview

Structured concurrency provides a disciplined approach to concurrent task execution with clear boundaries and automatic synchronization. The key principles are:

1. **Fan-out**: A parent task spawns multiple child tasks
2. **Sync point**: The parent waits until ALL children complete
3. **Continue**: Only after sync point does the parent complete

This contrasts with unstructured concurrency where tasks are "fire and forget" with no automatic coordination.

## Task States

```
pending → processing → completed
                    ↘ failed
                    ↘ waiting (parent with children)
```

- **pending**: Task ready to be picked up
- **processing**: Task currently executing
- **waiting**: Parent task has spawned children and awaits their completion
- **completed**: Task finished successfully
- **failed**: Task encountered an error

## Parent-Child Relationships

### Spawning Children

A handler procedure spawns child tasks using `worker.spawn()`:

```sql
-- Inside derive_statistical_unit handler
CALL worker.spawn(
    p_command => 'statistical_unit_refresh_batch',
    p_payload => jsonb_build_object('batch_seq', 1, 'enterprise_ids', ARRAY[1,2,3]),
    p_parent_id => p_task_id,  -- Links child to parent
    p_priority => 20
);
```

When a task spawns children:
1. Children are created with `parent_id` pointing to the parent task
2. After the handler returns, `process_tasks` checks if children exist
3. If children exist, parent state becomes `waiting` (not `completed`)

### Automatic Parent Completion

When a child task completes (or fails):
1. `complete_parent_if_ready()` is called automatically
2. It checks if all siblings are finished (completed or failed)
3. If all done:
   - If any child failed → parent fails
   - If all children completed → parent completes
4. Parent's `completed_at` timestamp is set

### Info Aggregation

Each handler reports what it did via `INOUT p_info jsonb`. When
`complete_parent_if_ready()` completes a parent, it merges all children's
info using SUM for numeric values. See [worker.md](worker.md#task-info-reporting)
for details and the Info Principle.

### Recursive Nesting

The system supports **recursive** parent-child relationships:
- Children can spawn grandchildren (arbitrary depth)
- Children can spawn siblings (same `parent_id`)
- Children can spawn uncle tasks (`parent_id IS NULL`)
- `depth` column tracks nesting level (0 = top-level, parent.depth + 1 for children)
- `child_mode` on the parent controls child execution: `'concurrent'` (parallel, default) or `'serial'` (one at a time)
- Depth-first parent selection ensures grandchildren complete before the fiber moves up

### Dynamic Work Spreading

Children can spawn more siblings at the same priority level, enabling dynamic batching:

```sql
-- Child task discovers more work needed, spawns sibling
CALL worker.spawn(
    p_command => 'statistical_unit_refresh_batch',
    p_payload => jsonb_build_object('batch_seq', 99, ...),
    p_parent_id => (SELECT parent_id FROM worker.tasks WHERE id = current_task_id),
    p_priority => 20  -- Same priority as siblings
);
```

This allows:
- Initial coarse batching that subdivides as needed
- Work discovery during processing (e.g., finding more affected entities)
- Load balancing by splitting large batches into smaller ones

The parent remains in `waiting` state until ALL children (including dynamically spawned ones) complete.

## How Fibers Cooperate

Each queue has **1 serial fiber** and **N concurrent fibers** (where N = concurrency - 1).
Two fiber types serve two purposes:

1. **Serial fiber** (1 per queue) — ensures **predictability**. Walks the serial path depth-first, one task at a time. Picks top-level tasks and serial children.
2. **Concurrent fibers** (N per queue) — ensures **speed**. A shared pool that processes concurrent work at any depth, up to the system resource limit.

For the original concept, see [Notes on structured concurrency, or: Go
statement considered harmful](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)
by Nathaniel J. Smith.

### Serial Fiber (depth-first serial execution)

The serial fiber walks the serial path:
- Picks top-level pending tasks or serial children of waiting parents
- If the handler spawns children, the parent enters `waiting` state
- If a concurrent parent exists, the serial fiber **exits** → Crystal wakes concurrent fibers and **blocks**
- When all concurrent fibers signal done, the serial fiber resumes walking the serial path
- The serial fiber also picks serial children at any depth (not just top-level)

### Concurrent Fibers (parallel execution within scope)

Concurrent fibers sleep until the serial fiber wakes them:
- Each picks **one pending child** of the deepest concurrent parent (`LIMIT 1, SKIP LOCKED`)
- Multiple concurrent fibers process different children in parallel
- Each concurrent fiber is a full executor: if a child spawns serial sub-children, the fiber walks them inline
- When no more concurrent children remain, each signals the serial fiber and goes back to sleep

### Serial→Concurrent→Serial→Concurrent (arbitrary depth)

The tree can alternate between serial and concurrent at any depth:

```
┌─────────────────────────────────────────────────────────────┐
│  Top-level tasks: strictly sequential (serial fiber)         │
│  ┌──────┐  ┌──────┐  ┌──────┐                              │
│  │Task A│→ │Task B│→ │Task C│  (one at a time)             │
│  └──────┘  └──────┘  └──────┘                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  When concurrent children exist: scoped concurrency          │
│                                                             │
│  ┌──────────────────────────────────┐                      │
│  │ Parent Task (state: waiting)     │                      │
│  │ Serial fiber BLOCKED here        │                      │
│  │                                  │                      │
│  │  ┌───────┐ ┌───────┐ ┌───────┐  │                      │
│  │  │Child 1│ │Child 2│ │Child 3│  │  (parallel on        │
│  │  │Fiber 1│ │Fiber 2│ │Fiber 3│  │   concurrent fibers) │
│  │  └───────┘ └───────┘ └───────┘  │                      │
│  │              ↓                   │                      │
│  │     All children complete        │                      │
│  │              ↓                   │                      │
│  │     Parent → completed           │                      │
│  │     Serial fiber unblocked       │                      │
│  └──────────────────────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

## Phase Wrappers (Serial Child Trees)

The pipeline uses **phase wrappers** — intermediate tasks that group related
steps into a serial subtree. `collect_changes` pre-spawns the entire tree:

```
collect_changes (depth=0, serial)
├── derive_units_phase (depth=1, serial)
│   ├── derive_statistical_unit (depth=2, concurrent children at depth=3)
│   └── statistical_unit_flush_staging (depth=2, leaf)
└── derive_reports_phase (depth=1, serial)
    ├── derive_statistical_history (depth=2, concurrent children at depth=3)
    ├── statistical_history_reduce (depth=2, leaf)
    ├── derive_statistical_unit_facet (depth=2, concurrent children at depth=3)
    ├── statistical_unit_facet_reduce (depth=2, leaf)
    ├── derive_statistical_history_facet (depth=2, concurrent children at depth=3)
    └── statistical_history_facet_reduce (depth=2, leaf, terminal)
```

No mixed child_modes — each parent is purely serial or purely concurrent.
Max depth = 3. The tree is pre-spawned (no handler enqueues the next step),
so execution order is enforced structurally by serial `child_mode`.

## Example: How process_tasks handles 4 levels

Traced for the analytics queue (1 serial fiber + 3 concurrent fibers):

1. Serial fiber picks `collect_changes` (depth=0). Handler pre-spawns entire tree.
   Has-children check → `waiting`.
2. Serial fiber: `process_tasks(serial)` finds `collect_changes` is serial parent.
   Picks `derive_units_phase` (depth=1). Handler is a no-op, has pre-spawned
   children → `waiting`.
3. Serial fiber loops. Deepest serial parent is `derive_units_phase` (depth=1).
   Picks `derive_statistical_unit` (depth=2). Handler spawns concurrent batch
   grandchildren → `waiting`.
4. Serial fiber: `process_tasks(serial)` detects concurrent parent
   `derive_statistical_unit` (depth=2) → **exits**. Crystal wakes 3 concurrent fibers.
5. All 3 concurrent fibers process batch tasks (depth=3) in parallel via
   `SKIP LOCKED`.
6. All batches complete → `derive_statistical_unit` auto-completes.
   Concurrent fibers find no more concurrent parents → signal done.
   Serial fiber **unblocks**.
7. Serial fiber resumes. `derive_units_phase` (depth=1, serial) is deepest
   serial parent. Picks `statistical_unit_flush_staging` (depth=2, leaf).
8. `statistical_unit_flush_staging` completes → `derive_units_phase`
   auto-completes → `collect_changes` still has `derive_reports_phase` pending.
9. Serial fiber picks `derive_reports_phase`. Handler runs
   `adjust_analytics_partition_count()`, has pre-spawned children → `waiting`.
   Continues walking serial children, with concurrent fibers woken for
   concurrent grandchildren where applicable.
10. Eventually all work done. Serial fiber finds no more tasks.
    Waits for next notification.

For the full pipeline diagram, see [derive-pipeline.md](./derive-pipeline.md).

## Why Skip ANALYZE in Batches?

`ANALYZE` acquires `ShareUpdateExclusiveLock` which conflicts with itself. If each batch task runs ANALYZE:

```
Fiber 1: ANALYZE establishment ← holds lock
Fiber 2: ANALYZE establishment ← blocked!
Fiber 3: ANALYZE establishment ← blocked!
Fiber 4: ANALYZE establishment ← blocked!
```

All concurrency is lost. Instead:
- Batch tasks skip ANALYZE (only do DELETE/INSERT)
- ANALYZE runs separately (not inside batch children)
- True parallel execution achieved

## Error Handling and Cascade-Fail

- If any child fails, parent eventually fails (after all children finish)
- `has_failed_siblings()` can be checked by children
- Failed state propagates upward but doesn't interrupt sibling execution
- **Cascade-fail**: When a task fails and has pre-spawned descendants still
  in `pending` or `waiting` state, `cascade_fail_descendants()` recursively
  marks them all as `failed` to prevent orphaned tasks

## Testing

```sql
-- Test structured concurrency in pg_regress
BEGIN;

-- Create parent task
INSERT INTO worker.tasks (command, payload)
VALUES ('derive_statistical_unit', '{}');

-- Process to create children
CALL worker.process_tasks(p_queue => 'analytics');

-- Verify parent is waiting
SELECT state FROM worker.tasks WHERE command = 'derive_statistical_unit';
-- Returns: waiting

-- Process children
CALL worker.process_tasks(p_queue => 'analytics');

-- Verify parent completed
SELECT state FROM worker.tasks WHERE command = 'derive_statistical_unit';
-- Returns: completed

ROLLBACK;
```

## Key Functions

| Function | Purpose |
|----------|---------|
| `worker.spawn()` | Create child task linked to parent |
| `worker.has_pending_children()` | Check if task has unfinished children |
| `worker.has_failed_siblings()` | Check if any sibling failed |
| `worker.complete_parent_if_ready()` | Complete parent when all children done |
| `worker.notify_task_progress()` | Notify frontend of task tree progress |

## Related Documentation

- [Worker System Architecture](./worker.md)
- [Worker Notifications](./worker-notifications.md)

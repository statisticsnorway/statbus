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

### Single-Level Only

The system enforces **single-level** parent-child relationships:
- Children cannot spawn grandchildren (trigger prevents this)
- Children CAN spawn siblings (same `parent_id`)
- This keeps the model simple and predictable

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

Each queue has **1 top fiber** and **N child fibers** (where N = concurrency - 1).
The top fiber is the only one that picks top-level tasks. Child fibers sleep
until explicitly woken.

For the original concept, see [Notes on structured concurrency, or: Go
statement considered harmful](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)
by Nathaniel J. Smith.

### Top Fiber (serial execution)

The top fiber picks **exactly one** top-level task at a time:
- If the handler spawns children, the parent enters `waiting` state
- The top fiber wakes the child fibers and **blocks** until they all signal done
- Only then does it loop to pick the next top-level task
- If a `waiting` parent exists when `mode='top'`, the SQL returns immediately
  (no second top-level task can start)

### Child Fibers (parallel execution within scope)

Child fibers sleep until the top fiber wakes them:
- Each picks **one pending child** of the waiting parent (`LIMIT 1, SKIP LOCKED`)
- Multiple child fibers process different children concurrently
- When no more children remain, each signals the top fiber and goes back to sleep

```
┌─────────────────────────────────────────────────────────────┐
│  Top-level tasks: strictly sequential                       │
│  ┌──────┐  ┌──────┐  ┌──────┐                              │
│  │Task A│→ │Task B│→ │Task C│  (one at a time, top fiber)  │
│  └──────┘  └──────┘  └──────┘                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  When a task spawns children: scoped concurrency             │
│                                                             │
│  ┌──────────────────────────────────┐                      │
│  │ Parent Task (state: waiting)     │                      │
│  │ Top fiber BLOCKED here           │                      │
│  │                                  │                      │
│  │  ┌───────┐ ┌───────┐ ┌───────┐  │                      │
│  │  │Child 1│ │Child 2│ │Child 3│  │  (parallel on child  │
│  │  │Fiber 1│ │Fiber 2│ │Fiber 3│  │   fibers)            │
│  │  └───────┘ └───────┘ └───────┘  │                      │
│  │              ↓                   │                      │
│  │     All children complete        │                      │
│  │              ↓                   │                      │
│  │     Parent → completed           │                      │
│  │     Top fiber unblocked          │                      │
│  └──────────────────────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

## Uncle Tasks

Sometimes a parent needs to enqueue tasks that should run AFTER it completes, but are NOT children. These are "uncle" tasks:

```sql
-- Inside derive_statistical_unit handler
-- This task runs AFTER parent completes (not as a child)
CALL worker.enqueue_analyze_tables();
```

Uncle tasks:
- Have `parent_id IS NULL` (top-level)
- Are deduplicated via unique indexes
- Run after the parent completes (serial mode resumes)
- Useful for post-processing like ANALYZE

## Example: Statistical Unit Derivation

For the full pipeline diagram, see [derive-pipeline.md](./derive-pipeline.md).

```
1. check_table detects changes → enqueues derive_statistical_unit

2. derive_statistical_unit runs:
   - Computes closed groups of affected enterprises
   - Spawns batch children:
     - statistical_unit_refresh_batch (batch 1)
     - statistical_unit_refresh_batch (batch 2)
     - statistical_unit_refresh_batch (batch 3)
     - ... (N batches of ~1000 enterprises each)
   - Enqueues uncle tasks (run after parent completes):
     - statistical_unit_flush_staging
     - derive_reports (triggers DSH → DSUF → DSHF chain)
   - Handler returns → state becomes 'waiting'

3. Concurrent mode activates:
   - 4 analytics fibers process batch children in parallel
   - Each batch refreshes statistical_unit for a subset of enterprises
   - SKIP LOCKED prevents conflicts

4. All children complete:
   - complete_parent_if_ready() fires
   - Parent state → completed

5. Serial mode resumes:
   - statistical_unit_flush_staging runs (merges staging → main table)
   - derive_reports runs (enqueues derive_statistical_history)
   - derive_statistical_history runs (spawns period children → concurrent)
   - derive_statistical_unit_facet runs (monolithic, no children)
   - derive_statistical_history_facet runs (spawns period children → concurrent)
```

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
- Uncle task runs ANALYZE once after all batches complete
- True parallel execution achieved

## Error Handling

- If any child fails, parent eventually fails (after all children finish)
- `has_failed_siblings()` can be checked by children
- Failed state propagates upward but doesn't interrupt sibling execution

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
| `worker.enforce_no_grandchildren()` | Trigger preventing grandchildren |

## Related Documentation

- [Worker System Architecture](./worker.md)
- [Worker Notifications](./worker-notifications.md)

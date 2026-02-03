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

## Concurrent vs Serial Mode

The `process_tasks` procedure operates in two modes:

### Serial Mode (default)

When no `waiting` parent exists:
- Pick top-level tasks (`parent_id IS NULL`)
- Process one at a time in priority order
- Multiple fibers can still run, but each picks its own top-level task

### Concurrent Mode

When a `waiting` parent exists:
- Pick children of the first waiting parent (by priority)
- Multiple fibers process children in parallel
- `FOR UPDATE SKIP LOCKED` prevents conflicts
- All fibers focus on completing the current parent before moving on

```
┌─────────────────────────────────────────────────────────────┐
│  Serial Mode: No waiting parent                             │
│  ┌──────┐  ┌──────┐  ┌──────┐                              │
│  │Task A│→ │Task B│→ │Task C│  (one at a time)             │
│  └──────┘  └──────┘  └──────┘                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Concurrent Mode: Parent waiting for children               │
│                                                             │
│  ┌──────────────────────────────────┐                      │
│  │ Parent Task (state: waiting)     │                      │
│  │                                  │                      │
│  │  ┌───────┐ ┌───────┐ ┌───────┐  │                      │
│  │  │Child 1│ │Child 2│ │Child 3│  │  (parallel)          │
│  │  │Fiber 1│ │Fiber 2│ │Fiber 3│  │                      │
│  │  └───────┘ └───────┘ └───────┘  │                      │
│  │              ↓                   │                      │
│  │     All children complete        │                      │
│  │              ↓                   │                      │
│  │     Parent → completed           │                      │
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

```
1. Trigger fires → enqueues derive_statistical_unit (priority 10)

2. derive_statistical_unit runs:
   - Computes closed groups of affected enterprises
   - Spawns batch children (priority 20):
     - statistical_unit_refresh_batch (batch 1)
     - statistical_unit_refresh_batch (batch 2)
     - statistical_unit_refresh_batch (batch 3)
   - Enqueues uncle tasks:
     - analyze_tables (runs after completion)
     - derive_reports (runs after completion)
   - Handler returns → state becomes 'waiting'

3. Concurrent mode activates:
   - 4 analytics fibers process batch children in parallel
   - Each batch refreshes a subset of enterprises
   - SKIP LOCKED prevents conflicts

4. All children complete:
   - complete_parent_if_ready() fires
   - Parent state → completed

5. Serial mode resumes:
   - analyze_tables runs (updates statistics)
   - derive_reports runs (generates reports)
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

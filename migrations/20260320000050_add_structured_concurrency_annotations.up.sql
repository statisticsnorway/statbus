-- Migration 20260320000050: add_structured_concurrency_annotations
-- Add COMMENT ON annotations to structured concurrency objects
-- so future readers (human or AI) understand intent from schema introspection.
BEGIN;

-- Enum
COMMENT ON TYPE worker.child_mode IS
'Execution mode for a task''s children.
concurrent: all children may run in parallel (worker pool permitting).
serial: one child at a time in priority order.
Set when first child is spawned; subsequent children must match or error.';

-- Columns on worker.tasks
COMMENT ON COLUMN worker.tasks.child_mode IS
'How this task''s children are processed. concurrent = parallel, serial = one at a time.
NULL = leaf task (no children). Set automatically by spawn() on first child.';

COMMENT ON COLUMN worker.tasks.depth IS
'Task tree depth: 0 = top-level, parent.depth + 1 for children.
Used by process_tasks for depth-first ordering (ORDER BY depth DESC)
so deeper work completes before shallower work resumes.';

COMMENT ON COLUMN worker.tasks.info IS
'Handler output via INOUT p_info jsonb. Each handler reports only what it did (Info Principle).
On parent completion, children''s info is aggregated: numeric values are SUMmed,
non-numeric values take the last child''s value. Parent''s own info overwrites via ||.';

COMMENT ON COLUMN worker.tasks.process_stop_at IS
'When the handler procedure returned (before waiting for children).
For leaf tasks: approximately equals completed_at.
For parent tasks: completed_at > process_stop_at (gap = child execution time).';

COMMENT ON COLUMN worker.tasks.process_duration_ms IS
'Handler execution time only: process_stop_at - process_start_at.
Excludes child execution. For leaf tasks equals completion_duration_ms.';

COMMENT ON COLUMN worker.tasks.completion_duration_ms IS
'Total wall-clock time: completed_at - process_start_at.
For parent tasks includes all child execution (completion_duration_ms - process_duration_ms = child time).';

-- Functions and procedures
COMMENT ON FUNCTION worker.spawn IS
'Create a child task under a parent. Calculates depth from parent, sets parent''s child_mode
on first child (defaults to concurrent), and fails fast if conflicting child_mode specified.
Returns new task ID. Part of the structured concurrency API.';

COMMENT ON PROCEDURE worker.process_tasks IS
'Structured concurrency executor. Picks tasks depth-first with mode-aware ordering.
Serial fiber processes top-level and serial children; concurrent fibers process
parallel children with SKIP LOCKED. Calls complete_parent_if_ready on completion.
Retries on deadlock/serialization failure (optimistic concurrency).';

COMMENT ON FUNCTION worker.complete_parent_if_ready IS
'Check if a parent task can complete (all children done). Aggregates children''s info
(SUM for numerics, last-value for others), marks parent completed or failed,
then recursively checks grandparent. Uses optimistic locking: UPDATE WHERE state=waiting
ensures only one fiber completes the parent in concurrent scenarios.';

COMMENT ON FUNCTION worker.notify_task_progress IS
'Emit pipeline_progress notification for frontend progress bars.
Builds phases array from active task tree: counts completed/total children,
reads effective_*_count from derive_statistical_unit info.
Called after each analytics-queue task completes.';

COMMENT ON FUNCTION worker.rescue_stuck_waiting_parent IS
'Defense-in-depth: finds deepest waiting parent whose children are all done
but was not completed (race condition safety net). Delegates to complete_parent_if_ready.
Should rarely trigger in normal operation.';

END;

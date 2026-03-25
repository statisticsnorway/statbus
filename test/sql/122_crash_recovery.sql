\echo "=== Test: Crash Recovery with Interrupted State ==="
\echo "Verifies: reset_abandoned_processing_tasks sets interrupted (not pending),"
\echo "          dedup constraint coexistence, priority ordering, parent-child,"
\echo "          and cascade-fail all handle the interrupted state correctly."

BEGIN;

-- Lock worker.tasks to prevent background worker interference and ensure deterministic IDs
LOCK TABLE worker.tasks IN EXCLUSIVE MODE;

-- Clean slate: delete non-maintenance tasks, restart sequences
DELETE FROM worker.tasks WHERE parent_id IS NOT NULL;
DELETE FROM worker.tasks WHERE command NOT IN ('task_cleanup', 'import_job_cleanup');
ALTER SEQUENCE worker.tasks_id_seq RESTART WITH 3;

-- Suppress DEBUG noise from process_tasks
SET client_min_messages = warning;

-- ============================================================================
-- Verify prerequisite: 'interrupted' exists in the task_state enum
-- ============================================================================

\echo "=== 0. Verify interrupted state exists in enum ==="
SELECT unnest(enum_range(NULL::worker.task_state)) AS state ORDER BY state;

-- ============================================================================
-- SCENARIO A: Basic reset — orphaned processing task becomes interrupted
-- ============================================================================

\echo "=== Scenario A: Basic reset of orphaned processing task ==="

SAVEPOINT scenario_a;

-- Insert a task in 'processing' state with a dead PID (99999 won't exist)
INSERT INTO worker.tasks (command, payload, state, worker_pid)
VALUES ('derive_statistical_unit', '{}', 'processing', 99999);

\echo "--- A1. Task before reset ---"
SELECT command, state, worker_pid
FROM worker.tasks
WHERE command = 'derive_statistical_unit' AND state = 'processing';

\echo "--- A2. Call reset_abandoned_processing_tasks ---"
SELECT worker.reset_abandoned_processing_tasks() AS reset_count;

\echo "--- A3. Task after reset: should be interrupted, no worker_pid ---"
SELECT command, state, worker_pid IS NULL AS pid_cleared, error IS NULL AS no_error
FROM worker.tasks
WHERE command = 'derive_statistical_unit';

ROLLBACK TO SAVEPOINT scenario_a;

-- ============================================================================
-- SCENARIO B: Dedup conflict — processing + pending collect_changes coexist
-- ============================================================================

\echo "=== Scenario B: Dedup conflict — interrupted coexists with pending ==="

SAVEPOINT scenario_b;

-- 1. Insert an orphaned processing collect_changes (simulating crash)
--    Must bypass the dedup index: only one pending collect_changes allowed,
--    but processing is fine. Use direct state override.
INSERT INTO worker.tasks (command, payload, state, worker_pid)
VALUES ('collect_changes', '{"command":"collect_changes"}', 'processing', 99999);

-- 2. Insert a pending collect_changes (the trigger-created duplicate)
--    This is the one that would conflict if reset tried processing -> pending.
INSERT INTO worker.tasks (command, payload, state)
VALUES ('collect_changes', '{"command":"collect_changes"}', 'pending');

-- 3. Set up crash recovery conditions: has_pending=TRUE, empty change log
UPDATE worker.base_change_log_has_pending SET has_pending = TRUE;
DELETE FROM worker.base_change_log;

\echo "--- B1. Before reset: one processing, one pending ---"
SELECT command, state, worker_pid
FROM worker.tasks
WHERE command = 'collect_changes'
ORDER BY state, id;

\echo "--- B2. Call reset — must NOT error despite dedup constraint ---"
SELECT worker.reset_abandoned_processing_tasks() AS reset_count;

\echo "--- B3. After reset: processing became interrupted, pending unchanged ---"
SELECT command, state, worker_pid IS NULL AS pid_cleared
FROM worker.tasks
WHERE command = 'collect_changes'
ORDER BY state, id;

\echo "--- B4. Both coexist (interrupted + pending) — no constraint violation ---"
SELECT count(*) AS collect_changes_count
FROM worker.tasks
WHERE command = 'collect_changes'
  AND state IN ('interrupted', 'pending');

ROLLBACK TO SAVEPOINT scenario_b;

-- ============================================================================
-- SCENARIO C: Interrupted tasks picked before pending
-- ============================================================================

\echo "=== Scenario C: Interrupted picked before pending ==="

SAVEPOINT scenario_c;

-- Insert task A: interrupted, with a HIGHER priority number (lower urgency)
INSERT INTO worker.tasks (command, payload, state, priority)
VALUES ('derive_statistical_unit', '{}', 'interrupted', 50)
RETURNING id AS task_a_id \gset

-- Insert task B: pending, with a LOWER priority number (higher urgency)
INSERT INTO worker.tasks (command, payload, state, priority)
VALUES ('derive_statistical_unit', '{}', 'pending', 10)
RETURNING id AS task_b_id \gset

\echo "--- C1. Before processing: one interrupted (pri=50), one pending (pri=10) ---"
SELECT id, command, state, priority
FROM worker.tasks
WHERE command = 'derive_statistical_unit'
ORDER BY id;

\echo "--- C2. Process one task — interrupted should be picked first ---"
CALL worker.process_tasks(p_queue => 'analytics', p_batch_size => 1);

\echo "--- C3. Interrupted task (A) was picked (now processing/completed/failed), pending (B) untouched ---"
-- Task A should have been picked (state changed from interrupted)
-- Task B should still be pending
SELECT id,
       command,
       state,
       priority,
       CASE WHEN id = :task_a_id THEN 'A (was interrupted)' ELSE 'B (was pending)' END AS label
FROM worker.tasks
WHERE command = 'derive_statistical_unit'
ORDER BY id;

ROLLBACK TO SAVEPOINT scenario_c;

-- ============================================================================
-- SCENARIO D: Parent with interrupted child
-- ============================================================================

\echo "=== Scenario D: Parent with interrupted child ==="

SAVEPOINT scenario_d;

-- Create a parent task in waiting state (simulating a parent whose children were interrupted by crash)
INSERT INTO worker.tasks (command, payload, state, child_mode)
VALUES ('derive_statistical_unit', '{}', 'waiting', 'concurrent')
RETURNING id AS parent_id \gset

-- Create an interrupted child (simulating crash recovery reset)
INSERT INTO worker.tasks (command, payload, state, parent_id, priority)
VALUES ('statistical_unit_refresh_batch', '{}', 'interrupted', :parent_id, 20)
RETURNING id AS child_id \gset

\echo "--- D1. has_pending_children should return TRUE for interrupted child ---"
SELECT worker.has_pending_children(:parent_id) AS has_pending;

\echo "--- D2. Process tasks — should pick up the interrupted child ---"
CALL worker.process_tasks(p_queue => 'analytics', p_batch_size => 1);

\echo "--- D3. Child should have been processed, parent should auto-complete ---"
SELECT id,
       command,
       state,
       CASE WHEN id = :parent_id THEN 'parent' ELSE 'child' END AS role
FROM worker.tasks
WHERE id IN (:parent_id, :child_id)
ORDER BY id;

ROLLBACK TO SAVEPOINT scenario_d;

-- ============================================================================
-- SCENARIO E: Cascade fail includes interrupted descendants
-- ============================================================================

\echo "=== Scenario E: Cascade fail includes interrupted ==="

SAVEPOINT scenario_e;

-- Create a failed parent
INSERT INTO worker.tasks (command, payload, state, error, completed_at)
VALUES ('derive_statistical_unit', '{}', 'failed', 'Simulated failure', now())
RETURNING id AS fail_parent_id \gset

-- Create an interrupted child of the failed parent
INSERT INTO worker.tasks (command, payload, state, parent_id)
VALUES ('statistical_unit_refresh_batch', '{}', 'interrupted', :fail_parent_id)
RETURNING id AS fail_child_id \gset

-- Create a pending child too, to verify both are cascade-failed
INSERT INTO worker.tasks (command, payload, state, parent_id)
VALUES ('statistical_unit_refresh_batch', '{}', 'pending', :fail_parent_id)
RETURNING id AS fail_child2_id \gset

\echo "--- E1. Before cascade: parent failed, children interrupted + pending ---"
SELECT id,
       command,
       state,
       CASE WHEN id = :fail_parent_id THEN 'parent'
            WHEN id = :fail_child_id THEN 'child (interrupted)'
            ELSE 'child (pending)' END AS role
FROM worker.tasks
WHERE id IN (:fail_parent_id, :fail_child_id, :fail_child2_id)
ORDER BY id;

\echo "--- E2. Cascade fail descendants ---"
SELECT worker.cascade_fail_descendants(:fail_parent_id);

\echo "--- E3. After cascade: both children should be failed ---"
SELECT id,
       command,
       state,
       error,
       CASE WHEN id = :fail_parent_id THEN 'parent'
            WHEN id = :fail_child_id THEN 'child (was interrupted)'
            ELSE 'child (was pending)' END AS role
FROM worker.tasks
WHERE id IN (:fail_parent_id, :fail_child_id, :fail_child2_id)
ORDER BY id;

ROLLBACK TO SAVEPOINT scenario_e;

-- ============================================================================
-- Clean up
-- ============================================================================

-- Restore base_change_log_has_pending to clean state
UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;

ROLLBACK;

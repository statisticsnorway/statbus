\echo "=== Test: Worker Structured Concurrency ==="
\echo "Verifies parent-child task relationships, waiting state, and automatic completion"

BEGIN;

-- Clean up any existing test tasks and reset sequence for deterministic IDs in error messages
DELETE FROM worker.tasks WHERE command IN ('derive_statistical_unit', 'statistical_unit_refresh_batch', 'derive_reports');
-- Reset sequence to get predictable task IDs (3 onwards, since 1 and 2 are maintenance tasks)
ALTER SEQUENCE worker.tasks_id_seq RESTART WITH 3;

\echo "=== 1. Verify task_state enum includes 'waiting' ==="
SELECT unnest(enum_range(NULL::worker.task_state)) AS state ORDER BY state;

\echo "=== 2. Verify tasks table has required columns ==="
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'worker' AND table_name = 'tasks' 
  AND column_name IN ('parent_id', 'completed_at')
ORDER BY column_name;

\echo "=== 3. Verify structured concurrency functions exist ==="
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'worker' 
  AND routine_name IN ('spawn', 'has_pending_children', 'has_failed_siblings', 'complete_parent_if_ready', 'enforce_no_grandchildren')
ORDER BY routine_name;

\echo "=== 4. Verify no-grandchildren trigger exists ==="
SELECT tgname, tgtype, tgenabled
FROM pg_trigger
WHERE tgname = 'tasks_enforce_no_grandchildren';

\echo "=== 5. Test spawn function creates parent-child relationship ==="
-- Create a parent task
INSERT INTO worker.tasks (command, payload, state)
VALUES ('derive_statistical_unit', '{}', 'processing')
RETURNING id AS parent_task_id \gset

-- Spawn a child task using the spawn function
SELECT worker.spawn(
    p_command := 'statistical_unit_refresh_batch',
    p_payload := '{"batch_seq": 1}'::jsonb,
    p_parent_id := :parent_task_id,
    p_priority := 20
) AS child_task_id \gset

-- Verify child has correct parent relationship (not specific IDs)
SELECT 
    command,
    parent_id = :parent_task_id AS has_correct_parent,
    priority,
    state
FROM worker.tasks
WHERE id = :child_task_id;

\echo "=== 6. Test has_pending_children function ==="
-- Parent should have pending children
SELECT worker.has_pending_children(:parent_task_id) AS has_pending;

-- Mark child as completed
UPDATE worker.tasks SET state = 'completed', completed_at = now() WHERE id = :child_task_id;

-- Now parent should NOT have pending children
SELECT worker.has_pending_children(:parent_task_id) AS has_pending_after_complete;

\echo "=== 7. Test complete_parent_if_ready function ==="
-- Set parent to waiting state (simulating what process_tasks does)
UPDATE worker.tasks SET state = 'waiting' WHERE id = :parent_task_id;

-- Call complete_parent_if_ready - should complete the parent
SELECT worker.complete_parent_if_ready(:child_task_id) AS parent_completed;

-- Verify parent is now completed
SELECT command, state, completed_at IS NOT NULL AS has_completed_at
FROM worker.tasks
WHERE id = :parent_task_id;

\echo "=== 8. Test grandchildren prevention trigger ==="
-- Create a new parent and child
INSERT INTO worker.tasks (command, payload, state)
VALUES ('derive_statistical_unit', '{}', 'waiting')
RETURNING id AS new_parent_id \gset

INSERT INTO worker.tasks (command, payload, parent_id, state)
VALUES ('statistical_unit_refresh_batch', '{}', :new_parent_id, 'processing')
RETURNING id AS new_child_id \gset

-- Attempt to create a grandchild (should fail with specific error message)
SAVEPOINT before_grandchild;
\set ON_ERROR_STOP off
INSERT INTO worker.tasks (command, payload, parent_id, state)
VALUES ('statistical_unit_refresh_batch', '{"nested": true}', :new_child_id, 'pending');
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_grandchild;

\echo "=== 9. Test sibling spawning (child can spawn siblings with same parent) ==="
-- Child should be able to spawn a sibling (same parent_id)
SELECT worker.spawn(
    p_command := 'statistical_unit_refresh_batch',
    p_payload := '{"batch_seq": 2, "spawned_by_sibling": true}'::jsonb,
    p_parent_id := :new_parent_id,
    p_priority := 20
) AS sibling_task_id \gset

-- Verify sibling exists with correct parent (not specific IDs)
SELECT 
    command,
    parent_id = :new_parent_id AS has_same_parent,
    payload->>'spawned_by_sibling' AS spawned_by_sibling
FROM worker.tasks
WHERE id = :sibling_task_id;

\echo "=== 10. Test uncle spawning (child can spawn top-level task) ==="
-- Child should be able to spawn an "uncle" (parent_id = NULL)
SELECT worker.spawn(
    p_command := 'derive_reports',
    p_payload := '{}'::jsonb,
    p_parent_id := NULL,
    p_priority := 30
) AS uncle_task_id \gset

-- Verify uncle is top-level
SELECT command, parent_id IS NULL AS is_top_level, priority
FROM worker.tasks
WHERE id = :uncle_task_id;

\echo "=== 11. Test has_failed_siblings function ==="
-- Create another child and mark it as failed
INSERT INTO worker.tasks (command, payload, parent_id, state, completed_at, error)
VALUES ('statistical_unit_refresh_batch', '{"will_fail": true}', :new_parent_id, 'failed', now(), 'Test failure')
RETURNING id AS failed_child_id \gset

-- Check if siblings detect the failure
SELECT worker.has_failed_siblings(:sibling_task_id) AS has_failed_sibling;

\echo "=== 12. Test parent fails when child fails ==="
-- Mark all pending children as completed
UPDATE worker.tasks 
SET state = 'completed', completed_at = now() 
WHERE parent_id = :new_parent_id AND state = 'pending';

-- Complete the processing child
UPDATE worker.tasks 
SET state = 'completed', completed_at = now() 
WHERE id = :new_child_id;

-- Now call complete_parent_if_ready - parent should FAIL because one child failed
SELECT worker.complete_parent_if_ready(:new_child_id) AS triggered_parent_completion;

-- Verify parent is failed
SELECT command, state, error
FROM worker.tasks
WHERE id = :new_parent_id;

\echo "=== 13. Summary of task relationships created (excluding maintenance) ==="
SELECT 
    command,
    state,
    CASE 
        WHEN parent_id IS NULL THEN 'root'
        ELSE 'child'
    END AS task_type,
    (SELECT COUNT(*) FROM worker.tasks c WHERE c.parent_id = t.id) AS child_count
FROM worker.tasks t
WHERE command NOT IN ('task_cleanup', 'import_job_cleanup')
ORDER BY 
    CASE command 
        WHEN 'derive_statistical_unit' THEN 1
        WHEN 'statistical_unit_refresh_batch' THEN 2
        WHEN 'derive_reports' THEN 3
    END,
    state,
    task_type;

-- ============================================================================
-- INTEGRATION TESTS: process_tasks with parent-child relationships
-- ============================================================================

\echo "=== 14. Test process_tasks: parent transitions to waiting when children spawned ==="
-- Clean slate for integration tests
DELETE FROM worker.tasks WHERE id > 2;
ALTER SEQUENCE worker.tasks_id_seq RESTART WITH 3;

-- Create a parent task that will spawn children
INSERT INTO worker.tasks (command, payload, state)
VALUES ('derive_statistical_unit', '{}', 'pending')
RETURNING id AS int_parent_id \gset

-- Manually spawn children (simulating what the handler would do)
INSERT INTO worker.tasks (command, payload, parent_id, state)
VALUES 
    ('statistical_unit_refresh_batch', '{"batch": 1}', :int_parent_id, 'pending'),
    ('statistical_unit_refresh_batch', '{"batch": 2}', :int_parent_id, 'pending');

-- Simulate process_tasks picking the parent: mark it processing
UPDATE worker.tasks SET state = 'processing', worker_pid = pg_backend_pid() WHERE id = :int_parent_id;

-- After handler runs and we detect children exist, parent should go to waiting
-- (This is what process_tasks does internally)
UPDATE worker.tasks 
SET state = 'waiting', processed_at = now()
WHERE id = :int_parent_id;

-- Verify parent is now waiting with 2 pending children
SELECT 
    (SELECT state FROM worker.tasks WHERE id = :int_parent_id) AS parent_state,
    (SELECT COUNT(*) FROM worker.tasks WHERE parent_id = :int_parent_id AND state = 'pending') AS pending_children;

\echo "=== 15. Test process_tasks: concurrent mode picks children of waiting parent ==="
-- When there's a waiting parent, process_tasks should pick its children
-- Simulate picking first child (use subquery since UPDATE doesn't support LIMIT)
UPDATE worker.tasks 
SET state = 'processing', worker_pid = pg_backend_pid()
WHERE id = (
    SELECT id FROM worker.tasks 
    WHERE parent_id = :int_parent_id AND state = 'pending' 
    ORDER BY id LIMIT 1
);

-- Verify one child is processing
SELECT 
    (SELECT COUNT(*) FROM worker.tasks WHERE parent_id = :int_parent_id AND state = 'processing') AS processing_children,
    (SELECT COUNT(*) FROM worker.tasks WHERE parent_id = :int_parent_id AND state = 'pending') AS pending_children;

\echo "=== 16. Test process_tasks: completing children triggers parent completion ==="
-- Complete both children
UPDATE worker.tasks 
SET state = 'completed', completed_at = now()
WHERE parent_id = :int_parent_id;

-- Call complete_parent_if_ready (this is what process_tasks calls after each child completes)
SELECT worker.complete_parent_if_ready(
    (SELECT id FROM worker.tasks WHERE parent_id = :int_parent_id LIMIT 1)
) AS parent_completed;

-- Verify parent is now completed
SELECT state, completed_at IS NOT NULL AS has_completed_at
FROM worker.tasks 
WHERE id = :int_parent_id;

\echo "=== 17. Test process_tasks: serial mode when no waiting parent ==="
-- Create a top-level task (no waiting parents exist)
INSERT INTO worker.tasks (command, payload, state)
VALUES ('derive_reports', '{}', 'pending')
RETURNING id AS serial_task_id \gset

-- Verify there's no waiting parent
SELECT COUNT(*) AS waiting_parents FROM worker.tasks WHERE state = 'waiting';

-- In serial mode, process_tasks would pick this top-level pending task
SELECT command, state, parent_id IS NULL AS is_top_level
FROM worker.tasks
WHERE id = :serial_task_id;

\echo "=== 18. Final state summary ==="
SELECT 
    command,
    state,
    CASE WHEN parent_id IS NULL THEN 'root' ELSE 'child' END AS task_type
FROM worker.tasks
WHERE command NOT IN ('task_cleanup', 'import_job_cleanup')
ORDER BY id;

ROLLBACK;

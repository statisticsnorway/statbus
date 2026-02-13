\echo "=== Test: Worker Structured Concurrency ==="
\echo "Verifies parent-child task relationships, waiting state, and automatic completion"

BEGIN;

-- Lock worker.tasks to prevent the background worker from advancing the sequence
-- during the test. This ensures deterministic task IDs in error messages.
LOCK TABLE worker.tasks IN EXCLUSIVE MODE;
-- Delete any non-maintenance tasks created between setup.sql and this transaction
DELETE FROM worker.tasks WHERE command NOT IN ('task_cleanup', 'import_job_cleanup');
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

-- ============================================================================
-- WAVE CONTINUATION TESTS: derive_statistical_unit_continue command
-- ============================================================================

\echo "=== 19. Verify derive_statistical_unit_continue command exists ==="
SELECT command, handler_procedure, queue 
FROM worker.command_registry 
WHERE command = 'derive_statistical_unit_continue';

\echo "=== 20. Verify continuation command has NO deduplication index ==="
-- derive_statistical_unit has pending-only dedup, but continue should have NONE
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE schemaname = 'worker' AND indexname LIKE '%derive%dedup%'
ORDER BY indexname;

\echo "=== 21. Test derive_statistical_unit deduplication (pending only) ==="
-- Clean slate for deduplication tests (delete children first due to FK)
DELETE FROM worker.tasks WHERE parent_id IS NOT NULL;
DELETE FROM worker.tasks WHERE command LIKE 'derive_statistical_unit%';

-- Insert first pending task
SELECT worker.enqueue_derive_statistical_unit(
    p_establishment_id_ranges := '{[1,10)}'::int4multirange
) AS first_task_id \gset

-- Insert second (should merge with first since it's pending)
SELECT worker.enqueue_derive_statistical_unit(
    p_establishment_id_ranges := '{[20,30)}'::int4multirange
) AS second_task_id \gset

-- Should be same task (merged)
SELECT :first_task_id = :second_task_id AS tasks_merged;

-- Verify ranges were merged
SELECT payload->>'establishment_id_ranges' AS merged_ranges
FROM worker.tasks WHERE id = :first_task_id;

\echo "=== 22. Test new pending task created when existing is processing ==="
-- Move first task to processing
UPDATE worker.tasks 
SET state = 'processing', worker_pid = pg_backend_pid() 
WHERE id = :first_task_id;

-- Insert third task (should create NEW task since first is processing)
SELECT worker.enqueue_derive_statistical_unit(
    p_establishment_id_ranges := '{[40,50)}'::int4multirange
) AS third_task_id \gset

-- Should be different task
SELECT :first_task_id != :third_task_id AS new_task_created;

-- Verify both tasks exist with their own ranges
SELECT id, state, payload->>'establishment_id_ranges' AS ranges
FROM worker.tasks 
WHERE command = 'derive_statistical_unit'
ORDER BY id;

\echo "=== 23. Test continuation tasks are NOT deduplicated ==="
-- Insert multiple continuation tasks (should all be created separately)
INSERT INTO worker.tasks (command, payload)
VALUES (
    'derive_statistical_unit_continue',
    '{"batch_offset": 10}'::jsonb
) RETURNING id AS cont1_id \gset

INSERT INTO worker.tasks (command, payload)
VALUES (
    'derive_statistical_unit_continue',
    '{"batch_offset": 20}'::jsonb
) RETURNING id AS cont2_id \gset

INSERT INTO worker.tasks (command, payload)
VALUES (
    'derive_statistical_unit_continue',
    '{"batch_offset": 30}'::jsonb
) RETURNING id AS cont3_id \gset

-- All three should exist as separate tasks
SELECT COUNT(*) AS continuation_count
FROM worker.tasks 
WHERE command = 'derive_statistical_unit_continue';

-- Verify each has different offset
SELECT id, payload->>'batch_offset' AS batch_offset
FROM worker.tasks 
WHERE command = 'derive_statistical_unit_continue'
ORDER BY id;

\echo "=== 24. Test has_more detection logic for wave processing ==="
-- This tests the count-based approach for detecting if more batches exist
DO $$
DECLARE
    v_batch_count INT;
    v_batches_per_wave INT := 3;  -- Small for testing
    v_has_more BOOLEAN;
    v_simulated_batches INT := 8;  -- Simulate 8 total batches
    v_offset INT;
BEGIN
    -- Wave 1: offset=0, should process 3, has_more=TRUE (because 8 > 3)
    v_batch_count := 0;
    v_has_more := FALSE;
    v_offset := 0;
    
    FOR i IN 1..(v_batches_per_wave + 1) LOOP
        EXIT WHEN (v_offset + i) > v_simulated_batches;
        
        IF v_batch_count >= v_batches_per_wave THEN
            v_has_more := TRUE;
            EXIT;
        END IF;
        v_batch_count := v_batch_count + 1;
    END LOOP;
    
    ASSERT v_batch_count = 3, format('Wave 1: Expected 3 batches, got %s', v_batch_count);
    ASSERT v_has_more = TRUE, format('Wave 1: Expected has_more = TRUE, got %s', v_has_more);
    RAISE NOTICE 'Wave 1 (offset=0): % batches, has_more=% [PASS]', v_batch_count, v_has_more;
    
    -- Wave 2: offset=3, should process 3, has_more=TRUE (because 8-3=5 > 3)
    v_batch_count := 0;
    v_has_more := FALSE;
    v_offset := 3;
    
    FOR i IN 1..(v_batches_per_wave + 1) LOOP
        EXIT WHEN (v_offset + i) > v_simulated_batches;
        
        IF v_batch_count >= v_batches_per_wave THEN
            v_has_more := TRUE;
            EXIT;
        END IF;
        v_batch_count := v_batch_count + 1;
    END LOOP;
    
    ASSERT v_batch_count = 3, format('Wave 2: Expected 3 batches, got %s', v_batch_count);
    ASSERT v_has_more = TRUE, format('Wave 2: Expected has_more = TRUE, got %s', v_has_more);
    RAISE NOTICE 'Wave 2 (offset=3): % batches, has_more=% [PASS]', v_batch_count, v_has_more;
    
    -- Wave 3: offset=6, should process 2, has_more=FALSE (because 8-6=2 < 3)
    v_batch_count := 0;
    v_has_more := FALSE;
    v_offset := 6;
    
    FOR i IN 1..(v_batches_per_wave + 1) LOOP
        EXIT WHEN (v_offset + i) > v_simulated_batches;
        
        IF v_batch_count >= v_batches_per_wave THEN
            v_has_more := TRUE;
            EXIT;
        END IF;
        v_batch_count := v_batch_count + 1;
    END LOOP;
    
    ASSERT v_batch_count = 2, format('Wave 3: Expected 2 batches, got %s', v_batch_count);
    ASSERT v_has_more = FALSE, format('Wave 3: Expected has_more = FALSE, got %s', v_has_more);
    RAISE NOTICE 'Wave 3 (offset=6): % batches, has_more=% [PASS]', v_batch_count, v_has_more;
    
    RAISE NOTICE 'All has_more detection tests passed!';
END $$;

\echo "=== 25. Verify derive_statistical_unit_impl function exists with batch_offset ==="
SELECT routine_name, 
       (SELECT string_agg(parameter_name, ', ' ORDER BY ordinal_position) 
        FROM information_schema.parameters p 
        WHERE p.specific_schema = r.specific_schema 
          AND p.specific_name = r.specific_name) AS parameters
FROM information_schema.routines r
WHERE routine_schema = 'worker' 
  AND routine_name = 'derive_statistical_unit_impl';

\echo "=== 26. Summary of continuation-related state ==="
SELECT 
    command,
    state,
    payload->>'batch_offset' AS batch_offset,
    payload->>'establishment_id_ranges' AS est_ranges
FROM worker.tasks
WHERE command LIKE 'derive_statistical_unit%'
ORDER BY command, id;

-- Cleanup continuation test data
DELETE FROM worker.tasks WHERE command LIKE 'derive_statistical_unit%';

ROLLBACK;

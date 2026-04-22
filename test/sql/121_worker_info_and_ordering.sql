\echo "=== Test: Worker Info (INOUT protocol) and Serial Ordering ==="
\echo "Verifies: (1) info populated via INOUT after handlers complete,"
\echo "          (2) serial child ordering without round_priority_base,"
\echo "          (3) info bubble-up from children to parent,"
\echo "          (4) ELSE branch sets zero counts when no changes exist."

BEGIN;

-- Lock worker.tasks to prevent background worker interference and ensure deterministic IDs
LOCK TABLE worker.tasks IN EXCLUSIVE MODE;

-- Clean slate: delete non-maintenance tasks, pending maintenance stubs, restart sequences
DELETE FROM worker.tasks WHERE parent_id IS NOT NULL;
DELETE FROM worker.tasks WHERE command NOT IN ('task_cleanup', 'import_job_cleanup');
DELETE FROM worker.tasks WHERE state = 'pending';
ALTER SEQUENCE worker.tasks_id_seq RESTART WITH 3;

-- Suppress DEBUG noise
SET client_min_messages = warning;

-- ============================================================================
-- PART 1: Inject a change and process collect_changes
-- ============================================================================

\echo "=== 1. Inject a synthetic change into base_change_log ==="

-- Insert a change directly into base_change_log (simulating a trigger firing)
-- We use legal_unit_id=1 as a placeholder; collect_changes aggregates these.
INSERT INTO worker.base_change_log (legal_unit_ids, enterprise_ids, establishment_ids, power_group_ids, valid_ranges)
VALUES (
    '{[1,2)}'::int4multirange,
    '{[1,2)}'::int4multirange,
    '{}'::int4multirange,
    '{}'::int4multirange,
    '{}'::datemultirange
);
UPDATE worker.base_change_log_has_pending SET has_pending = TRUE;

-- Create collect_changes task manually (trigger would do this, but we're in a test)
INSERT INTO worker.tasks (command, payload, state)
VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb, 'pending');

\echo "=== 2. Process collect_changes task ==="

-- Process one task: this will run command_collect_changes handler
CALL worker.process_tasks(p_queue => 'analytics', p_batch_size => 1);

\echo "=== 3. Verify collect_changes info has affected counts ==="

-- The handler should have set info via INOUT with non-null affected_*_count keys
SELECT
    command,
    state,
    info ? 'affected_legal_unit_count' AS has_lu_count_key,
    info ? 'affected_enterprise_count' AS has_ent_count_key,
    info ? 'affected_establishment_count' AS has_est_count_key,
    info ? 'affected_power_group_count' AS has_pg_count_key,
    (info->>'affected_legal_unit_count')::int > 0 AS lu_count_positive,
    (info->>'affected_enterprise_count')::int > 0 AS ent_count_positive
FROM worker.tasks
WHERE command = 'collect_changes'
ORDER BY id DESC LIMIT 1;

-- ============================================================================
-- PART 2: Verify task tree structure and serial ordering
-- ============================================================================

\echo "=== 4. Verify task tree: collect_changes spawned phase children ==="

-- collect_changes should be in 'waiting' state with serial children
SELECT command, state, child_mode
FROM worker.tasks
WHERE command = 'collect_changes'
ORDER BY id DESC LIMIT 1;

\echo "=== 5. Verify phase ordering: derive_units_phase before derive_reports_phase ==="

-- In serial mode, children are processed by priority ASC, id ASC.
-- Since spawn() uses nextval() for priority (no round_priority_base),
-- children spawned first get lower priority numbers.
SELECT
    t.command,
    t.state,
    t.depth,
    -- Show relative ordering: derive_units_phase should have lower priority than derive_reports_phase
    CASE
        WHEN t.command = 'derive_units_phase' THEN 'phase1'
        WHEN t.command = 'derive_reports_phase' THEN 'phase2'
    END AS phase_label,
    t.priority < (
        SELECT t2.priority FROM worker.tasks AS t2
        WHERE t2.command = 'derive_reports_phase'
          AND t2.parent_id = t.parent_id
    ) AS ordered_before_phase2
FROM worker.tasks AS t
WHERE t.command IN ('derive_units_phase', 'derive_reports_phase')
  AND t.parent_id = (SELECT id FROM worker.tasks WHERE command = 'collect_changes' ORDER BY id DESC LIMIT 1)
ORDER BY t.priority, t.id;

\echo "=== 6. Verify serial children of derive_units_phase ==="

-- derive_units_phase should have serial children:
-- derive_statistical_unit, then statistical_unit_flush_staging
SELECT
    child.command,
    child.state,
    child.depth
FROM worker.tasks AS child
WHERE child.parent_id = (
    SELECT id FROM worker.tasks
    WHERE command = 'derive_units_phase'
    ORDER BY id DESC LIMIT 1
)
ORDER BY child.priority, child.id;

\echo "=== 7. Verify serial children of derive_reports_phase ==="

-- derive_reports_phase should have serial children in order:
-- derive_statistical_history, statistical_history_reduce,
-- derive_statistical_unit_facet, statistical_unit_facet_reduce,
-- derive_statistical_history_facet, statistical_history_facet_reduce
SELECT
    child.command,
    child.state,
    child.depth
FROM worker.tasks AS child
WHERE child.parent_id = (
    SELECT id FROM worker.tasks
    WHERE command = 'derive_reports_phase'
    ORDER BY id DESC LIMIT 1
)
ORDER BY child.priority, child.id;

-- ============================================================================
-- PART 3: Process remaining tasks and verify info propagation
-- ============================================================================

\echo "=== 8. Process all remaining analytics tasks ==="

-- Process all remaining tasks to completion
CALL worker.process_tasks(p_queue => 'analytics');

\echo "=== 9. Verify all tasks completed ==="

-- All tasks should be completed (no pending or failed)
SELECT state, count(*) AS cnt
FROM worker.tasks
WHERE command NOT IN ('task_cleanup', 'import_job_cleanup')
GROUP BY state
ORDER BY state;

\echo "=== 10. Verify info bubbled up to collect_changes ==="

-- After all children complete, complete_parent_if_ready aggregates children's info.
-- collect_changes should have its own info keys plus bubbled-up children info.
-- The key check: info is not NULL and has the affected_*_count keys from the handler,
-- plus effective_*_count keys bubbled up from derive_statistical_unit children.
SELECT
    command,
    info IS NOT NULL AS has_info,
    info ? 'affected_legal_unit_count' AS has_lu_count,
    info ? 'affected_enterprise_count' AS has_ent_count,
    -- Verify new keys bubbled up from children (Info Principle)
    info ? 'effective_legal_unit_count' AS has_eff_lu,
    info ? 'effective_enterprise_count' AS has_eff_en,
    info ? 'rows_reduced' AS has_rows_reduced
FROM worker.tasks
WHERE command = 'collect_changes'
ORDER BY id DESC LIMIT 1;

-- ============================================================================
-- PART 4: ELSE branch - no changes produces zero counts
-- ============================================================================

\echo "=== 11. Clean up and test ELSE branch (no pending changes) ==="

-- Clean slate
DELETE FROM worker.tasks WHERE parent_id IS NOT NULL;
DELETE FROM worker.tasks WHERE command NOT IN ('task_cleanup', 'import_job_cleanup');
ALTER SEQUENCE worker.tasks_id_seq RESTART WITH 100;

-- Ensure base_change_log is empty (no pending changes)
DELETE FROM worker.base_change_log;
UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;

-- Create collect_changes task with no changes to collect
INSERT INTO worker.tasks (command, payload, state)
VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb, 'pending');

\echo "=== 12. Process collect_changes with no changes ==="

CALL worker.process_tasks(p_queue => 'analytics', p_batch_size => 1);

\echo "=== 13. Verify ELSE branch: info has zero counts ==="

-- When no changes exist, collect_changes should still set info with zero counts
-- and complete immediately (no children spawned).
SELECT
    command,
    state,
    (info->>'affected_establishment_count')::int AS est_count,
    (info->>'affected_legal_unit_count')::int AS lu_count,
    (info->>'affected_enterprise_count')::int AS ent_count,
    (info->>'affected_power_group_count')::int AS pg_count
FROM worker.tasks
WHERE command = 'collect_changes'
ORDER BY id DESC LIMIT 1;

\echo "=== 14. Verify no children spawned for empty change set ==="

-- No children should exist (ELSE branch does not spawn phases)
SELECT count(*) AS child_count
FROM worker.tasks
WHERE parent_id = (
    SELECT id FROM worker.tasks
    WHERE command = 'collect_changes'
    ORDER BY id DESC LIMIT 1
);

ROLLBACK;

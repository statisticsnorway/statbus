-- =============================================================================
-- Test Suite: `import.temporal_merge` (Single Key)
--
-- Description:
--   This test suite provides comprehensive validation for the unified
--   `temporal_merge_plan` and `temporal_merge` functions for entities with
--   a single-column primary key.
--
-- Table of Contents:
--   - Setup
--   - Scenario 1: Initial Data Load (Empty Target)
--   - Scenarios for `upsert_patch` mode (Allen's Interval Algebra)
--     - Scenario 2: `starts`
--     - Scenario 3: `finishes`
--     - Scenario 4: `during` / `contains`
--     - Scenario 5: `overlaps`
--     - Scenario 6: `overlapped by`
--     - Scenario 7: `meets`
--     - Scenario 8: `met by`
--     - Scenario 9: `before`
--     - Scenario 10: `after`
--     - Scenario 11: `equals`
--   - Scenarios for `upsert_replace` mode
--     - Scenario 12: `starts`
--     - Scenario 13: `finishes`
--     - Scenario 14: `during` / `contains`
--     - Scenario 15: `overlaps`
--     - Scenario 16: `equals`
--     - Scenario 17: `replace` with NULL source value
--   - Scenarios for `_only` modes (NOOP behavior)
--     - Scenario 18: `patch_only` on non-existent entity
--     - Scenario 19: `replace_only` on non-existent entity
--   - Scenarios for NULL handling in `patch` mode
--     - Scenario 20: `upsert_patch` with NULL source value
--     - Scenario 21: `patch_only` with NULL source value
--   - Scenarios for Ephemeral Columns
--     - Scenario 22: `equals` with different ephemeral data
--     - Scenario 23: `equals` with identical data (should be NOOP)
--   - Scenarios for Multi-Row Source Data
--     - Scenario 24: Multiple disjoint source rows
--     - Scenario 25: Multiple overlapping source rows
--     - Scenario 26: Multiple source rows creating a hole
--   - Scenarios for `sql_saga` Integration
--     - Scenario 27: `starts` with deferred foreign key
--   - Scenarios for `insert_defaulted_columns`
--     - Scenario 28: Initial INSERT with default columns
--   - Scenarios for SAVEPOINT and Transactional Correctness
--     - Scenario 29: Test `meets` relation
--     - Scenario 30: Test `starts` relation
--     - Scenario 31: Test `during` relation
--     - Scenario 32: Test `overlaps` relation
--     - Scenario 33: Test `finishes` relation
--     - Scenario 34: Test `equals` relation
--   - Scenarios for Batch-Level Feedback
--     - Scenario 35: `patch_only` with mixed valid/invalid entities
--   - Scenarios for Merging and Coalescing
--     - Scenario 36: `upsert_patch` with two consecutive, identical source rows
--     - Scenario 37: `upsert_patch` with three consecutive, identical source rows
--     - Scenario 38: `upsert_patch` with two consecutive but DIFFERENT source rows
--     - Scenario 39: `upsert_patch` where source row is consecutive with existing target row
--   - Scenarios for `insert_defaulted_columns`
--     - Scenario 40: `INSERT` with `created_at` defaulted
--   - Final Cleanup
-- =============================================================================

BEGIN;
SET client_min_messages TO WARNING;

-- Test schema
CREATE SCHEMA set_test_merge;

-- Sequences for auto-generated IDs
CREATE SEQUENCE set_test_merge.legal_unit_id_seq;
CREATE SEQUENCE set_test_merge.establishment_id_seq;

-- Target tables (simplified versions for testing)
CREATE TABLE set_test_merge.legal_unit (
    id INT PRIMARY KEY,
    name TEXT
);

CREATE TABLE set_test_merge.establishment (
    id INT NOT NULL,
    legal_unit_id INT NOT NULL,
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    name TEXT,
    employees INT,
    edit_comment TEXT,
    PRIMARY KEY (id, valid_after)
);

-- Helper procedure to reset target table state between scenarios
CREATE PROCEDURE set_test_merge.reset_target() LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE set_test_merge.establishment;
    TRUNCATE set_test_merge.legal_unit;
    -- Seed with a legal unit for FK constraints
    INSERT INTO set_test_merge.legal_unit (id, name) VALUES (1, 'Test LU');
    ALTER SEQUENCE set_test_merge.establishment_id_seq RESTART WITH 1;
END;
$$;

-- psql variables for the test
\set target_schema 'set_test_merge'
\set target_table 'establishment'
\set source_schema 'pg_temp'
\set entity_id_cols '{id}'

\set ephemeral_cols '{edit_comment}'

--------------------------------------------------------------------------------
-- Scenarios for UPSERT_PATCH (`insert_or_update`)
--------------------------------------------------------------------------------
\echo '================================================================================'
\echo 'Begin Scenarios for UPSERT_PATCH mode'
\echo '================================================================================'

--------------------------------------------------------------------------------
\echo 'Scenario 1: Initial Insert of a new entity'
\echo 'Mode: upsert_patch'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
CREATE TEMP TABLE temp_source_1 (
    row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source_1 VALUES (101, 1, nextval('set_test_merge.establishment_id_seq'), '2023-12-31', '2024-12-31', 'New EST', 10, 'Initial Insert');

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_1 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_1
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_1',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{101}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "New EST", "employees": 10, "edit_comment": "Initial Insert", "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (101, '[{"id": 1}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_1;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (1, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'New EST'::TEXT, 10, 'Initial Insert'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_merge.establishment WHERE id = 1 ORDER BY valid_after;

DROP TABLE temp_source_1;

--------------------------------------------------------------------------------
\echo 'Scenario 2: `upsert_patch` with `starts` relation'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (2, 1, '2023-12-31', '2025-12-31', 'Original', 20, 'Original slice');
CREATE TEMP TABLE temp_source_2 ( row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source_2 VALUES (102, 2, 1, '2023-12-31', '2024-12-31', 'Patched', 25, 'Starts patch');

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_2 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_2
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_2',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{102}'::INT[], 'UPDATE'::import.plan_operation_type, 2, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "Patched", "employees": 25, "legal_unit_id": 1, "edit_comment": "Starts patch"}'::JSONB, 'starts'::public.allen_interval_relation),
    (2, '{102}'::INT[], 'INSERT'::import.plan_operation_type, 2, NULL::DATE,         '2024-12-31'::DATE, '2025-12-31'::DATE, '{"name": "Original", "employees": 20, "legal_unit_id": 1, "edit_comment": "Original slice"}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (102, '[{"id": 2}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_2;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (2, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'Patched', 25, 'Starts patch'),
    (2, 1, '2024-12-31'::DATE, '2025-12-31'::DATE, 'Original', 20, 'Original slice')
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_merge.establishment WHERE id = 2 ORDER BY valid_after;
DROP TABLE temp_source_2;

--------------------------------------------------------------------------------
\echo 'Scenario 3: `upsert_patch` with `finishes` relation'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES (3, 1, '2023-12-31', '2025-12-31', 'Original', 30);
CREATE TEMP TABLE temp_source_3 ( row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT) ON COMMIT DROP;
INSERT INTO temp_source_3 VALUES (103, 3, 1, '2024-12-31', '2025-12-31', 'Patched', 35);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_3 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_3
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_3',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{103}'::INT[], 'UPDATE'::import.plan_operation_type, 3, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "Original", "employees": 30, "legal_unit_id": 1}'::JSONB, 'starts'::public.allen_interval_relation),
    (2, '{103}'::INT[], 'INSERT'::import.plan_operation_type, 3, NULL::DATE, '2024-12-31'::DATE, '2025-12-31'::DATE, '{"name": "Patched", "employees": 35, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (103, '[{"id": 3}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_3;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (3, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'Original', 30),
    (3, 1, '2024-12-31'::DATE, '2025-12-31'::DATE, 'Patched', 35)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 3 ORDER BY valid_after;
DROP TABLE temp_source_3;

--------------------------------------------------------------------------------
\echo 'Scenario 4: `upsert_patch` with `during` relation'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES (4, 1, '2023-12-31', '2025-12-31', 'Original', 40);
CREATE TEMP TABLE temp_source_4 ( row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT) ON COMMIT DROP;
INSERT INTO temp_source_4 VALUES (104, 4, 1, '2024-06-30', '2024-12-31', 'Patched', 45);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_4 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_4
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_4',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{104}'::INT[], 'UPDATE'::import.plan_operation_type, 4, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-06-30'::DATE, '{"name": "Original", "employees": 40, "legal_unit_id": 1}'::JSONB, 'starts'::public.allen_interval_relation),
    (2, '{104}'::INT[], 'INSERT'::import.plan_operation_type, 4, NULL::DATE,         '2024-06-30'::DATE, '2024-12-31'::DATE, '{"name": "Patched", "employees": 45, "legal_unit_id": 1}'::JSONB,  NULL::public.allen_interval_relation),
    (3, '{104}'::INT[], 'INSERT'::import.plan_operation_type, 4, NULL::DATE,         '2024-12-31'::DATE, '2025-12-31'::DATE, '{"name": "Original", "employees": 40, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (104, '[{"id": 4}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_4;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (4, 1, '2023-12-31'::DATE, '2024-06-30'::DATE, 'Original', 40),
    (4, 1, '2024-06-30'::DATE, '2024-12-31'::DATE, 'Patched', 45),
    (4, 1, '2024-12-31'::DATE, '2025-12-31'::DATE, 'Original', 40)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 4 ORDER BY valid_after;
DROP TABLE temp_source_4;

--------------------------------------------------------------------------------
\echo 'Scenario 5: `upsert_patch` with `overlaps` relation'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES (5, 1, '2023-12-31', '2024-12-31', 'Original', 50);
CREATE TEMP TABLE temp_source_5 ( row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT) ON COMMIT DROP;
INSERT INTO temp_source_5 VALUES (105, 5, 1, '2024-06-30', '2025-06-30', 'Patched', 55);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_5 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_5
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_5',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{105}'::INT[], 'UPDATE'::import.plan_operation_type, 5, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-06-30'::DATE, '{"name": "Original", "employees": 50, "legal_unit_id": 1}'::JSONB, 'starts'::public.allen_interval_relation),
    (2, '{105}'::INT[], 'INSERT'::import.plan_operation_type, 5, NULL::DATE, '2024-06-30'::DATE, '2025-06-30'::DATE, '{"name": "Patched", "employees": 55, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (105, '[{"id": 5}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_5;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (5, 1, '2023-12-31'::DATE, '2024-06-30'::DATE, 'Original', 50),
    (5, 1, '2024-06-30'::DATE, '2025-06-30'::DATE, 'Patched', 55)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 5 ORDER BY valid_after;
DROP TABLE temp_source_5;

--------------------------------------------------------------------------------
\echo 'Scenario 6: `upsert_patch` with `overlapped by` relation'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES (6, 1, '2024-06-30', '2025-06-30', 'Original', 60);
CREATE TEMP TABLE temp_source_6 ( row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT) ON COMMIT DROP;
INSERT INTO temp_source_6 VALUES (106, 6, 1, '2023-12-31', '2024-12-31', 'Patched', 65);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_6 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_6
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_6',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{106}'::INT[], 'UPDATE'::import.plan_operation_type, 6, '2024-06-30'::DATE, '2024-12-31'::DATE, '2025-06-30'::DATE, '{"name": "Original", "employees": 60, "legal_unit_id": 1}'::JSONB, 'finishes'::public.allen_interval_relation),
    (2, '{106}'::INT[], 'INSERT'::import.plan_operation_type, 6, NULL::DATE,         '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "Patched", "employees": 65, "legal_unit_id": 1}'::JSONB,   NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (106, '[{"id": 6}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_6;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (6, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'Patched', 65),
    (6, 1, '2024-12-31'::DATE, '2025-06-30'::DATE, 'Original', 60)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 6 ORDER BY valid_after;
DROP TABLE temp_source_6;

--------------------------------------------------------------------------------
\echo 'Scenario 7: `upsert_patch` with `meets` relation'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES (7, 1, '2024-12-31', '2025-12-31', 'Original', 70);
CREATE TEMP TABLE temp_source_7 ( row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT) ON COMMIT DROP;
INSERT INTO temp_source_7 VALUES (107, 7, 1, '2023-12-31', '2024-12-31', 'Patched', 75);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_7 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_7
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_7',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{107}'::INT[], 'INSERT'::import.plan_operation_type, 7, NULL::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "Patched", "employees": 75, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (107, '[{"id": 7}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_7;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (7, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'Patched', 75),
    (7, 1, '2024-12-31'::DATE, '2025-12-31'::DATE, 'Original', 70)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 7 ORDER BY valid_after;
DROP TABLE temp_source_7;

--------------------------------------------------------------------------------
\echo 'Scenario 8: `upsert_patch` with `met by` relation'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES (8, 1, '2023-12-31', '2024-12-31', 'Original', 80);
CREATE TEMP TABLE temp_source_8 ( row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT) ON COMMIT DROP;
INSERT INTO temp_source_8 VALUES (108, 8, 1, '2024-12-31', '2025-12-31', 'Patched', 85);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_8 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_8
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_8',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{108}'::INT[], 'INSERT'::import.plan_operation_type, 8, NULL::DATE, '2024-12-31'::DATE, '2025-12-31'::DATE, '{"name": "Patched", "employees": 85, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (108, '[{"id": 8}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_8;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (8, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'Original', 80),
    (8, 1, '2024-12-31'::DATE, '2025-12-31'::DATE, 'Patched', 85)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 8 ORDER BY valid_after;
DROP TABLE temp_source_8;

--------------------------------------------------------------------------------
\echo 'Scenario 9: `upsert_patch` with `before` relation (non-contiguous)'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES (9, 1, '2025-01-01', '2025-12-31', 'Original', 90);
CREATE TEMP TABLE temp_source_9 ( row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT) ON COMMIT DROP;
INSERT INTO temp_source_9 VALUES (109, 9, 1, '2023-12-31', '2024-12-31', 'Patched', 95);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_9 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_9
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_9',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{109}'::INT[], 'INSERT'::import.plan_operation_type, 9, NULL::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "Patched", "employees": 95, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (109, '[{"id": 9}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_9;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (9, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'Patched', 95),
    (9, 1, '2025-01-01'::DATE, '2025-12-31'::DATE, 'Original', 90)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 9 ORDER BY valid_after;
DROP TABLE temp_source_9;

--------------------------------------------------------------------------------
\echo 'Scenario 10: `upsert_patch` with `after` relation (non-contiguous)'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES (10, 1, '2023-12-31', '2024-12-31', 'Original', 100);
CREATE TEMP TABLE temp_source_10 ( row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT) ON COMMIT DROP;
INSERT INTO temp_source_10 VALUES (110, 10, 1, '2025-01-01', '2025-12-31', 'Patched', 105);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_10 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_10
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_10',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{110}'::INT[], 'INSERT'::import.plan_operation_type, 10, NULL::DATE, '2025-01-01'::DATE, '2025-12-31'::DATE, '{"name": "Patched", "employees": 105, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (110, '[{"id": 10}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_10;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (10, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'Original', 100),
    (10, 1, '2025-01-01'::DATE, '2025-12-31'::DATE, 'Patched', 105)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 10 ORDER BY valid_after;
DROP TABLE temp_source_10;

--------------------------------------------------------------------------------
\echo 'Scenario 11: `upsert_patch` with `equals` relation'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES (11, 1, '2023-12-31', '2024-12-31', 'Original', 110);
CREATE TEMP TABLE temp_source_11 ( row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT) ON COMMIT DROP;
INSERT INTO temp_source_11 VALUES (111, 11, 1, '2023-12-31', '2024-12-31', 'Patched', 115);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_11 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_11
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_11',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{111}'::INT[], 'UPDATE'::import.plan_operation_type, 11, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "Patched", "employees": 115, "legal_unit_id": 1}'::JSONB, 'equals'::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (111, '[{"id": 11}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_11;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (11, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'Patched', 115)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 11 ORDER BY valid_after;
DROP TABLE temp_source_11;

--------------------------------------------------------------------------------
\echo '================================================================================'
\echo 'Begin Scenarios for UPSERT_REPLACE mode'
\echo '================================================================================'
\echo 'Scenario 17: `upsert_replace` with `equals` relation (Source NULL replaces existing value)'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2023-12-31', '2024-12-31', 'Old Name', 10, 'Old Comment');
CREATE TEMP TABLE temp_source_17 (
    row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT, employees INT
) ON COMMIT DROP;
INSERT INTO temp_source_17 VALUES (102, 1, 1, '2023-12-31', '2024-12-31', NULL, 'Replaced with NULL', NULL);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_17 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_17
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_17',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[],
    p_mode                     => 'upsert_replace'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{102}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": null, "employees": null, "legal_unit_id": 1, "edit_comment": "Replaced with NULL"}'::JSONB, 'equals'::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (102, '[{"id": 1}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_17;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (1, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, NULL::TEXT, NULL::INT, 'Replaced with NULL'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_merge.establishment WHERE id = 1 ORDER BY valid_after;

DROP TABLE temp_source_17;


--------------------------------------------------------------------------------
\echo 'Scenario 35: `SAVEPOINT` test demonstrating necessity of `process_*` call ordering'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
CREATE TEMP TABLE temp_source_35 ( row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
SAVEPOINT before_wrong_order;

\echo '--- Stage 1: Prove that `patch_only` before `upsert_patch` is a NOOP ---'
INSERT INTO temp_source_35 VALUES (301, 1, 3, '2021-12-31', '2022-12-31', 'NewCo UPDATE', 15, 'Should not be inserted');
\echo '--- Orchestrator: Calling with `patch_only` on non-existent entity... ---'
\echo '--- Orchestrator: Expected Feedback (MISSING_TARGET) ---'
SELECT * FROM (VALUES (301, '[]'::JSONB, 'MISSING_TARGET'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);
\echo '--- Orchestrator: Actual Feedback ---'
SELECT source_row_id, target_entity_ids, status, error_message FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_35',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[],
    p_mode                     => 'patch_only'
);
\echo '--- Orchestrator: Final state of target table (expected empty, proving data loss) ---'
SELECT 0 as row_count WHERE NOT EXISTS (SELECT 1 FROM set_test_merge.establishment WHERE id = 3);
\echo '--- Orchestrator: Actual state of target table ---'
SELECT count(*) as row_count FROM set_test_merge.establishment WHERE id = 3;
ROLLBACK TO SAVEPOINT before_wrong_order;

\echo '--- Stage 2: Prove that `upsert_patch`-then-`patch_only` succeeds ---'
\echo '--- Orchestrator: Calling with `upsert_patch`... ---'
TRUNCATE temp_source_35;
INSERT INTO temp_source_35 VALUES (301, 1, 3, '2020-12-31', '2021-12-31', 'NewCo INSERT', 10, 'Initial Insert');
SELECT source_row_id, target_entity_ids, status, error_message FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_35',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Orchestrator: Calling with `patch_only`... ---'
TRUNCATE temp_source_35;
INSERT INTO temp_source_35 VALUES (302, 1, 3, '2021-12-31', '2022-12-31', NULL, 15, 'Successful Update');
SELECT source_row_id, target_entity_ids, status, error_message FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_35',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[],
    p_mode                     => 'patch_only'
);

\echo '--- Orchestrator: Final state of target table (expected complete history) ---'
SELECT * FROM (VALUES
    (3, 1, '2020-12-31'::DATE, '2021-12-31'::DATE, 'NewCo INSERT'::TEXT, 10, 'Initial Insert'::TEXT),
    (3, 1, '2021-12-31'::DATE, '2022-12-31'::DATE, 'NewCo INSERT'::TEXT, 15, 'Successful Update'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);
\echo '--- Orchestrator: Actual state of target table ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_merge.establishment WHERE id = 3 ORDER BY valid_after;
RELEASE SAVEPOINT before_wrong_order;
DROP TABLE temp_source_35;

\echo '--- Orchestrator: Expected Final State (after successful run) ---'
SELECT 2 AS row_count;
\echo '--- Orchestrator: Actual Final State ---'
SELECT count(*) AS row_count FROM set_test_merge.establishment WHERE id = 3;

--------------------------------------------------------------------------------
-- Scenarios for Merging and Coalescing
--------------------------------------------------------------------------------
\echo '================================================================================'
\echo 'Begin Scenarios for Merging and Coalescing'
\echo '================================================================================'

--------------------------------------------------------------------------------
\echo 'Scenario 36: `upsert_patch` with consecutive, identical source rows (should merge into one operation)'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
CREATE TEMP TABLE temp_source_36 (
    row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT
) ON COMMIT DROP;
-- Two source rows, contiguous in time, with identical data.
INSERT INTO temp_source_36 VALUES
(401, 1, 4, '2023-01-01', '2023-06-30', 'Continuous Op', 20),
(402, 1, 4, '2023-06-30', '2023-12-31', 'Continuous Op', 20);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_36 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_36
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_36',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan (A single INSERT for the full period) ---'
SELECT * FROM (VALUES
    (1, '{401, 402}'::INT[], 'INSERT'::import.plan_operation_type, 4, NULL::DATE, '2023-01-01'::DATE, '2023-12-31'::DATE, '{"name": "Continuous Op", "employees": 20, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES
    (401, '[{"id": 4}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT),
    (402, '[{"id": 4}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)
) AS t (source_row_id, target_entity_ids, status, error_message) ORDER BY source_row_id;

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_36 ORDER BY source_row_id;

\echo '--- Orchestrator: Expected Final State (A single merged row) ---'
SELECT * FROM (VALUES
    (4, 1, '2023-01-01'::DATE, '2023-12-31'::DATE, 'Continuous Op'::TEXT, 20, NULL::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_merge.establishment WHERE id = 4 ORDER BY valid_after;

DROP TABLE temp_source_36;

--------------------------------------------------------------------------------
\echo 'Scenario 37: `upsert_patch` with three consecutive, identical source rows (should merge)'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
CREATE TEMP TABLE temp_source_37 (
    row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT
) ON COMMIT DROP;
INSERT INTO temp_source_37 VALUES
(501, 1, 5, '2023-01-01', '2023-03-31', 'Three-part Op', 30),
(502, 1, 5, '2023-03-31', '2023-06-30', 'Three-part Op', 30),
(503, 1, 5, '2023-06-30', '2023-09-30', 'Three-part Op', 30);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_37 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_37
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_37',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan (A single INSERT for the full period) ---'
SELECT * FROM (VALUES
    (1, '{501, 502, 503}'::INT[], 'INSERT'::import.plan_operation_type, 5, NULL::DATE, '2023-01-01'::DATE, '2023-09-30'::DATE, '{"name": "Three-part Op", "employees": 30, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES
    (501, '[{"id": 5}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT),
    (502, '[{"id": 5}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT),
    (503, '[{"id": 5}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)
) AS t (source_row_id, target_entity_ids, status, error_message) ORDER BY source_row_id;

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_37 ORDER BY source_row_id;

\echo '--- Orchestrator: Expected Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 5 ORDER BY valid_after;
DROP TABLE temp_source_37;

--------------------------------------------------------------------------------
\echo 'Scenario 38: `upsert_patch` with two consecutive but DIFFERENT source rows (should NOT merge)'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
CREATE TEMP TABLE temp_source_38 (
    row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT
) ON COMMIT DROP;
INSERT INTO temp_source_38 VALUES
(601, 1, 6, '2023-01-01', '2023-06-30', 'First Part', 40),
(602, 1, 6, '2023-06-30', '2023-12-31', 'Second Part', 50);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_38 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_38
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_38',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan (Two separate INSERTs) ---'
SELECT * FROM (VALUES
    (1, '{601}'::INT[], 'INSERT'::import.plan_operation_type, 6, NULL::DATE, '2023-01-01'::DATE, '2023-06-30'::DATE, '{"name": "First Part", "employees": 40, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation),
    (2, '{602}'::INT[], 'INSERT'::import.plan_operation_type, 6, NULL::DATE, '2023-06-30'::DATE, '2023-12-31'::DATE, '{"name": "Second Part", "employees": 50, "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation) ORDER BY plan_op_seq;

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan ORDER BY plan_op_seq;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES
    (601, '[{"id": 6}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT),
    (602, '[{"id": 6}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)
) AS t (source_row_id, target_entity_ids, status, error_message) ORDER BY source_row_id;

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_38 ORDER BY source_row_id;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (6, 1, '2023-01-01'::DATE, '2023-06-30'::DATE, 'First Part'::TEXT, 40),
    (6, 1, '2023-06-30'::DATE, '2023-12-31'::DATE, 'Second Part'::TEXT, 50)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees FROM set_test_merge.establishment WHERE id = 6 ORDER BY valid_after;
DROP TABLE temp_source_38;

--------------------------------------------------------------------------------
\echo 'Scenario 39: `upsert_patch` where source row is consecutive with existing target row (should merge/extend)'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES (7, 1, '2022-12-31', '2023-06-30', 'Existing Op', 60);
CREATE TEMP TABLE temp_source_39 (
    row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT
) ON COMMIT DROP;
-- This source row meets the existing target row, with identical data.
INSERT INTO temp_source_39 VALUES (701, 1, 7, '2023-06-30', '2023-12-31', 'Existing Op', 60);

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_39 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_39
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_39',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan (A single UPDATE extending the target row) ---'
SELECT * FROM (VALUES
    (1, '{701}'::INT[], 'UPDATE'::import.plan_operation_type, 7, '2022-12-31'::DATE, '2022-12-31'::DATE, '2023-12-31'::DATE, '{"name": "Existing Op", "employees": 60, "legal_unit_id": 1}'::JSONB, 'started_by'::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (701, '[{"id": 7}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_39;

\echo '--- Orchestrator: Expected Final State (A single merged row) ---'
SELECT * FROM (VALUES
    (7, 1, '2022-12-31'::DATE, '2023-12-31'::DATE, 'Existing Op'::TEXT, 60, NULL::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_merge.establishment WHERE id = 7 ORDER BY valid_after;

DROP TABLE temp_source_39;

-- Final Cleanup before independent tests.
DROP PROCEDURE set_test_merge.reset_target();
DROP TABLE set_test_merge.establishment;
DROP TABLE set_test_merge.legal_unit;
DROP SEQUENCE set_test_merge.establishment_id_seq;
DROP SEQUENCE set_test_merge.legal_unit_id_seq;
DROP SCHEMA set_test_merge CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

BEGIN;
SET client_min_messages TO WARNING;

-- Test schema
CREATE SCHEMA set_test_merge;

-- Sequences for auto-generated IDs
CREATE SEQUENCE set_test_merge.legal_unit_id_seq;
CREATE SEQUENCE set_test_merge.establishment_id_seq;

-- Target tables (simplified versions for testing)
CREATE TABLE set_test_merge.legal_unit (
    id INT PRIMARY KEY,
    name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE set_test_merge.establishment (
    id INT NOT NULL,
    legal_unit_id INT NOT NULL,
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    name TEXT,
    employees INT,
    edit_comment TEXT,
    PRIMARY KEY (id, valid_after)
);

-- Helper procedure to reset target table state between scenarios
CREATE PROCEDURE set_test_merge.reset_target() LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE set_test_merge.establishment;
    TRUNCATE set_test_merge.legal_unit;
    -- Seed with a legal unit for FK constraints
    INSERT INTO set_test_merge.legal_unit (id, name) VALUES (1, 'Test LU');
    ALTER SEQUENCE set_test_merge.establishment_id_seq RESTART WITH 1;
END;
$$;

-- psql variables for the test
\set target_schema 'set_test_merge'
\set target_table 'establishment'
\set source_schema 'pg_temp'
\set entity_id_cols '{id}'

\set ephemeral_cols '{edit_comment}'

--------------------------------------------------------------------------------
\echo 'Scenario 40: `INSERT` with `created_at` defaulted'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
CREATE TEMP TABLE temp_source_40 (
    row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source_40 VALUES (801, 1, 40, '2023-12-31', '2024-12-31', 'Default Test', 10, 'Default Insert');

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_40 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_40
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_40',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => ARRAY['created_at', 'updated_at'],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan ---'
-- The planner should NOT include `created_at` in the data payload, allowing the DB default to apply.
SELECT * FROM (VALUES
    (1, '{801}'::INT[], 'INSERT'::import.plan_operation_type, 40, NULL::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "Default Test", "employees": 10, "edit_comment": "Default Insert", "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (801, '[{"id": 40}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_40;

\echo '--- Orchestrator: Expected Final State (created_at should NOT be null) ---'
-- We only check that created_at is not null, as the exact time is non-deterministic.
SELECT 1 AS row_count WHERE EXISTS (SELECT 1 FROM set_test_merge.establishment WHERE id = 40 AND created_at IS NOT NULL);

\echo '--- Orchestrator: Actual Final State ---'
SELECT count(*)::INT AS row_count FROM set_test_merge.establishment WHERE id = 40 AND created_at IS NOT NULL;

DROP TABLE temp_source_40;

-- Final Cleanup
DROP PROCEDURE set_test_merge.reset_target();
DROP TABLE set_test_merge.establishment;
DROP TABLE set_test_merge.legal_unit;
DROP SEQUENCE set_test_merge.establishment_id_seq;
DROP SEQUENCE set_test_merge.legal_unit_id_seq;
DROP SCHEMA set_test_merge CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

BEGIN;
SET client_min_messages TO WARNING;

-- Test schema for valid_from test
CREATE SCHEMA set_test_merge_vf;

-- Target table with generated valid_from
CREATE TABLE set_test_merge_vf.test_target (
    id INT NOT NULL,
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    -- valid_from is inclusive start, valid_after is exclusive start
    valid_from DATE NOT NULL GENERATED ALWAYS AS (valid_after + INTERVAL '1 day') STORED,
    name TEXT,
    PRIMARY KEY (id, valid_after)
);

-- Helper procedure
CREATE PROCEDURE set_test_merge_vf.reset_target() LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE set_test_merge_vf.test_target;
END;
$$;

-- psql variables
\set target_schema 'set_test_merge_vf'
\set target_table 'test_target'
\set source_schema 'pg_temp'
\set entity_id_cols '{id}'
\set ephemeral_cols '{}'

--------------------------------------------------------------------------------
\echo 'Scenario 41: `upsert_patch` with `starts` on a table with generated `valid_from`'
--------------------------------------------------------------------------------
CALL set_test_merge_vf.reset_target();
INSERT INTO set_test_merge_vf.test_target (id, valid_after, valid_to, name) VALUES (1, '2023-12-31', '2025-12-31', 'Original');
CREATE TEMP TABLE temp_source_41 (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, valid_from DATE
) ON COMMIT DROP;
-- Source data has a `valid_from` that would be inconsistent if copied directly to a split-off segment
INSERT INTO temp_source_41 VALUES (901, 1, '2023-12-31', '2024-12-31', 'Patched', '2024-01-01');

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_41 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_41
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_41',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan (valid_from should not be in the data payload) ---'
SELECT * FROM (VALUES
    (1, '{901}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "Patched"}'::JSONB, 'starts'::public.allen_interval_relation),
    (2, '{901}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE,         '2024-12-31'::DATE, '2025-12-31'::DATE, '{"name": "Original"}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (901, '[{"id": 1}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_41;

\echo '--- Orchestrator: Expected Final State (valid_from should be correct for both segments) ---'
SELECT * FROM (VALUES
    (1, '2023-12-31'::DATE, '2024-12-31'::DATE, '2024-01-01'::DATE, 'Patched'),
    (1, '2024-12-31'::DATE, '2025-12-31'::DATE, '2025-01-01'::DATE, 'Original')
) AS t (id, valid_after, valid_to, valid_from, name);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, valid_after, valid_to, valid_from, name FROM set_test_merge_vf.test_target WHERE id = 1 ORDER BY valid_after;

DROP TABLE temp_source_41;

-- Final Cleanup
DROP PROCEDURE set_test_merge_vf.reset_target();
DROP TABLE set_test_merge_vf.test_target;
DROP SCHEMA set_test_merge_vf CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

BEGIN;
SET client_min_messages TO WARNING;

-- Test schema for multi-entity batch test
CREATE SCHEMA set_test_merge_me;

-- Target table
CREATE TABLE set_test_merge_me.test_target (
    id INT NOT NULL,
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    status TEXT,
    PRIMARY KEY (id, valid_after)
);

-- Helper procedure
CREATE PROCEDURE set_test_merge_me.reset_target() LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE set_test_merge_me.test_target;
END;
$$;

-- psql variables
\set target_schema 'set_test_merge_me'
\set target_table 'test_target'
\set source_schema 'pg_temp'
\set entity_id_cols '{id}'
\set ephemeral_cols '{}'

--------------------------------------------------------------------------------
\echo 'Scenario 42: Multi-entity batch with status change (Bug Reproduction for #106)'
--------------------------------------------------------------------------------
CREATE TEMP TABLE temp_source_42 (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, status TEXT
) ON COMMIT DROP;
-- Entity 1 ("Oslo"): single continuous record
INSERT INTO temp_source_42 VALUES (101, 1, '2009-12-31', 'infinity', 'active');
-- Entity 2 ("Omegn"): contiguous records with a status change
INSERT INTO temp_source_42 VALUES (102, 2, '2009-12-31', '2010-12-31', 'active');
INSERT INTO temp_source_42 VALUES (103, 2, '2010-12-31', 'infinity', 'passive');

-- Run the orchestrator and store its feedback
CALL set_test_merge_me.reset_target();
CREATE TEMP TABLE actual_feedback_42 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_42
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_42',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_replace'
);

\echo '--- Planner: Expected Plan (Entity 1 should have one INSERT, Entity 2 should have two) ---'
SELECT * FROM (VALUES
    (1, '{101}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2009-12-31'::DATE, 'infinity'::DATE, '{"status": "active"}'::JSONB, NULL::public.allen_interval_relation),
    (2, '{102}'::INT[], 'INSERT'::import.plan_operation_type, 2, NULL::DATE, '2009-12-31'::DATE, '2010-12-31'::DATE, '{"status": "active"}'::JSONB, NULL::public.allen_interval_relation),
    (3, '{103}'::INT[], 'INSERT'::import.plan_operation_type, 2, NULL::DATE, '2010-12-31'::DATE, 'infinity'::DATE, '{"status": "passive"}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation)
ORDER BY entity_id, new_valid_after;

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan ORDER BY (entity_ids->>'id')::INT, new_valid_after;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES
    (101, '[{"id": 1}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT),
    (102, '[{"id": 2}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT),
    (103, '[{"id": 2}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)
) AS t (source_row_id, target_entity_ids, status, error_message) ORDER BY source_row_id;

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_42 ORDER BY source_row_id;

\echo '--- Orchestrator: Expected Final State (Entity 1 should NOT be split) ---'
SELECT * FROM (VALUES
    (1, '2009-12-31'::DATE, 'infinity'::DATE, 'active'),
    (2, '2009-12-31'::DATE, '2010-12-31'::DATE, 'active'),
    (2, '2010-12-31'::DATE, 'infinity'::DATE, 'passive')
) AS t (id, valid_after, valid_to, status) ORDER BY id, valid_after;

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, valid_after, valid_to, status FROM set_test_merge_me.test_target ORDER BY id, valid_after;

DROP TABLE temp_source_42;
DROP PROCEDURE set_test_merge_me.reset_target();
DROP TABLE set_test_merge_me.test_target;
DROP SCHEMA set_test_merge_me CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

BEGIN;
SET client_min_messages TO WARNING;

-- Test schema
CREATE SCHEMA set_test_merge;

-- Sequences for auto-generated IDs
CREATE SEQUENCE set_test_merge.legal_unit_id_seq;
CREATE SEQUENCE set_test_merge.establishment_id_seq;

-- Target tables (simplified versions for testing)
CREATE TABLE set_test_merge.legal_unit (
    id INT PRIMARY KEY,
    name TEXT
);

CREATE TABLE set_test_merge.establishment (
    id INT NOT NULL,
    legal_unit_id INT NOT NULL,
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    name TEXT,
    employees INT,
    edit_comment TEXT,
    PRIMARY KEY (id, valid_after)
);

-- Helper procedure to reset target table state between scenarios
CREATE PROCEDURE set_test_merge.reset_target() LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE set_test_merge.establishment;
    TRUNCATE set_test_merge.legal_unit;
    -- Seed with a legal unit for FK constraints
    INSERT INTO set_test_merge.legal_unit (id, name) VALUES (1, 'Test LU');
    ALTER SEQUENCE set_test_merge.establishment_id_seq RESTART WITH 1;
END;
$$;

-- psql variables for the test
\set target_schema 'set_test_merge'
\set target_table 'establishment'
\set source_schema 'pg_temp'
\set entity_id_cols '{id}'
\set ephemeral_cols '{edit_comment}'
--------------------------------------------------------------------------------
\echo 'Scenario 43: Multi-entity batch with data change (Realistic reproduction of #106)'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
CREATE TEMP TABLE temp_source_43 (
    row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
-- Entity 10 ("Continuous"): single continuous record
INSERT INTO temp_source_43 VALUES (1001, 10, 1, '2009-12-31', 'infinity', 'Continuous', 50, 'comment');
-- Entity 20 ("Changes"): contiguous records with a data change
INSERT INTO temp_source_43 VALUES (1002, 20, 1, '2009-12-31', '2010-12-31', 'Changes', 100, 'comment');
INSERT INTO temp_source_43 VALUES (1003, 20, 1, '2010-12-31', 'infinity',   'Changes', 150, 'comment');

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_43 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_43
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_43',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_mode                     => 'upsert_patch'
);

\echo '--- Planner: Expected Plan (Entity 10 should have one INSERT, Entity 20 should have two) ---'
SELECT * FROM (VALUES
    (1, '{1001}'::INT[], 'INSERT'::import.plan_operation_type, 10, NULL::DATE, '2009-12-31'::DATE, 'infinity'::DATE,   '{"name": "Continuous", "employees": 50, "edit_comment": "comment", "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation),
    (2, '{1002}'::INT[], 'INSERT'::import.plan_operation_type, 20, NULL::DATE, '2009-12-31'::DATE, '2010-12-31'::DATE, '{"name": "Changes", "employees": 100, "edit_comment": "comment", "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation),
    (3, '{1003}'::INT[], 'INSERT'::import.plan_operation_type, 20, NULL::DATE, '2010-12-31'::DATE, 'infinity'::DATE,   '{"name": "Changes", "employees": 150, "edit_comment": "comment", "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation)
ORDER BY entity_id, new_valid_after;

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan ORDER BY (entity_ids->>'id')::INT, new_valid_after;

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES
    (1001, '[{"id": 10}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT),
    (1002, '[{"id": 20}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT),
    (1003, '[{"id": 20}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)
) AS t (source_row_id, target_entity_ids, status, error_message) ORDER BY source_row_id;

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_43 ORDER BY source_row_id;

\echo '--- Orchestrator: Expected Final State (Entity 10 should NOT be split) ---'
SELECT * FROM (VALUES
    (10, 1, '2009-12-31'::DATE, 'infinity'::DATE,   'Continuous', 50, 'comment'),
    (20, 1, '2009-12-31'::DATE, '2010-12-31'::DATE, 'Changes',    100, 'comment'),
    (20, 1, '2010-12-31'::DATE, 'infinity'::DATE,   'Changes',    150, 'comment')
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) ORDER BY id, valid_after;

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_merge.establishment ORDER BY id, valid_after;

DROP TABLE temp_source_43;

-- Final Cleanup
DROP PROCEDURE set_test_merge.reset_target();
DROP TABLE set_test_merge.establishment;
DROP TABLE set_test_merge.legal_unit;
DROP SEQUENCE set_test_merge.establishment_id_seq;
DROP SEQUENCE set_test_merge.legal_unit_id_seq;
DROP SCHEMA set_test_merge CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

BEGIN;
SET client_min_messages TO WARNING;

-- Test schema
CREATE SCHEMA set_test_merge_serial;

-- Target table with SERIAL surrogate key
CREATE TABLE set_test_merge_serial.test_target (
    id SERIAL PRIMARY KEY,
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    name TEXT,
    UNIQUE (id, valid_after)
);

-- psql variables for the test
\set target_schema 'set_test_merge_serial'
\set target_table 'test_target'
\set source_schema 'pg_temp'
\set entity_id_cols '{id}'
\set ephemeral_cols '{}'

--------------------------------------------------------------------------------
\echo 'Scenario 44: `INSERT` with SERIAL surrogate key should return the generated ID'
--------------------------------------------------------------------------------
CREATE TEMP TABLE temp_source_44 (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT
) ON COMMIT DROP;
-- ID is NULL, to be generated by the database
INSERT INTO temp_source_44 VALUES (1001, NULL, '2023-12-31', '2024-12-31', 'Serial Widget');

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_44 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_44
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_44',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => ARRAY['id'],
    p_mode                     => 'upsert_replace'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{1001}'::INT[], 'INSERT'::import.plan_operation_type, '{"id": 1}'::JSONB, NULL::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "Serial Widget"}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_ids, old_valid_after, new_valid_after, new_valid_to, data, relation);

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, entity_ids, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan;

\echo '--- Orchestrator: Expected Feedback (Should return generated ID 1) ---'
SELECT * FROM (VALUES (1001, '[{"id": 1}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_44;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'Serial Widget'::TEXT)
) AS t (id, valid_after, valid_to, name);

\echo '--- Orchestrator: Actual Final State ---'
SELECT id, valid_after, valid_to, name FROM set_test_merge_serial.test_target WHERE id = 1 ORDER BY valid_after;

DROP TABLE temp_source_44;

-- Final Cleanup
DROP TABLE set_test_merge_serial.test_target;
DROP SCHEMA set_test_merge_serial CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

BEGIN;
SET client_min_messages TO WARNING;

-- Use the same schema as Scenario 44 for simplicity
CREATE SCHEMA set_test_merge_multi_insert;
CREATE TABLE set_test_merge_multi_insert.test_target (
    id SERIAL PRIMARY KEY,
    name TEXT,
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL
);

\set target_schema 'set_test_merge_multi_insert'
\set target_table 'test_target'
\set source_schema 'pg_temp'
\set entity_id_cols '{id}'

--------------------------------------------------------------------------------
\echo 'Scenario 45: Batch INSERT of multiple new entities'
--------------------------------------------------------------------------------
CREATE TEMP TABLE temp_source_45 (
    row_id INT, id INT, name TEXT, valid_after DATE NOT NULL, valid_to DATE NOT NULL
) ON COMMIT DROP;
-- Source contains two distinct new entities
INSERT INTO temp_source_45 VALUES
(2001, NULL, 'Entity One', '2024-01-01', '2024-12-31'),
(2002, NULL, 'Entity Two', '2024-01-01', '2024-12-31');

-- Run the orchestrator and store its feedback
CREATE TEMP TABLE actual_feedback_45 (LIKE import.temporal_merge_result) ON COMMIT DROP;
INSERT INTO actual_feedback_45
SELECT * FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_45',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => '{}'::TEXT[],
    p_insert_defaulted_columns => ARRAY['id'],
    p_mode                     => 'upsert_replace'
);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    (1, '{2001}'::INT[], 'INSERT'::import.plan_operation_type, '{"id": 1}'::JSONB, NULL::DATE, '2024-01-01'::DATE, '2024-12-31'::DATE, '{"name": "Entity One"}'::JSONB, NULL::public.allen_interval_relation),
    (2, '{2002}'::INT[], 'INSERT'::import.plan_operation_type, '{"id": 2}'::JSONB, NULL::DATE, '2024-01-01'::DATE, '2024-12-31'::DATE, '{"name": "Entity Two"}'::JSONB, NULL::public.allen_interval_relation)
) AS t (plan_op_seq, source_row_ids, operation, entity_ids, old_valid_after, new_valid_after, new_valid_to, data, relation) ORDER BY (data->>'name');

\echo '--- Planner: Actual Plan (from Orchestrator) ---'
SELECT plan_op_seq, source_row_ids, operation, entity_ids, old_valid_after, new_valid_after, new_valid_to, data, relation FROM __temp_last_temporal_merge_plan ORDER BY (data->>'name');

\echo '--- Orchestrator: Expected Feedback (One distinct result per source row) ---'
SELECT * FROM (VALUES
    (2001, '[{"id": 1}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT),
    (2002, '[{"id": 2}]'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)
) AS t (source_row_id, target_entity_ids, status, error_message) ORDER BY source_row_id;

\echo '--- Orchestrator: Actual Feedback ---'
SELECT * FROM actual_feedback_45 ORDER BY source_row_id;

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (1, 'Entity One', '2024-01-01'::DATE, '2024-12-31'::DATE),
    (2, 'Entity Two', '2024-01-01'::DATE, '2024-12-31'::DATE)
) AS t (id, name, valid_after, valid_to);
\echo '--- Orchestrator: Actual Final State ---'
SELECT id, name, valid_after, valid_to FROM set_test_merge_multi_insert.test_target ORDER BY id;
DROP TABLE temp_source_45;

-- Final Cleanup
DROP TABLE set_test_merge_multi_insert.test_target;
DROP SCHEMA set_test_merge_multi_insert CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

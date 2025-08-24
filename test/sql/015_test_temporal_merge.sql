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

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    ('{101}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "New EST", "employees": 10, "edit_comment": "Initial Insert", "legal_unit_id": 1}'::JSONB, NULL::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo '--- Planner: Actual Plan ---'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.temporal_merge_plan(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_1',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_mode                     => 'upsert_patch',
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[]
);

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (101, '{"id": 1}'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);
\echo '--- Orchestrator: Actual Feedback ---'
SELECT source_row_id, target_entity_ids, status, error_message FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_1',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_mode                     => 'upsert_patch',
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[]
);

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (1, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'New EST'::TEXT, 10, 'Initial Insert'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);
\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_merge.establishment WHERE id = 1 ORDER BY valid_after;

DROP TABLE temp_source_1;

--------------------------------------------------------------------------------
\echo 'Scenario 18: `upsert_replace` with `equals` relation (Source NULL replaces existing value)'
--------------------------------------------------------------------------------
CALL set_test_merge.reset_target();
INSERT INTO set_test_merge.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2023-12-31', '2024-12-31', 'Old Name', 10, 'Old Comment');
CREATE TEMP TABLE temp_source_18 (
    row_id INT, id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT, employees INT
) ON COMMIT DROP;
INSERT INTO temp_source_18 VALUES (102, 1, 1, '2023-12-31', '2024-12-31', NULL, 'Replaced with NULL', NULL);

\echo '--- Planner: Expected Plan ---'
SELECT * FROM (VALUES
    ('{102}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": null, "employees": null, "legal_unit_id": 1, "edit_comment": "Replaced with NULL"}'::JSONB, 'equals'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo '--- Planner: Actual Plan ---'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.temporal_merge_plan(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_18',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_mode                     => 'upsert_replace',
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[]
);

\echo '--- Orchestrator: Expected Feedback ---'
SELECT * FROM (VALUES (102, '{"id": 1}'::JSONB, 'SUCCESS'::import.set_result_status, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);
\echo '--- Orchestrator: Actual Feedback ---'
SELECT source_row_id, target_entity_ids, status, error_message FROM import.temporal_merge(
    p_target_schema_name       => :'target_schema',
    p_target_table_name        => :'target_table',
    p_source_schema_name       => :'source_schema',
    p_source_table_name        => 'temp_source_18',
    p_entity_id_column_names   => :'entity_id_cols'::TEXT[],
    p_mode                     => 'upsert_replace',
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[]
);

\echo '--- Orchestrator: Expected Final State ---'
SELECT * FROM (VALUES
    (1, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, NULL::TEXT, NULL::INT, 'Replaced with NULL'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);
\echo '--- Orchestrator: Actual Final State ---'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_merge.establishment WHERE id = 1 ORDER BY valid_after;

DROP TABLE temp_source_18;


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
    p_mode                     => 'patch_only',
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[]
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
    p_mode                     => 'upsert_patch',
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[]
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
    p_mode                     => 'patch_only',
    p_source_row_ids           => NULL,
    p_ephemeral_columns        => :'ephemeral_cols'::TEXT[],
    p_insert_defaulted_columns => '{}'::TEXT[]
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

-- Final Cleanup
DROP PROCEDURE set_test_merge.reset_target();
DROP TABLE set_test_merge.establishment;
DROP TABLE set_test_merge.legal_unit;
DROP SEQUENCE set_test_merge.establishment_id_seq;
DROP SEQUENCE set_test_merge.legal_unit_id_seq;
DROP SCHEMA set_test_merge CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

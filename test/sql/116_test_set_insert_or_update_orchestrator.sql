BEGIN;
\i test/setup.sql

\echo '----------------------------------------------------------------------------'
\echo 'Test: import.set_insert_or_update_generic_valid_time_table orchestrator'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE;

-- Setup: Create necessary schema and tables for this test
CREATE SCHEMA IF NOT EXISTS set_test_orchestrator;
CREATE SEQUENCE IF NOT EXISTS set_test_orchestrator.legal_unit_id_seq;
CREATE SEQUENCE IF NOT EXISTS set_test_orchestrator.establishment_id_seq;

-- Parent table: legal_unit
CREATE TABLE set_test_orchestrator.legal_unit (
    id INT NOT NULL,
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    name TEXT,
    PRIMARY KEY (id, valid_after)
);
SELECT sql_saga.add_era('set_test_orchestrator.legal_unit', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('set_test_orchestrator.legal_unit', ARRAY['id'], 'valid', 'legal_unit_id_uk');

-- Target table: establishment (with temporal FK to legal_unit)
CREATE TABLE set_test_orchestrator.establishment (
    id INT NOT NULL,
    legal_unit_id INT, -- Temporal FK
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    name TEXT,
    employees INT,
    edit_comment TEXT, -- Ephemeral column
    PRIMARY KEY (id, valid_after)
);
SELECT sql_saga.add_era('set_test_orchestrator.establishment', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('set_test_orchestrator.establishment', ARRAY['id'], 'valid', 'establishment_id_uk');
SELECT sql_saga.add_foreign_key('set_test_orchestrator.establishment', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_uk');

-- Helper procedure to reset the target table for a new scenario
CREATE OR REPLACE PROCEDURE set_test_orchestrator.reset_target() AS $$
BEGIN
    TRUNCATE set_test_orchestrator.legal_unit, set_test_orchestrator.establishment RESTART IDENTITY CASCADE;
    ALTER SEQUENCE set_test_orchestrator.legal_unit_id_seq RESTART WITH 1;
    ALTER SEQUENCE set_test_orchestrator.establishment_id_seq RESTART WITH 1;
    -- Add parent data
    INSERT INTO set_test_orchestrator.legal_unit (id, valid_after, valid_to, name) VALUES
    (1, '1900-01-01', 'infinity', 'Parent LU 1');
END;
$$ LANGUAGE plpgsql;

-- Parameters for the set-based function
\set target_schema 'set_test_orchestrator'
\set target_table 'establishment'
\set entity_id_cols '{id}'
\set source_schema 'pg_temp'
\set ephemeral_cols '{edit_comment}'

--------------------------------------------------------------------------------
-- Test `set_insert_or_update`
--------------------------------------------------------------------------------
\echo 'Test Case 1: `set_insert_or_update` with a `during` relation (split)'
CALL set_test_orchestrator.reset_target();
INSERT INTO set_test_orchestrator.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2023-12-31', '2024-12-31', 'Original Name', 10, 'Original');
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (101, 1, 1, '2024-03-31', '2024-08-31', NULL, 20, 'Updated part'); -- name is NULL, employees changes
\echo 'Calling orchestrator...'
\echo 'Expected orchestrator feedback:'
SELECT * FROM (VALUES (101, '{"id": 1}'::JSONB, 'SUCCESS'::TEXT, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);
\echo 'Actual orchestrator feedback:'
SELECT source_row_id, target_entity_ids, status, error_message FROM import.set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
\echo 'Final state of target table (expected):'
SELECT * FROM (VALUES
    (1, 1, '2023-12-31'::DATE, '2024-03-31'::DATE, 'Original Name'::TEXT, 10, 'Original'::TEXT),
    (1, 1, '2024-03-31'::DATE, '2024-08-31'::DATE, 'Original Name'::TEXT, 20, 'Updated part'::TEXT),
    (1, 1, '2024-08-31'::DATE, '2024-12-31'::DATE, 'Original Name'::TEXT, 10, 'Original'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);
\echo 'Actual state of target table:'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_orchestrator.establishment WHERE id = 1 ORDER BY valid_after;
DROP TABLE temp_source;

--------------------------------------------------------------------------------
\echo 'Test Case 2: `set_insert_or_update` should not delete non-interacting history'
CALL set_test_orchestrator.reset_target();
-- Two historical, non-contiguous records for entity 1
INSERT INTO set_test_orchestrator.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES
(1, 1, '2023-12-31', '2024-03-31', 'History Part 1', 10, 'Original 1'),
(1, 1, '2024-08-31', '2024-12-31', 'History Part 2', 10, 'Original 2');
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
-- Source data only interacts with "History Part 1"
INSERT INTO temp_source VALUES (102, 1, 1, '2024-01-31', '2024-02-29', 'Updated Slice', 15, 'Update');
\echo 'Calling orchestrator...'
\echo 'Expected orchestrator feedback:'
SELECT * FROM (VALUES (102, '{"id": 1}'::JSONB, 'SUCCESS'::TEXT, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);
\echo 'Actual orchestrator feedback:'
SELECT source_row_id, target_entity_ids, status, error_message FROM import.set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
\echo 'Final state of target table (expected):'
SELECT * FROM (VALUES
    (1, 1, '2023-12-31'::DATE, '2024-01-31'::DATE, 'History Part 1'::TEXT, 10, 'Original 1'::TEXT),
    (1, 1, '2024-01-31'::DATE, '2024-02-29'::DATE, 'Updated Slice'::TEXT, 15, 'Update'::TEXT),
    (1, 1, '2024-02-29'::DATE, '2024-03-31'::DATE, 'History Part 1'::TEXT, 10, 'Original 1'::TEXT),
    (1, 1, '2024-08-31'::DATE, '2024-12-31'::DATE, 'History Part 2'::TEXT, 10, 'Original 2'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);
\echo 'Actual state of target table (should preserve "History Part 2"):'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_orchestrator.establishment WHERE id = 1 ORDER BY valid_after;
DROP TABLE temp_source;

\echo 'Test Case 3: `meets` relation, same core data, different ephemeral data (should merge and update ephemeral)'
CALL set_test_orchestrator.reset_target();
INSERT INTO set_test_orchestrator.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2024-01-31', '2024-03-31', 'Same Core', 10, 'Comment A');
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (103, 1, 1, '2024-03-31', '2024-06-30', 'Same Core', 10, 'Comment B');
\echo 'Calling orchestrator...'
\echo 'Expected orchestrator feedback:'
SELECT * FROM (VALUES (103, '{"id": 1}'::JSONB, 'SUCCESS'::TEXT, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);
\echo 'Actual orchestrator feedback:'
SELECT source_row_id, target_entity_ids, status, error_message FROM import.set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
\echo 'Final state of target table (expected):'
SELECT * FROM (VALUES
    (1, 1, '2024-01-31'::DATE, '2024-06-30'::DATE, 'Same Core'::TEXT, 10, 'Comment B'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);
\echo 'Actual state of target table:'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_orchestrator.establishment WHERE id = 1 ORDER BY valid_after;
DROP TABLE temp_source;

--------------------------------------------------------------------------------
\echo 'Test Case 4: Initial insert of new entity'
CALL set_test_orchestrator.reset_target();
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES (104, 1, nextval('set_test_orchestrator.establishment_id_seq'), '2023-12-31', '2024-12-31', 'New EST', 10, 'Initial');
\echo 'Calling orchestrator...'
\echo 'Expected orchestrator feedback:'
SELECT * FROM (VALUES (104, '{"id": 1}'::JSONB, 'SUCCESS'::TEXT, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);
\echo 'Actual orchestrator feedback:'
SELECT source_row_id, target_entity_ids, status, error_message FROM import.set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
\echo 'Final state of target table (expected):'
SELECT * FROM (VALUES
    (1, 1, '2023-12-31'::DATE, '2024-12-31'::DATE, 'New EST'::TEXT, 10, 'Initial'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);
\echo 'Actual state of target table:'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_orchestrator.establishment WHERE id = 1 ORDER BY valid_after;
DROP TABLE temp_source;

--------------------------------------------------------------------------------
\echo 'Test Case 5: Contiguous source rows with same core data should coalesce'
CALL set_test_orchestrator.reset_target();
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES
(105, 1, 1, '2024-01-31', '2024-03-31', 'Same Data', 50, 'Part A'),
(106, 1, 1, '2024-03-31', '2024-06-30', 'Same Data', 50, 'Part B');
\echo 'Calling orchestrator...'
\echo 'Expected orchestrator feedback (SUCCESS for both source rows):'
SELECT * FROM (VALUES
    (105, '{"id": 1}'::JSONB, 'SUCCESS'::TEXT, NULL::TEXT),
    (106, '{"id": 1}'::JSONB, 'SUCCESS'::TEXT, NULL::TEXT)
) AS t (source_row_id, target_entity_ids, status, error_message);
\echo 'Actual orchestrator feedback:'
SELECT source_row_id, target_entity_ids, status, error_message FROM import.set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]) ORDER BY source_row_id;
\echo 'Final state of target table (expected):'
SELECT * FROM (VALUES
    (1, 1, '2024-01-31'::DATE, '2024-06-30'::DATE, 'Same Data'::TEXT, 50, 'Part B'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);
\echo 'Actual state of target table:'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_orchestrator.establishment WHERE id = 1 ORDER BY valid_after;
DROP TABLE temp_source;

--------------------------------------------------------------------------------
-- This test uses SAVEPOINTs to rigorously prove the necessity of the two-stage
-- "INSERT-then-UPDATE" logic used by `process_*` procedures.
-- It confirms that calling UPDATE for a non-existent entity is a successful NOOP
-- that returns an empty entity ID array. This result is the "semantic hint" to
-- the caller that it must perform an INSERT first. The test proves that ignoring
-- this hint and failing to perform the initial INSERT leads to data loss.
\echo 'Test Case 6: Demonstrate necessity of `process_*` call ordering with SAVEPOINTs'
CALL set_test_orchestrator.reset_target();
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
SAVEPOINT before_wrong_order;
\echo '--- Stage 1: Prove that UPDATE-before-INSERT is a NOOP (and currently fails) ---'
INSERT INTO temp_source VALUES (301, 1, 3, '2021-12-31', '2022-12-31', 'NewCo UPDATE', 15, 'Should not be inserted');
\echo 'Calling orchestrator with UPDATE on non-existent entity...'
\echo 'Expected orchestrator feedback (MISSING_TARGET, indicating a NOOP):'
SELECT * FROM (VALUES (301, '[]'::JSONB, 'MISSING_TARGET'::TEXT, NULL::TEXT)) AS t (source_row_id, target_entity_ids, status, error_message);
\echo 'Actual orchestrator feedback:'
SELECT source_row_id, target_entity_ids, status, error_message FROM import.set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
\echo 'Final state of target table (expected empty, proving data loss):'
SELECT 0 as row_count WHERE NOT EXISTS (SELECT 1 FROM set_test_orchestrator.establishment WHERE id = 3);
\echo 'Actual state of target table:'
SELECT count(*) as row_count FROM set_test_orchestrator.establishment WHERE id = 3;
ROLLBACK TO SAVEPOINT before_wrong_order;

\echo '--- Stage 2: Prove that INSERT-then-UPDATE succeeds ---'
\echo 'Calling orchestrator with INSERT...'
TRUNCATE temp_source;
INSERT INTO temp_source VALUES (301, 1, 3, '2020-12-31', '2021-12-31', 'NewCo INSERT', 10, 'Initial Insert');
SELECT source_row_id, target_entity_ids, status, error_message FROM import.set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);

\echo 'Calling orchestrator with UPDATE...'
TRUNCATE temp_source;
INSERT INTO temp_source VALUES (302, 1, 3, '2021-12-31', '2022-12-31', NULL, 15, 'Successful Update');
SELECT source_row_id, target_entity_ids, status, error_message FROM import.set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);

\echo 'Final state of target table (expected complete history):'
SELECT * FROM (VALUES
    (3, 1, '2020-12-31'::DATE, '2021-12-31'::DATE, 'NewCo INSERT'::TEXT, 10, 'Initial Insert'::TEXT),
    (3, 1, '2021-12-31'::DATE, '2022-12-31'::DATE, 'NewCo INSERT'::TEXT, 15, 'Successful Update'::TEXT)
) AS t (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment);
\echo 'Actual state of target table:'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_orchestrator.establishment WHERE id = 3 ORDER BY valid_after;
RELEASE SAVEPOINT before_wrong_order;
DROP TABLE temp_source;

-- Cleanup
DROP PROCEDURE set_test_orchestrator.reset_target();
DROP TABLE set_test_orchestrator.establishment;
DROP TABLE set_test_orchestrator.legal_unit;
DROP SEQUENCE set_test_orchestrator.establishment_id_seq;
DROP SEQUENCE set_test_orchestrator.legal_unit_id_seq;
DROP SCHEMA set_test_orchestrator CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

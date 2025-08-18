BEGIN;
\i test/setup.sql

\echo '----------------------------------------------------------------------------'
\echo 'Test: import.plan_set_insert_or_replace_generic_valid_time_table'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE;

-- Setup: Create necessary schema and tables for this test
CREATE SCHEMA IF NOT EXISTS set_test_replace;
CREATE SEQUENCE IF NOT EXISTS set_test_replace.legal_unit_id_seq;

-- Target table for the upsert operation, modeling public.legal_unit
CREATE TABLE set_test_replace.legal_unit (
    id INT NOT NULL,
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    name TEXT,
    edit_comment TEXT, -- Ephemeral column
    PRIMARY KEY (id, valid_after)
);
SELECT sql_saga.add_era('set_test_replace.legal_unit', 'valid_after', 'valid_to');
SELECT sql_saga.add_unique_key('set_test_replace.legal_unit', ARRAY['id']);

-- Helper procedure to reset the target table for a new scenario
CREATE OR REPLACE PROCEDURE set_test_replace.reset_target() AS $$
BEGIN
    TRUNCATE set_test_replace.legal_unit RESTART IDENTITY CASCADE;
    ALTER SEQUENCE set_test_replace.legal_unit_id_seq RESTART WITH 1;
    -- Add unrelated data that should not be affected by the tests
    INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name) VALUES
    (99, '2023-12-31', '2024-12-31', 'Unaffected LU'),
    (100, '2023-01-31', 'infinity', 'Another Unaffected LU');
END;
$$ LANGUAGE plpgsql;

-- Parameters for the set-based function
\set target_schema 'set_test_replace'
\set target_table 'legal_unit'
\set target_entity_id_col 'id'
\set source_schema 'pg_temp'
\set source_entity_id_col 'legal_unit_id'
\set ephemeral_cols '{edit_comment}'

-- Scenario 1: Initial Insert of a new entity
\echo 'Scenario 1: Initial Insert of a new entity'
CALL set_test_replace.reset_target();
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (101, nextval('set_test_replace.legal_unit_id_seq'), '2023-12-31', '2024-12-31', 'New LU', 'Initial Insert');
\echo 'Generated Plan (Scenario 1):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 2: `equals` relation
\echo 'Scenario 2: `equals` relation (source replaces existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-12-31', 'Old Name', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (102, 1, '2023-12-31', '2024-12-31', 'New Name', 'Replaced');
\echo 'Generated Plan (Scenario 2):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 3: `during` (Source inside Existing)
\echo 'Scenario 3: `during` relation (source splits existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-12-31', 'Original Name', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (103, 1, '2024-03-31', '2024-08-31', 'Temporary Name', 'Split');
\echo 'Generated Plan (Scenario 3):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 4: `contains` (Existing inside Source)
\echo 'Scenario 4: `contains` relation (source envelops existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-03-31', '2024-08-31', 'Old Name', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (104, 1, '2023-12-31', '2024-12-31', 'New Overarching Name', 'Envelop');
\echo 'Generated Plan (Scenario 4):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 5: Multiple non-overlapping source rows replacing a single existing row
\echo 'Scenario 5: Multiple non-overlapping source rows'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-12-31', 'Original Full Year', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES
(109, 1, '2024-01-31', '2024-03-31', 'Name B', 'Part B'),
(110, 1, '2024-06-30', '2024-08-31', 'Name C', 'Part C');
\echo 'Generated Plan (Scenario 5):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 6: `starts` relation
\echo 'Scenario 6: `starts` relation (source truncates start of existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', 'infinity', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (105, 1, '2023-12-31', '2024-06-30', 'Starts New', 'Starts');
\echo 'Generated Plan (Scenario 6):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 7: `finishes` relation
\echo 'Scenario 7: `finishes` relation (source truncates end of existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-06-30', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (106, 1, '2024-01-31', '2024-06-30', 'Finishes New', 'Finishes');
\echo 'Generated Plan (Scenario 7):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 8: `overlaps` relation
\echo 'Scenario 8: `overlaps` relation'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-03-31', '2024-08-31', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (107, 1, '2023-12-31', '2024-06-30', 'Overlaps New', 'Overlaps');
\echo 'Generated Plan (Scenario 8):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 9: `meets` relation (different data)
\echo 'Scenario 9: `meets` relation (different data)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-03-31', '2024-08-31', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (108, 1, '2023-12-31', '2024-03-31', 'Meets New', 'Meets new');
\echo 'Generated Plan (Scenario 9):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 10: `meets` relation (same data, should coalesce)
\echo 'Scenario 10: `meets` relation (same data, should coalesce)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-03-31', '2024-08-31', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (109, 1, '2023-12-31', '2024-03-31', 'Original', 'Meets same');
\echo 'Generated Plan (Scenario 10):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 11: `met_by` relation
\echo 'Scenario 11: `met_by` relation (source is met by existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-03-31', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (111, 1, '2024-03-31', '2024-08-31', 'Met By New', 'Met By');
\echo 'Generated Plan (Scenario 11):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 12: `preceded_by` relation (no interaction)
\echo 'Scenario 12: `preceded_by` relation (no interaction)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-08-31', '2024-12-31', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (112, 1, '2023-12-31', '2024-03-31', 'Preceded By New', 'Preceded By');
\echo 'Generated Plan (Scenario 12):'
SELECT * FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Cleanup
DROP PROCEDURE set_test_replace.reset_target();
DROP TABLE set_test_replace.legal_unit;
DROP SEQUENCE set_test_replace.legal_unit_id_seq;
DROP SCHEMA set_test_replace CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

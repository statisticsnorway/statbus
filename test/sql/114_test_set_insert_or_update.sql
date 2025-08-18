BEGIN;
\i test/setup.sql

\echo '----------------------------------------------------------------------------'
\echo 'Test: import.plan_set_insert_or_update_generic_valid_time_table'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE;

-- Setup: Create necessary schema and tables for this test
CREATE SCHEMA IF NOT EXISTS set_test_update;
GRANT USAGE ON SCHEMA set_test_update TO PUBLIC;
CREATE SEQUENCE IF NOT EXISTS set_test_update.legal_unit_id_seq;
CREATE SEQUENCE IF NOT EXISTS set_test_update.establishment_id_seq;

-- Parent table: legal_unit
CREATE TABLE set_test_update.legal_unit (
    id INT NOT NULL,
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    name TEXT,
    PRIMARY KEY (id, valid_after)
);
SELECT sql_saga.add_era('set_test_update.legal_unit', 'valid_after', 'valid_to');
-- Give the unique key a deterministic name for the FK to reference
SELECT sql_saga.add_unique_key('set_test_update.legal_unit', ARRAY['id'], 'valid', 'legal_unit_id_uk');

-- Target table: establishment (with temporal FK to legal_unit)
CREATE TABLE set_test_update.establishment (
    id INT NOT NULL,
    legal_unit_id INT, -- Temporal FK
    valid_after DATE NOT NULL,
    valid_to DATE NOT NULL,
    name TEXT,
    employees INT,
    edit_comment TEXT, -- Ephemeral column
    PRIMARY KEY (id, valid_after)
);
SELECT sql_saga.add_era('set_test_update.establishment', 'valid_after', 'valid_to');
-- Give the unique key a deterministic name for consistency
SELECT sql_saga.add_unique_key('set_test_update.establishment', ARRAY['id'], 'valid', 'establishment_id_uk');
-- Reference the deterministically-named UK on the parent table.
-- With the bug in sql_saga's C-triggers fixed, this will now correctly validate
-- against set_test_update.legal_unit.
SELECT sql_saga.add_foreign_key('set_test_update.establishment', ARRAY['legal_unit_id'], 'valid', 'legal_unit_id_uk');

-- Grant permissions for sql_saga triggers to work correctly
GRANT SELECT ON set_test_update.legal_unit TO PUBLIC;
-- Helper procedure to reset the target table for a new scenario
CREATE OR REPLACE PROCEDURE set_test_update.reset_target() AS $$
BEGIN
    TRUNCATE set_test_update.legal_unit, set_test_update.establishment RESTART IDENTITY CASCADE;
    ALTER SEQUENCE set_test_update.legal_unit_id_seq RESTART WITH 1;
    ALTER SEQUENCE set_test_update.establishment_id_seq RESTART WITH 1;
    -- Add parent data and unrelated data that should not be affected by the tests
    INSERT INTO set_test_update.legal_unit (id, valid_after, valid_to, name) VALUES
    (1, '2023-12-30', 'infinity', 'Parent LU 1'),
    (99, '2023-12-30', 'infinity', 'Unaffected LU');
    INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees) VALUES
    (999, 99, '2023-12-31', '2024-12-31', 'Unaffected EST', 99);
END;
$$ LANGUAGE plpgsql;

-- Parameters for the set-based function
\set target_schema 'set_test_update'
\set target_table 'establishment'
\set target_entity_id_col 'id'
\set source_schema 'pg_temp'
\set source_entity_id_col 'establishment_id'
\set ephemeral_cols '{edit_comment}'

-- Scenario 1: Initial Insert of a new entity
\echo 'Scenario 1: Initial Insert of a new entity'
CALL set_test_update.reset_target();
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (101, 1, nextval('set_test_update.establishment_id_seq'), '2023-12-31', '2024-12-31', 'New EST', 10, 'Initial Insert');
\echo 'Generated Plan (Scenario 1):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 2: Source `during` Existing, partial update (NULL in source)
\echo 'Scenario 2: Source `during` Existing, partial update (Split)'
CALL set_test_update.reset_target();
INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2023-12-31', '2024-12-31', 'Original Name', 10, 'Original');
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (102, 1, 1, '2024-03-31', '2024-08-31', NULL, 20, 'Updated part'); -- name is NULL, employees changes
\echo 'Generated Plan (Scenario 2):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 3: `meets` relation, equivalent data (should merge)
\echo 'Scenario 3: `meets` relation, equivalent data (should merge)'
CALL set_test_update.reset_target();
INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2024-03-31', '2024-08-31', 'Same Name', 10, 'Original');
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (103, 1, 1, '2023-12-31', '2024-03-31', 'Same Name', 10, 'Meets and Merges');
\echo 'Generated Plan (Scenario 3):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 4: Source refers to gappy parent timeline
\echo 'Scenario 4: Source refers to gappy parent timeline'
CALL set_test_update.reset_target();
TRUNCATE set_test_update.legal_unit RESTART IDENTITY CASCADE;
-- Create a parent LU with a gap in its timeline
INSERT INTO set_test_update.legal_unit (id, valid_after, valid_to, name) VALUES
    (1, '2023-12-31', '2024-03-31', 'Parent LU 1 (Part 1)'),
    (1, '2024-08-31', 'infinity', 'Parent LU 1 (Part 2)');
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (104, 1, nextval('set_test_update.establishment_id_seq'), '2023-12-31', 'infinity', 'EST spanning gap', 10, 'This plan is valid, but would fail sql_saga constraint on execution');
\echo 'Generated Plan (Scenario 4):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 5: `equals` relation, partial update
\echo 'Scenario 5: `equals` relation, partial update'
CALL set_test_update.reset_target();
INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2023-12-31', '2024-12-31', 'Original Name', 10, 'Original');
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES (105, 1, 1, '2023-12-31', '2024-12-31', 'New Name', NULL, 'Replaced'); -- employees is NULL
\echo 'Generated Plan (Scenario 5):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 6: `contains` relation (Existing inside Source)
\echo 'Scenario 6: `contains` relation (source envelops existing)'
CALL set_test_update.reset_target();
INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2024-03-31', '2024-08-31', 'Old Name', 10, 'Original');
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES (106, 1, 1, '2023-12-31', '2024-12-31', 'New Overarching Name', NULL, 'Envelop');
\echo 'Generated Plan (Scenario 6):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 7: `starts` relation
\echo 'Scenario 7: `starts` relation (source truncates start of existing)'
CALL set_test_update.reset_target();
INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2023-12-31', 'infinity', 'Original', 10, 'Original');
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES (107, 1, 1, '2023-12-31', '2024-06-30', 'Starts New', 20, 'Starts');
\echo 'Generated Plan (Scenario 7):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 8: `finishes` relation
\echo 'Scenario 8: `finishes` relation (source truncates end of existing)'
CALL set_test_update.reset_target();
INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2023-12-31', '2024-06-30', 'Original', 10, 'Original');
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES (108, 1, 1, '2024-01-31', '2024-06-30', 'Finishes New', NULL, 'Finishes');
\echo 'Generated Plan (Scenario 8):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 9: `overlaps` relation
\echo 'Scenario 9: `overlaps` relation'
CALL set_test_update.reset_target();
INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2024-03-31', '2024-08-31', 'Original', 10, 'Original');
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES (109, 1, 1, '2023-12-31', '2024-06-30', 'Overlaps New', 20, 'Overlaps');
\echo 'Generated Plan (Scenario 9):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 10: `met_by` relation
\echo 'Scenario 10: `met_by` relation (source is met by existing)'
CALL set_test_update.reset_target();
INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2023-12-31', '2024-03-31', 'Original', 10, 'Original');
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES (110, 1, 1, '2024-03-31', '2024-08-31', 'Met By New', 20, 'Met By');
\echo 'Generated Plan (Scenario 10):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 11: `precedes` relation (no interaction)
\echo 'Scenario 11: `precedes` relation (no interaction)'
CALL set_test_update.reset_target();
INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2024-08-31', '2024-12-31', 'Original', 10, 'Original');
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES (111, 1, 1, '2023-12-31', '2024-03-31', 'Precedes New', 20, 'Precedes');
\echo 'Generated Plan (Scenario 11):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 12: `preceded_by` relation (no interaction)
\echo 'Scenario 12: `preceded_by` relation (no interaction)'
CALL set_test_update.reset_target();
INSERT INTO set_test_update.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2023-12-31', '2024-03-31', 'Original', 10, 'Original');
CREATE TEMP TABLE temp_source ( row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES (112, 1, 1, '2024-08-31', '2024-12-31', 'Preceded By New', 20, 'Preceded By');
\echo 'Generated Plan (Scenario 12):'
SELECT * FROM import.plan_set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Cleanup
DROP PROCEDURE set_test_update.reset_target();
DROP TABLE set_test_update.establishment;
DROP TABLE set_test_update.legal_unit;
DROP SEQUENCE set_test_update.establishment_id_seq;
DROP SEQUENCE set_test_update.legal_unit_id_seq;
DROP SCHEMA set_test_update CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

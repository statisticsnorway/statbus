BEGIN;
\i test/setup.sql

\echo '----------------------------------------------------------------------------'
\echo 'Test: import.set_insert_or_update_generic_valid_time_table orchestrator'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE;

-- Setup: Create necessary schema and tables for this test
CREATE SCHEMA IF NOT EXISTS set_test_orchestrator;
GRANT USAGE ON SCHEMA set_test_orchestrator TO PUBLIC;
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

-- Grant permissions for sql_saga triggers to work correctly
GRANT SELECT ON set_test_orchestrator.legal_unit TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON set_test_orchestrator.establishment TO PUBLIC;

-- Helper procedure to reset the target table for a new scenario
CREATE OR REPLACE PROCEDURE set_test_orchestrator.reset_target() AS $$
BEGIN
    TRUNCATE set_test_orchestrator.legal_unit, set_test_orchestrator.establishment RESTART IDENTITY CASCADE;
    ALTER SEQUENCE set_test_orchestrator.legal_unit_id_seq RESTART WITH 1;
    ALTER SEQUENCE set_test_orchestrator.establishment_id_seq RESTART WITH 1;
    -- Add parent data
    INSERT INTO set_test_orchestrator.legal_unit (id, valid_after, valid_to, name) VALUES
    (1, '2023-12-30', 'infinity', 'Parent LU 1');
END;
$$ LANGUAGE plpgsql;

-- Parameters for the set-based function
\set target_schema 'set_test_orchestrator'
\set target_table 'establishment'
\set target_entity_id_col 'id'
\set source_schema 'pg_temp'
\set source_entity_id_col 'establishment_id'
\set ephemeral_cols '{edit_comment}'

--------------------------------------------------------------------------------
-- Test `set_insert_or_update`
--------------------------------------------------------------------------------
\echo 'Test Case 1: `set_insert_or_update` with a `during` relation (split)'
CALL set_test_orchestrator.reset_target();
INSERT INTO set_test_orchestrator.establishment (id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment) VALUES (1, 1, '2023-12-31', '2024-12-31', 'Original Name', 10, 'Original');
CREATE TEMP TABLE temp_source (
    row_id INT, legal_unit_id INT, establishment_id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, employees INT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (101, 1, 1, '2024-03-31', '2024-08-31', NULL, 20, 'Updated part'); -- name is NULL, employees changes
\echo 'Calling orchestrator...'
SELECT * FROM import.set_insert_or_update_generic_valid_time_table(:'target_schema', :'target_table', :'target_entity_id_col', :'source_schema', 'temp_source', :'source_entity_id_col', NULL, :'ephemeral_cols'::TEXT[]);
\echo 'Final state of target table:'
SELECT id, legal_unit_id, valid_after, valid_to, name, employees, edit_comment FROM set_test_orchestrator.establishment WHERE id = 1 ORDER BY valid_after;
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

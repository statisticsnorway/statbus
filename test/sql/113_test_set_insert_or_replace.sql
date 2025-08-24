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
\set entity_id_cols '{id}'
\set source_schema 'pg_temp'
\set ephemeral_cols '{edit_comment}'

-- Scenario 1: Initial Insert of a new entity
\echo 'Scenario 1: Initial Insert of a new entity'
CALL set_test_replace.reset_target();
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source (row_id, id, valid_after, valid_to, name, edit_comment) VALUES (101, nextval('set_test_replace.legal_unit_id_seq'), '2023-12-31', '2024-12-31', 'New LU', 'Initial Insert');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{101}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "New LU"}'::JSONB, NULL::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 2: `equals` relation
\echo 'Scenario 2: `equals` relation (source replaces existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-12-31', 'Old Name', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (102, 1, '2023-12-31', '2024-12-31', 'New Name', 'Replaced');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{102}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "New Name"}'::JSONB, 'equals'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 2b: `equals` relation with NULL in source
\echo 'Scenario 2b: `equals` relation (source NULL should replace existing value)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-12-31', 'Old Name', 'Old Comment');
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (102, 1, '2023-12-31', '2024-12-31', NULL, 'Replaced with NULL');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{102}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": null}'::JSONB, 'equals'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 3: `during` (Source inside Existing)
\echo 'Scenario 3: `during` relation (source splits existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-12-31', 'Original Name', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (103, 1, '2024-03-31', '2024-08-31', 'Temporary Name', 'Split');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{103}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-03-31'::DATE, '{"name": "Original Name"}'::JSONB, 'during'::public.allen_interval_relation),
    ('{103}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-03-31'::DATE, '2024-08-31'::DATE, '{"name": "Temporary Name"}'::JSONB, 'during'::public.allen_interval_relation),
    ('{103}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-08-31'::DATE, '2024-12-31'::DATE, '{"name": "Original Name"}'::JSONB, 'during'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 4: `contains` (Existing inside Source)
\echo 'Scenario 4: `contains` relation (source envelops existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-03-31', '2024-08-31', 'Old Name', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (104, 1, '2023-12-31', '2024-12-31', 'New Overarching Name', 'Envelop');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{104}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2024-03-31'::DATE, '2023-12-31'::DATE, '2024-12-31'::DATE, '{"name": "New Overarching Name", "edit_comment": "Envelop"}'::JSONB, 'contains'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 5: Multiple non-overlapping source rows replacing a single existing row
\echo 'Scenario 5: Multiple non-overlapping source rows'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-12-31', 'Original Full Year', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES
(109, 1, '2024-01-31', '2024-03-31', 'Name B', 'Part B'),
(110, 1, '2024-06-30', '2024-08-31', 'Name C', 'Part C');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{109}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-01-31'::DATE, '{"name": "Original Full Year"}'::JSONB, 'during'::public.allen_interval_relation),
    ('{109}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-01-31'::DATE, '2024-03-31'::DATE, '{"name": "Name B"}'::JSONB, 'during'::public.allen_interval_relation),
    ('{109}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-03-31'::DATE, '2024-06-30'::DATE, '{"name": "Original Full Year"}'::JSONB, 'during'::public.allen_interval_relation),
    ('{110}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-06-30'::DATE, '2024-08-31'::DATE, '{"name": "Name C"}'::JSONB, 'during'::public.allen_interval_relation),
    ('{110}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-08-31'::DATE, '2024-12-31'::DATE, '{"name": "Original Full Year"}'::JSONB, 'during'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 6: `starts` relation
\echo 'Scenario 6: `starts` relation (source truncates start of existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', 'infinity', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (105, 1, '2023-12-31', '2024-06-30', 'Starts New', 'Starts');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{105}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-06-30'::DATE, '{"name": "Starts New"}'::JSONB, 'starts'::public.allen_interval_relation),
    ('{105}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-06-30'::DATE, 'infinity'::DATE, '{"name": "Original"}'::JSONB, 'starts'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 7: `finishes` relation
\echo 'Scenario 7: `finishes` relation (source truncates end of existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-06-30', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (106, 1, '2024-01-31', '2024-06-30', 'Finishes New', 'Finishes');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{106}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-01-31'::DATE, '{"name": "Original"}'::JSONB, 'finishes'::public.allen_interval_relation),
    ('{106}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-01-31'::DATE, '2024-06-30'::DATE, '{"name": "Finishes New"}'::JSONB, 'finishes'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 8: `overlaps` relation
\echo 'Scenario 8: `overlaps` relation'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-03-31', '2024-08-31', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (107, 1, '2023-12-31', '2024-06-30', 'Overlaps New', 'Overlaps');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{107}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2024-03-31'::DATE, '2024-06-30'::DATE, '2024-08-31'::DATE, '{"name": "Original"}'::JSONB, 'overlaps'::public.allen_interval_relation),
    ('{107}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2023-12-31'::DATE, '2024-06-30'::DATE, '{"name": "Overlaps New"}'::JSONB, 'overlaps'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 9: `meets` relation (different data)
\echo 'Scenario 9: `meets` relation (different data)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-03-31', '2024-08-31', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (108, 1, '2023-12-31', '2024-03-31', 'Meets New', 'Meets new');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{108}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2023-12-31'::DATE, '2024-03-31'::DATE, '{"name": "Meets New", "edit_comment": "Meets new"}'::JSONB, 'meets'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 10: `meets` relation (same data, should coalesce)
\echo 'Scenario 10: `meets` relation (same data, should coalesce)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-03-31', '2024-08-31', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (109, 1, '2023-12-31', '2024-03-31', 'Original', 'Meets same');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{109}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2024-03-31'::DATE, '2023-12-31'::DATE, '2024-08-31'::DATE, '{"name": "Original"}'::JSONB, 'meets'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 11: `met_by` relation
\echo 'Scenario 11: `met_by` relation (source is met by existing)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-03-31', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (111, 1, '2024-03-31', '2024-08-31', 'Met By New', 'Met By');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{111}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-03-31'::DATE, '2024-08-31'::DATE, '{"name": "Met By New", "edit_comment": "Met By"}'::JSONB, 'met_by'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 12: `preceded_by` relation (no interaction)
\echo 'Scenario 12: `preceded_by` relation (no interaction)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-08-31', '2024-12-31', 'Original', NULL);
CREATE TEMP TABLE temp_source (
    row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT
) ON COMMIT DROP;
INSERT INTO temp_source VALUES (112, 1, '2023-12-31', '2024-03-31', 'Preceded By New', 'Preceded By');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{112}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2023-12-31'::DATE, '2024-03-31'::DATE, '{"name": "Preceded By New"}'::JSONB, 'precedes'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 13: Replace affects one slice, should preserve other unrelated slices for the same entity
\echo 'Scenario 13: Replace should preserve non-interacting historical slices'
CALL set_test_replace.reset_target();
-- Two historical, non-contiguous records for entity 1
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES
(1, '2023-12-31', '2024-03-31', 'History Part 1', 'Original 1'),
(1, '2024-08-31', '2024-12-31', 'History Part 2', 'Original 2');
CREATE TEMP TABLE temp_source ( row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT ) ON COMMIT DROP;
-- Source data only interacts with "History Part 1"
INSERT INTO temp_source VALUES (113, 1, '2024-01-31', '2024-02-29', 'Updated Slice', 'Update');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{113}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-01-31'::DATE, '{"name": "History Part 1"}'::JSONB, 'during'::public.allen_interval_relation),
    ('{113}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-01-31'::DATE, '2024-02-29'::DATE, '{"name": "Updated Slice"}'::JSONB, 'during'::public.allen_interval_relation),
    ('{113}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-02-29'::DATE, '2024-03-31'::DATE, '{"name": "History Part 1"}'::JSONB, 'during'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 14: Adjacent but non-contiguous source rows with same data should not coalesce
\echo 'Scenario 14: Adjacent but non-contiguous source rows with same data should not coalesce'
CALL set_test_replace.reset_target();
-- No initial target data for this entity
CREATE TEMP TABLE temp_source ( row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT ) ON COMMIT DROP;
-- Two source rows with identical data but a one-day gap between them
INSERT INTO temp_source VALUES
(114, 1, '2024-01-31', '2024-03-31', 'Same Data', 'Part A'),
(115, 1, '2024-04-01', '2024-06-30', 'Same Data', 'Part B');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{114}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-01-31'::DATE, '2024-03-31'::DATE, '{"name": "Same Data", "edit_comment": "Part A"}'::JSONB, NULL::public.allen_interval_relation),
    ('{115}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-04-01'::DATE, '2024-06-30'::DATE, '{"name": "Same Data", "edit_comment": "Part B"}'::JSONB, NULL::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 15: `meets` relation, same core data, different ephemeral data (should merge and update ephemeral)
\echo 'Scenario 15: `meets` relation, same core data, different ephemeral data (should merge and update ephemeral)'
CALL set_test_replace.reset_target();
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2024-01-31', '2024-03-31', 'Same Core', 'Comment A');
CREATE TEMP TABLE temp_source ( row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT ) ON COMMIT DROP;
INSERT INTO temp_source VALUES (116, 1, '2024-03-31', '2024-06-30', 'Same Core', 'Comment B');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{116}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2024-01-31'::DATE, '2024-01-31'::DATE, '2024-06-30'::DATE, '{"name": "Same Core", "edit_comment": "Comment B"}'::JSONB, 'met_by'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 16: Contiguous source rows with same core data should coalesce
\echo 'Scenario 16: Contiguous source rows with same core data should coalesce'
CALL set_test_replace.reset_target();
-- No initial target data for this entity
CREATE TEMP TABLE temp_source ( row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT ) ON COMMIT DROP;
-- Two source rows with identical core data and different ephemeral data, and are contiguous
INSERT INTO temp_source VALUES
(117, 1, '2024-01-31', '2024-03-31', 'Same Data', 'Part A'),
(118, 1, '2024-03-31', '2024-06-30', 'Same Data', 'Part B');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    ('{117,118}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-01-31'::DATE, '2024-06-30'::DATE, '{"name": "Same Data", "edit_comment": "Part B"}'::JSONB, NULL::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 17: Test causal attribution with multiple source rows splitting a target row
\echo 'Scenario 17: Test causal attribution with multiple source rows splitting a target row'
CALL set_test_replace.reset_target();
-- Target has one continuous record
INSERT INTO set_test_replace.legal_unit (id, valid_after, valid_to, name, edit_comment) VALUES (1, '2023-12-31', '2024-12-31', 'Original', 'Original Comment');
CREATE TEMP TABLE temp_source ( row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT ) ON COMMIT DROP;
-- Two source rows that split the target, creating a preserved segment between them
INSERT INTO temp_source VALUES
(119, 1, '2024-02-29', '2024-04-01', 'Update A', 'Caused by 119'),
(120, 1, '2024-08-31', '2024-10-01', 'Update B', 'Caused by 120');
\echo 'Expected plan:'
SELECT * FROM (VALUES
    -- Preserved start segment, caused by the first interacting source row (119)
    ('{119}'::INT[], 'UPDATE'::import.plan_operation_type, 1, '2023-12-31'::DATE, '2023-12-31'::DATE, '2024-02-29'::DATE, '{"name": "Original"}'::JSONB, 'during'::public.allen_interval_relation),
    -- Inserted segment from source row 119
    ('{119}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-02-29'::DATE, '2024-04-01'::DATE, '{"name": "Update A"}'::JSONB, 'during'::public.allen_interval_relation),
    -- Preserved middle segment. Should be attributed to the closest preceding source row (119)
    ('{119}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-04-01'::DATE, '2024-08-31'::DATE, '{"name": "Original"}'::JSONB, 'during'::public.allen_interval_relation),
    -- Inserted segment from source row 120
    ('{120}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-08-31'::DATE, '2024-10-01'::DATE, '{"name": "Update B"}'::JSONB, 'during'::public.allen_interval_relation),
    -- Preserved end segment, caused by the second interacting source row (120)
    ('{120}'::INT[], 'INSERT'::import.plan_operation_type, 1, NULL::DATE, '2024-10-01'::DATE, '2024-12-31'::DATE, '{"name": "Original"}'::JSONB, 'during'::public.allen_interval_relation)
) AS t (source_row_ids, operation, entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation);
\echo 'Actual plan:'
SELECT source_row_ids, operation, (entity_ids->>'id')::INT AS entity_id, old_valid_after, new_valid_after, new_valid_to, data, relation FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Scenario 18: REPLACE on non-existent entity should produce no plan
\echo 'Scenario 18: REPLACE on non-existent entity should produce no plan'
CALL set_test_replace.reset_target();
CREATE TEMP TABLE temp_source ( row_id INT, id INT, valid_after DATE NOT NULL, valid_to DATE NOT NULL, name TEXT, edit_comment TEXT ) ON COMMIT DROP;
-- Source row for entity ID 5, which does not exist in the target table.
INSERT INTO temp_source VALUES (121, 5, '2024-01-01', '2024-12-31', 'Should not be inserted', 'NOOP');
\echo 'Expected plan (0 rows):'
SELECT 0 as row_count WHERE NOT EXISTS (SELECT 1 FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]));
\echo 'Actual plan (count):'
SELECT count(*) as row_count FROM import.plan_set_insert_or_replace_generic_valid_time_table(:'target_schema', :'target_table', :'source_schema', 'temp_source', :'entity_id_cols'::TEXT[], NULL, :'ephemeral_cols'::TEXT[]);
DROP TABLE temp_source;

-- Cleanup
DROP PROCEDURE set_test_replace.reset_target();
DROP TABLE set_test_replace.legal_unit;
DROP SEQUENCE set_test_replace.legal_unit_id_seq;
DROP SCHEMA set_test_replace CASCADE;

SET client_min_messages TO NOTICE;
ROLLBACK;

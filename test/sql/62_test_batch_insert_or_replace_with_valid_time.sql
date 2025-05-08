BEGIN;

\echo '----------------------------------------------------------------------------'
\echo 'Test: admin.batch_insert_or_replace_generic_valid_time_table'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE; -- Changed from DEBUG1 to NOTICE

-- Setup: Create necessary schema and tables
CREATE SCHEMA IF NOT EXISTS batch_test; -- Use dedicated schema

CREATE SEQUENCE IF NOT EXISTS batch_test.batch_upsert_target_id_seq;

-- Target table for the upsert operation
CREATE TABLE batch_test.batch_upsert_target (
    id INT NOT NULL DEFAULT nextval('batch_test.batch_upsert_target_id_seq'),
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL,
    value_a TEXT,
    value_b INT,
    edit_comment TEXT, -- Ephemeral column
    PRIMARY KEY (id, valid_from)
);

-- Source table containing data to be upserted
CREATE TABLE batch_test.batch_upsert_source (
    row_id BIGSERIAL PRIMARY KEY, -- Source row identifier
    target_id INT, -- ID in the target table (can be null for lookup)
    valid_from DATE NOT NULL,
    valid_to DATE, -- Allow NULL for testing error case
    value_a TEXT,
    value_b INT,
    edit_comment TEXT
);

-- Parameters for the batch upsert function
\set target_schema 'batch_test'
\set target_table 'batch_upsert_target'
\set source_schema 'batch_test'
\set source_table 'batch_upsert_source'
\set source_row_id_col 'row_id'
-- Define variables without outer SQL quotes
\set unique_cols '[ "value_a" ]'
\set temporal_cols '{valid_from, valid_to}'
\set ephemeral_cols '{edit_comment}'
\set id_col 'id'

-- Function to display target table contents easily
CREATE OR REPLACE FUNCTION batch_test.show_target_table(p_filter_id INT DEFAULT NULL)
RETURNS TABLE (id INT, valid_from DATE, valid_to DATE, value_a TEXT, value_b INT, edit_comment TEXT) AS $$
BEGIN
    IF p_filter_id IS NULL THEN
        RETURN QUERY SELECT tgt.id, tgt.valid_from, tgt.valid_to, tgt.value_a, tgt.value_b, tgt.edit_comment 
                     FROM batch_test.batch_upsert_target tgt ORDER BY tgt.id, tgt.valid_from;
    ELSE
        RETURN QUERY SELECT tgt.id, tgt.valid_from, tgt.valid_to, tgt.value_a, tgt.value_b, tgt.edit_comment 
                     FROM batch_test.batch_upsert_target tgt WHERE tgt.id = p_filter_id ORDER BY tgt.valid_from;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 1. Initial Insert
\echo 'Scenario 1: Initial Insert'
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(NULL, '2024-01-01', '2024-12-31', 'A', 10, 'Initial A');

-- Use SQL quotes around the variable, then cast
SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(); -- Show all, expect one row with new ID
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE;
DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 2. Adjacent Equivalent Merge
\echo 'Scenario 2: Adjacent Equivalent Merge'
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-01-01', '2024-06-30', 'A', 10, 'First half');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-07-01', '2024-12-31', 'A', 10, 'Second half'); -- Same data

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one merged row for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 3. Adjacent Different (No Merge)
\echo 'Scenario 3: Adjacent Different (No Merge)'
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-01-01', '2024-06-30', 'A', 10, 'First half');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-07-01', '2024-12-31', 'B', 20, 'Second half different'); -- Different data

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be two separate rows for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 4. Overlap Start Equivalent
\echo 'Scenario 4: Overlap Start Equivalent'
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-03-01', '2024-12-31', 'A', 10, 'Existing March-Dec');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-01-01', '2024-05-31', 'A', 10, 'New Jan-May'); -- Same data, overlaps start

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one row Jan-Dec for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 5. Overlap Start Different
\echo 'Scenario 5: Overlap Start Different'
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-03-01', '2024-12-31', 'A', 10, 'Existing March-Dec');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-01-01', '2024-05-31', 'B', 20, 'New Jan-May Different'); -- Different data

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be New Jan-May (B), Existing June-Dec (A) for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 6. Overlap End Equivalent
\echo 'Scenario 6: Overlap End Equivalent'
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-01-01', '2024-09-30', 'A', 10, 'Existing Jan-Sep');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-07-01', '2024-12-31', 'A', 10, 'New Jul-Dec'); -- Same data, overlaps end

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one row Jan-Dec for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 7. Overlap End Different
\echo 'Scenario 7: Overlap End Different'
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-01-01', '2024-09-30', 'A', 10, 'Existing Jan-Sep');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-07-01', '2024-12-31', 'B', 20, 'New Jul-Dec Different'); -- Different data

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be Existing Jan-Jun (A), New Jul-Dec (B) for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 8. Inside Equivalent
\echo 'Scenario 8: Inside Equivalent'
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-01-01', '2024-12-31', 'A', 10, 'Existing Jan-Dec');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-04-01', '2024-08-31', 'A', 10, 'New Apr-Aug'); -- Same data, inside

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one row Jan-Dec for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 9. Inside Different (Split)
\echo 'Scenario 9: Inside Different (Split)'
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-01-01', '2024-12-31', 'A', 10, 'Existing Jan-Dec');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-04-01', '2024-08-31', 'B', 20, 'New Apr-Aug Different'); -- Different data

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be Existing Jan-Mar (A), New Apr-Aug (B), Existing Sep-Dec (A) for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 10. Contains Existing
\echo 'Scenario 10: Contains Existing'
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-04-01', '2024-08-31', 'A', 10, 'Existing Apr-Aug');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-01-01', '2024-12-31', 'B', 20, 'New Jan-Dec Different'); -- Different data, contains existing

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one row Jan-Dec with value B for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 11. Batch Processing (Multiple IDs, Multiple Scenarios)
\echo 'Scenario 11: Batch Processing (Multiple IDs and Scenarios)'
-- ID 1 (will be new, e.g. seq val 1): Initial Insert
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(NULL, '2024-01-01', '2024-12-31', 'ID1', 11, 'ID1 Initial');
-- ID 2: Existing data
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(2, '2024-01-01', '2024-12-31', 'ID2-Old', 22, 'ID2 Existing');
-- ID 2: Source data to split existing ID2
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(2, '2024-05-01', '2024-08-31', 'ID2-New', 23, 'ID2 Split');
-- ID 3: Existing data
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(3, '2024-01-01', '2024-06-30', 'ID3', 33, 'ID3 First Half');
-- ID 3: Source data adjacent equivalent to merge
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(3, '2024-07-01', '2024-12-31', 'ID3', 33, 'ID3 Second Half Merge');
-- ID 4: Source data with error (null valid_to)
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(4, '2024-01-01', NULL, 'ID4-Error', 44, 'ID4 Error');

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
) ORDER BY source_row_id;

\echo 'Target table after batch:'
SELECT * FROM batch_test.show_target_table();
-- Expected:
-- ID for ID1 (e.g. 1): One row Jan-Dec, value ID1
-- ID 2: Three rows: Jan-Apr (ID2-Old), May-Aug (ID2-New), Sep-Dec (ID2-Old)
-- ID 3: One row Jan-Dec, value ID3
-- ID 4: No rows in target table

TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 12. ID Lookup using unique_columns
\echo 'Scenario 12: ID Lookup'
INSERT INTO batch_test.batch_upsert_target (id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(5, '2024-01-01', '2024-12-31', 'LookupMe', 50, 'Existing Lookup');
-- Source row has target_id = NULL, but value_a matches existing row
INSERT INTO batch_test.batch_upsert_source (target_id, valid_from, valid_to, value_a, value_b, edit_comment) VALUES
(NULL, '2024-06-01', '2024-09-30', 'LookupMe', 55, 'Update via Lookup'); -- Overlaps, different data

SELECT * FROM admin.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(5); -- Should have split the original row for ID 5
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- Cleanup
DROP FUNCTION batch_test.show_target_table(INT);
DROP TABLE batch_test.batch_upsert_source;
DROP TABLE batch_test.batch_upsert_target;
DROP SEQUENCE batch_test.batch_upsert_target_id_seq;
DROP SCHEMA batch_test CASCADE; -- Use CASCADE to drop schema and its contents

SET client_min_messages TO NOTICE; -- Keep NOTICE for the final ROLLBACK message
ROLLBACK; -- Rollback changes after test

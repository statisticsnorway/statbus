BEGIN;
\i test/setup.sql

\echo '----------------------------------------------------------------------------'
\echo 'Test: admin.batch_insert_or_replace_generic_valid_time_table'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE;

-- Setup: Create necessary schema and tables
CREATE SCHEMA IF NOT EXISTS batch_test; -- Use dedicated schema

CREATE SEQUENCE IF NOT EXISTS batch_test.batch_upsert_target_id_seq;

-- Target table for the upsert operation
CREATE TABLE batch_test.batch_upsert_target (
    id INT NOT NULL DEFAULT nextval('batch_test.batch_upsert_target_id_seq'),
    valid_after DATE NOT NULL, -- (exclusive start)
    valid_to DATE NOT NULL,    -- (inclusive end)
    value_a TEXT,
    value_b INT,
    edit_comment TEXT, -- Ephemeral column
    PRIMARY KEY (id, valid_after) -- PK uses valid_after
);

-- Source table containing data to be upserted
CREATE TABLE batch_test.batch_upsert_source (
    row_id BIGSERIAL PRIMARY KEY, -- Source row identifier
    target_id INT, -- ID in the target table (can be null for lookup)
    valid_after DATE NOT NULL, -- (exclusive start)
    valid_to DATE,             -- (inclusive end)
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
\set temporal_cols '{valid_after, valid_to}'
\set ephemeral_cols '{edit_comment}'
\set id_col 'id'

-- Function to display target table contents easily
CREATE OR REPLACE FUNCTION batch_test.show_target_table(p_filter_id INT DEFAULT NULL)
RETURNS TABLE (id INT, valid_after DATE, valid_to DATE, value_a TEXT, value_b INT, edit_comment TEXT) AS $$
BEGIN
    IF p_filter_id IS NULL THEN
        RETURN QUERY SELECT tgt.id, tgt.valid_after, tgt.valid_to, tgt.value_a, tgt.value_b, tgt.edit_comment 
                     FROM batch_test.batch_upsert_target tgt ORDER BY tgt.id, tgt.valid_after;
    ELSE
        RETURN QUERY SELECT tgt.id, tgt.valid_after, tgt.valid_to, tgt.value_a, tgt.value_b, tgt.edit_comment 
                     FROM batch_test.batch_upsert_target tgt WHERE tgt.id = p_filter_id ORDER BY tgt.id, tgt.valid_after;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 1. Initial Insert
\echo 'Scenario 1: Initial Insert'
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(NULL, '2023-12-31', '2024-12-31', 'A', 10, 'Initial A');

-- Use SQL quotes around the variable, then cast
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(); -- Show all, expect one row with new ID
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE;
DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 2. Adjacent Equivalent Merge
\echo 'Scenario 2: Adjacent Equivalent Merge'
-- SET client_min_messages TO DEBUG1; -- Scenario 2 is now passing
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-06-30', 'A', 10, 'First half');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-06-30', '2024-12-31', 'A', 10, 'Second half'); -- Same data, now adjacent with (]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one merged row for ID 1
-- SET client_min_messages TO NOTICE; -- Already NOTICE by default
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 3. Adjacent Different (No Merge)
\echo 'Scenario 3: Adjacent Different (No Merge)'
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-06-30', 'A', 10, 'First half');
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-06-30', '2024-12-31', 'B', 20, 'Second half different'); -- Different data, now adjacent with (]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be two separate rows for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 4. Overlap Start Equivalent
\echo 'Scenario 4: Overlap Start Equivalent'
-- SET client_min_messages TO DEBUG1;
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-02-29', '2024-12-31', 'A', 10, 'Existing March-Dec'); -- (Feb 29, Dec 31]
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 10, 'New Jan-May'); -- Same data, overlaps start (Dec 31, May 31]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one row Jan-Dec for ID 1
-- SET client_min_messages TO NOTICE;
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 5. Overlap Start Different
\echo 'Scenario 5: Overlap Start Different'
-- SET client_min_messages TO DEBUG1; -- Scenario 5 is now passing
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-02-29', '2024-12-31', 'A', 10, 'Existing March-Dec'); -- (Feb 29, Dec 31]
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'B', 20, 'New Jan-May Different'); -- Different data (Dec 31, May 31]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be New Jan-May (B), Existing June-Dec (A) for ID 1
-- SET client_min_messages TO NOTICE; -- Already NOTICE by default
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 6. Overlap End Equivalent
\echo 'Scenario 6: Overlap End Equivalent'
-- SET client_min_messages TO DEBUG1;
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-09-30', 'A', 10, 'Existing Jan-Sep'); -- (Dec 31, Sep 30]
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-06-30', '2024-12-31', 'A', 10, 'New Jul-Dec'); -- Same data, overlaps end (June 30, Dec 31]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one row Jan-Dec for ID 1
-- SET client_min_messages TO NOTICE;
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 7. Overlap End Different
\echo 'Scenario 7: Overlap End Different'
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-09-30', 'A', 10, 'Existing Jan-Sep'); -- (Dec 31, Sep 30]
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-06-30', '2024-12-31', 'B', 20, 'New Jul-Dec Different'); -- Different data (June 30, Dec 31]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be Existing Jan-Jun (A), New Jul-Dec (B) for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 8. Inside Equivalent
\echo 'Scenario 8: Inside Equivalent'
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 10, 'Existing Jan-Dec'); -- (Dec 31, Dec 31]
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-03-31', '2024-08-31', 'A', 10, 'New Apr-Aug'); -- Same data, inside (Mar 31, Aug 31]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one row Jan-Dec for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 9. Inside Different (Split)
\echo 'Scenario 9: Inside Different (Split)'
-- SET client_min_messages TO DEBUG1; -- Scenario 9 is now passing
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 10, 'Existing Jan-Dec'); -- (Dec 31, Dec 31]
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-03-31', '2024-08-31', 'B', 20, 'New Apr-Aug Different'); -- Different data (Mar 31, Aug 31]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be Existing Jan-Mar (A), New Apr-Aug (B), Existing Sep-Dec (A) for ID 1
-- SET client_min_messages TO NOTICE; -- Already NOTICE by default
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 10. Contains Existing
\echo 'Scenario 10: Contains Existing'
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-03-31', '2024-08-31', 'A', 10, 'Existing Apr-Aug'); -- (Mar 31, Aug 31]
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'B', 20, 'New Jan-Dec Different'); -- Different data, contains existing (Dec 31, Dec 31]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one row Jan-Dec with value B for ID 1
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 11. Batch Processing (Multiple IDs, Multiple Scenarios)
\echo 'Scenario 11: Batch Processing (Multiple IDs and Scenarios)'
-- ID 1 (will be new, e.g. seq val 1): Initial Insert
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(NULL, '2023-12-31', '2024-12-31', 'ID1', 11, 'ID1 Initial'); -- (Dec 31, Dec 31]
-- ID 2: Existing data
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(2, '2023-12-31', '2024-12-31', 'ID2-Old', 22, 'ID2 Existing'); -- (Dec 31, Dec 31]
-- ID 2: Source data to split existing ID2
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(2, '2024-04-30', '2024-08-31', 'ID2-New', 23, 'ID2 Split'); -- (Apr 30, Aug 31]
-- ID 3: Existing data
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(3, '2023-12-31', '2024-06-30', 'ID3', 33, 'ID3 First Half'); -- (Dec 31, June 30]
-- ID 3: Source data adjacent equivalent to merge
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(3, '2024-06-30', '2024-12-31', 'ID3', 33, 'ID3 Second Half Merge'); -- (June 30, Dec 31]
-- ID 4: Source data with error (null valid_to)
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(4, '2023-12-31', NULL, 'ID4-Error', 44, 'ID4 Error'); -- (Dec 31, NULL]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
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
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(5, '2023-12-31', '2024-12-31', 'LookupMe', 50, 'Existing Lookup'); -- (Dec 31, Dec 31]
-- Source row has target_id = NULL, but value_a matches existing row
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(NULL, '2024-05-31', '2024-09-30', 'LookupMe', 55, 'Update via Lookup'); -- Overlaps, different data (May 31, Sep 30]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(5); -- Should have split the original row for ID 5
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 13. Identical Period, Different Data, Full Replacement
\echo 'Scenario 13: Identical Period, Different Data, Full Replacement'
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'KeyForID1', 100, 'Original Version'); -- (Dec 31, Dec 31]
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'KeyForID1', 200, 'Updated Version'); -- Different value_b, identical period (Dec 31, Dec 31]

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, -- p_unique_columns is empty as target_id is provided
    :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Should be one row for ID 1, with value_b = 200
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 14. Equals Relation, Equivalent Data (No Change Expected)
\echo 'Scenario 14: Equals Relation, Equivalent Data'
-- SET client_min_messages TO DEBUG1; -- Scenario 14 is now passing
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'Equivalent', 100, 'Original Comment'); -- (Dec 31, Dec 31]
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'Equivalent', 100, 'Source Comment, Should Not Overwrite'); -- Identical data and period

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, -- p_unique_columns is empty as target_id is provided
    :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Expected: One row for ID 1, edit_comment = 'Original Comment'
-- SET client_min_messages TO NOTICE; -- Reverted as scenario is passing
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 15. Precedes Relation (Non-Overlapping, New record should be added)
\echo 'Scenario 15: Precedes Relation'
INSERT INTO batch_test.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2024-06-30', '2024-12-31', 'Later', 200, 'Later Record'); -- Existing: (June 30, Dec 31]
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', '2024-03-31', 'Earlier', 100, 'Earlier Record'); -- Source: (Dec 31, Mar 31] (precedes existing)

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, 
    :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1); -- Expected: Two rows for ID 1, one for earlier, one for later period
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target;
ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;


-- 16. A-A-B-A Sequence with yearly 'infinity' inputs (4 inputs -> 3 outputs)
\echo 'Scenario 16: A-A-B-A Sequence with yearly ''infinity'' inputs (4 inputs -> 3 outputs)'
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test.batch_upsert_target; ALTER SEQUENCE batch_test.batch_upsert_target_id_seq RESTART WITH 1;

-- Step 1: Insert A1 (CoreA, val_b=10) for 2021 (valid_to=infinity)
\echo 'Step 16.1: Insert A1 (CoreA, val_b=10) for 2021 (valid_to=infinity)'
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(NULL, '2020-12-31', 'infinity', 'CoreA', 10, 'CommentA1_2021');
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table();
-- Expected: 1 row for ID 1: (CoreA,10) valid_after='2020-12-31', valid_to='infinity', comment='CommentA1_2021'

-- Step 2: Insert A2 (CoreA, val_b=10 - same core, same ephemeral for simplicity of merge test) for 2022 (valid_to=infinity)
\echo 'Step 16.2: Insert A2 (CoreA, val_b=10) for 2022 (valid_to=infinity) - meets A1, equivalent core'
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE;
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2021-12-31', 'infinity', 'CoreA', 10, 'CommentA2_2022'); -- Ephemeral data updated
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1);
-- Expected: 1 row for ID 1: (CoreA,10) valid_after='2020-12-31', valid_to='infinity', comment='CommentA2_2022' (original A1 is closed at 2021-12-31, A2 merges and extends)

-- Step 3: Insert B1 (CoreB, val_b=20) for 2023 (valid_to=infinity) - different core
\echo 'Step 16.3: Insert B1 (CoreB, val_b=20) for 2023 (valid_to=infinity) - meets A1A2, different core'
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE;
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2022-12-31', 'infinity', 'CoreB', 20, 'CommentB1_2023');
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1);
-- Expected: 2 rows for ID 1:
-- 1: (CoreA,10) valid_after='2020-12-31', valid_to='2022-12-31', comment='CommentA2_2022'
-- 2: (CoreB,20) valid_after='2022-12-31', valid_to='infinity', comment='CommentB1_2023'

-- Step 4: Insert A3 (CoreA, val_b=10) for 2024 (valid_to=infinity) - different from B1, same core as A1A2
\echo 'Step 16.4: Insert A3 (CoreA, val_b=10) for 2024 (valid_to=infinity) - meets B1, different core from B1'
TRUNCATE batch_test.batch_upsert_source RESTART IDENTITY CASCADE;
INSERT INTO batch_test.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, edit_comment) VALUES
(1, '2023-12-31', 'infinity', 'CoreA', 10, 'CommentA3_2024');
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test.show_target_table(1);
-- Expected: 3 rows for ID 1:
-- 1: (CoreA,10) valid_after='2020-12-31', valid_to='2022-12-31', comment='CommentA2_2022'
-- 2: (CoreB,20) valid_after='2022-12-31', valid_to='2023-12-31', comment='CommentB1_2023'
-- 3: (CoreA,10) valid_after='2023-12-31', valid_to='infinity', comment='CommentA3_2024'

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

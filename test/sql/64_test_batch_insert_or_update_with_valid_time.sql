BEGIN;
\i test/setup.sql

\echo '----------------------------------------------------------------------------'
\echo 'Test: import.batch_insert_or_update_generic_valid_time_table'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE; -- Reverted to NOTICE for cleaner output

CREATE SCHEMA IF NOT EXISTS batch_test_update; 
CREATE SEQUENCE IF NOT EXISTS batch_test_update.batch_upsert_target_id_seq;

CREATE TABLE batch_test_update.batch_upsert_target (
    id INT NOT NULL DEFAULT nextval('batch_test_update.batch_upsert_target_id_seq'),
    valid_after DATE NOT NULL, -- (exclusive start)
    valid_to DATE NOT NULL,    -- (inclusive end)
    value_a TEXT,
    value_b INT,
    value_c TEXT, 
    updated_on DATE, -- Added
    edit_comment TEXT,
    PRIMARY KEY (id, valid_after) -- PK uses valid_after
);

CREATE TABLE batch_test_update.batch_upsert_source (
    row_id BIGSERIAL PRIMARY KEY,
    target_id INT,
    valid_after DATE NOT NULL, -- (exclusive start)
    valid_to DATE,             -- (inclusive end)
    value_a TEXT,
    value_b INT,
    value_c TEXT, 
    updated_on DATE, -- Added
    edit_comment TEXT
);

\set target_schema 'batch_test_update'
\set target_table 'batch_upsert_target'
\set source_schema 'batch_test_update'
\set source_table 'batch_upsert_source'
\set source_row_id_col 'row_id'
\set unique_cols '[ "value_a" ]'
\set temporal_cols '{valid_after, valid_to}'
\set ephemeral_cols '{edit_comment, updated_on}'
\set id_col 'id'

CREATE OR REPLACE FUNCTION batch_test_update.show_target_table(p_filter_id INT DEFAULT NULL)
RETURNS TABLE (id INT, valid_after DATE, valid_to DATE, value_a TEXT, value_b INT, value_c TEXT, updated_on DATE, edit_comment TEXT) AS $$
BEGIN
    IF p_filter_id IS NULL THEN
        RETURN QUERY SELECT tgt.id, tgt.valid_after, tgt.valid_to, tgt.value_a, tgt.value_b, tgt.value_c, tgt.updated_on, tgt.edit_comment 
                     FROM batch_test_update.batch_upsert_target tgt ORDER BY tgt.id, tgt.valid_after;
    ELSE
        RETURN QUERY SELECT tgt.id, tgt.valid_after, tgt.valid_to, tgt.value_a, tgt.value_b, tgt.value_c, tgt.updated_on, tgt.edit_comment 
                     FROM batch_test_update.batch_upsert_target tgt WHERE tgt.id = p_filter_id ORDER BY tgt.valid_after;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Scenario 1: Initial Insert (same as replace)
\echo 'Scenario 1: Initial Insert'
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(NULL, '2023-12-31', '2024-12-31', 'A', 10, 'Initial C1', '2024-01-15', 'Initial A'); -- (2023-12-31, 2024-12-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table();
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 2: Update existing - Full Overlap, Non-Null Update
\echo 'Scenario 2: Update existing - Full Overlap, Non-Null Update'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 10, 'Original C', '2024-01-10', 'Original'); -- (2023-12-31, 2024-12-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 20, 'Updated C', '2024-01-15', 'Update B and C'); -- value_b and value_c change
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1); -- Expected: value_b=20, value_c='Updated C', updated_on='2024-01-15'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 3: Update existing - Full Overlap, Partial Null Update (value_b is NULL in source)
\echo 'Scenario 3: Update existing - Full Overlap, Partial Null Update'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 10, 'Original C', '2024-01-10', 'Original'); -- (2023-12-31, 2024-12-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', NULL, 'Updated C by partial null', '2024-01-15', 'Update C, B is null in source'); -- value_b is NULL
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1); -- Expected: value_b=10 (unchanged), value_c='Updated C by partial null', updated_on='2024-01-15'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 4: Update existing - Inside Different (Split with Update)
\echo 'Scenario 4: Update existing - Inside Different (Split with Update)'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 10, 'Original C', '2024-01-10', 'Original Jan-Dec'); -- (2023-12-31, 2024-12-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-03-31', '2024-08-31', 'A', 20, NULL, '2024-01-15', 'Update Apr-Aug, C is null'); -- Source: (2024-03-31, 2024-08-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1); 
-- Expected: 
-- Row 1: va=2023-12-31, vt=2024-03-31, value_a='A', value_b=10, value_c='Original C', updated_on='2024-01-10'
-- Row 2: va=2024-03-31, vt=2024-08-31, value_a='A', value_b=20, value_c='Original C', updated_on='2024-01-15' (c unchanged due to null in source)
-- Row 3: va=2024-08-31, vt=2024-12-31, value_a='A', value_b=10, value_c='Original C', updated_on='2024-01-10'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 5: No data change, only temporal adjustment (adjacent equivalent merge)
\echo 'Scenario 5: No data change, only temporal adjustment (adjacent equivalent merge)'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-06-30', 'A', 10, 'C val', '2024-01-10', 'First half'); -- (2023-12-31, 2024-06-30]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-06-30', '2024-12-31', 'A', 10, 'C val', '2024-01-15', 'Second half'); -- Source: (2024-06-30, 2024-12-31] -- All data same

\echo 'Manual check for earlier adjacent record before function call (Scenario 5):'
SELECT * FROM batch_test_update.batch_upsert_target WHERE id = 1 AND valid_to = '2024-06-30'::DATE LIMIT 1;
\echo 'End of manual check.'

SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1); -- Expected: One merged row: (2023-12-31, 2024-12-31], updated_on='2024-01-15', edit_comment='Second half'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 6: Source overlaps start of existing, data different
\echo 'Scenario 6: Source overlaps start of existing, data different'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-02-28', '2024-10-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Mid-Year'); -- Period: (2024-02-28, 2024-10-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 20, 'Updated C by Source Overlap Start', '2024-01-15', 'Source Overlaps Start'); -- Period: (2023-12-31, 2024-05-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 3 rows
-- Row 1: va=2023-12-31, vt=2024-02-28, value_b=20, value_c='Updated C by Source Overlap Start', updated_on='2024-01-15' (Leading source part)
-- Row 2: va=2024-02-28, vt=2024-05-31, value_b=20, value_c='Updated C by Source Overlap Start', updated_on='2024-01-15' (Middle overlapping part)
-- Row 3: va=2024-05-31, vt=2024-10-31, value_b=10, value_c='Original C', updated_on='2024-01-10' (Trailing existing part)
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 7: Source overlaps end of existing, data different
\echo 'Scenario 7: Source overlaps end of existing, data different'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-08-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Early-Mid Year'); -- Period: (2023-12-31, 2024-08-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-05-31', '2024-12-31', 'A', 30, 'Updated C by Source Overlap End', '2024-01-15', 'Source Overlaps End'); -- Period: (2024-05-31, 2024-12-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 3 rows
-- Row 1: va=2023-12-31, vt=2024-05-31, value_b=10, value_c='Original C', updated_on='2024-01-10' (Leading existing part)
-- Row 2: va=2024-05-31, vt=2024-08-31, value_b=30, value_c='Updated C by Source Overlap End', updated_on='2024-01-15' (Middle overlapping part)
-- Row 3: va=2024-08-31, vt=2024-12-31, value_b=30, value_c='Updated C by Source Overlap End', updated_on='2024-01-15' (Trailing source part)
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 8: Existing is contained within source, data different
\echo 'Scenario 8: Existing is contained within source, data different'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-02-28', '2024-08-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Mid-Period'); -- Period: (2024-02-28, 2024-08-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 40, 'Updated C by Source Contains Existing', '2024-01-15', 'Source Contains Existing'); -- Period: (2023-12-31, 2024-12-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 3 rows
-- Row 1: va=2023-12-31, vt=2024-02-28, value_b=40, value_c='Updated C by Source Contains Existing', updated_on='2024-01-15' (Leading source part)
-- Row 2: va=2024-02-28, vt=2024-08-31, value_b=40, value_c='Updated C by Source Contains Existing', updated_on='2024-01-15' (Middle updated part)
-- Row 3: va=2024-08-31, vt=2024-12-31, value_b=40, value_c='Updated C by Source Contains Existing', updated_on='2024-01-15' (Trailing source part)
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 9: Existing is contained within source, data equivalent
\echo 'Scenario 9: Existing is contained within source, data equivalent'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-02-28', '2024-08-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Mid-Period, Same Data'); -- Period: (2024-02-28, 2024-08-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 10, 'Same C', '2024-01-15', 'Source Contains Existing, Same Data'); -- Period: (2023-12-31, 2024-12-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 1 row (the source record, as the existing one was deleted due to being contained with equivalent data)
-- Row 1: va=2023-12-31, vt=2024-12-31, value_b=10, value_c='Same C', updated_on='2024-01-15', edit_comment='Source Contains Existing, Same Data'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 10: Source overlaps start of existing, data equivalent
\echo 'Scenario 10: Source overlaps start of existing, data equivalent'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-02-28', '2024-10-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Mid-Year, Same Data'); -- Period: (2024-02-28, 2024-10-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 10, 'Same C', '2024-01-15', 'Source Overlaps Start, Same Data'); -- Period: (2023-12-31, 2024-05-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 1 row, existing extended to start earlier
-- Row 1: va=2023-12-31, vt=2024-10-31, value_b=10, value_c='Same C', updated_on='2024-01-15', edit_comment='Source Overlaps Start, Same Data'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 11: Source overlaps end of existing, data equivalent
\echo 'Scenario 11: Source overlaps end of existing, data equivalent'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-08-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Early-Mid Year, Same Data'); -- Period: (2023-12-31, 2024-08-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-05-31', '2024-12-31', 'A', 10, 'Same C', '2024-01-15', 'Source Overlaps End, Same Data'); -- Period: (2024-05-31, 2024-12-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 1 row, existing extended to end later
-- Row 1: va=2023-12-31, vt=2024-12-31, value_b=10, value_c='Same C', updated_on='2024-01-15', edit_comment='Source Overlaps End, Same Data'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 12: Source starts existing, data different
\echo 'Scenario 12: Source starts existing, data different'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Full Year'); -- Period: (2023-12-31, 2024-10-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 50, 'Updated C by Source Starts Existing', '2024-01-15', 'Source Starts Existing'); -- Period: (2023-12-31, 2024-05-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 2 rows
-- Row 1: va=2023-12-31, vt=2024-05-31, value_b=50, value_c='Updated C by Source Starts Existing', updated_on='2024-01-15' (Updated part)
-- Row 2: va=2024-05-31, vt=2024-10-31, value_b=10, value_c='Original C', updated_on='2024-01-10' (Remaining existing part)
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 13: Existing starts source, data different
\echo 'Scenario 13: Existing starts source, data different'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Shorter Period'); -- Period: (2023-12-31, 2024-05-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 60, 'Updated C by Existing Starts Source', '2024-01-15', 'Existing Starts Source'); -- Period: (2023-12-31, 2024-10-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 2 rows
-- Row 1: va=2023-12-31, vt=2024-05-31, value_b=60, value_c='Updated C by Existing Starts Source', updated_on='2024-01-15' (Updated part, original extent of existing)
-- Row 2: va=2024-05-31, vt=2024-10-31, value_b=60, value_c='Updated C by Existing Starts Source', updated_on='2024-01-15' (Trailing source part)
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 14: Existing finishes source, data different
\echo 'Scenario 14: Existing finishes source, data different'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-03-31', '2024-10-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Later Part'); -- Period: (2024-03-31, 2024-10-31]
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 70, 'Updated C by Existing Finishes Source', '2024-01-15', 'Existing Finishes Source'); -- Period: (2023-12-31, 2024-10-31]
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 2 rows
-- Row 1: va=2023-12-31, vt=2024-03-31, value_b=70, value_c='Updated C by Existing Finishes Source', updated_on='2024-01-15' (Leading source part)
-- Row 2: va=2024-03-31, vt=2024-10-31, value_b=70, value_c='Updated C by Existing Finishes Source', updated_on='2024-01-15' (Updated/finishing part)
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 15: Source starts existing, data equivalent
\echo 'Scenario 15: Source starts existing, data equivalent'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Full Year, Same Data'); 
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 10, 'Same C', '2024-01-15', 'Source Starts Existing, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 1 row (existing record unchanged, source is fully handled, ephemeral data updated from source)
-- Row 1: va=2023-12-31, vt=2024-10-31, value_b=10, value_c='Same C', updated_on='2024-01-15', edit_comment='Source Starts Existing, Same Data'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 16: Existing starts source, data equivalent
\echo 'Scenario 16: Existing starts source, data equivalent'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Shorter, Same Data'); 
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-15', 'Existing Starts Source, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 1 row (source record, existing was deleted)
-- Row 1: va=2023-12-31, vt=2024-10-31, value_b=10, value_c='Same C', updated_on='2024-01-15', edit_comment='Existing Starts Source, Same Data'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 17: Source finishes existing, data equivalent
\echo 'Scenario 17: Source finishes existing, data equivalent'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Full Year, Same Data'); 
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-03-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-15', 'Source Finishes Existing, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 1 row (existing record unchanged, source is fully handled, ephemeral data updated from source)
-- Row 1: va=2023-12-31, vt=2024-10-31, value_b=10, value_c='Same C', updated_on='2024-01-15', edit_comment='Source Finishes Existing, Same Data'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 18: Existing finishes source, data equivalent
\echo 'Scenario 18: Existing finishes source, data equivalent'
INSERT INTO batch_test_update.batch_upsert_target (id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-03-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Later Part, Same Data'); 
INSERT INTO batch_test_update.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-15', 'Existing Finishes Source, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update.show_target_table(1);
-- Expected: 1 row (source record, existing was deleted)
-- Row 1: va=2023-12-31, vt=2024-10-31, value_b=10, value_c='Same C', updated_on='2024-01-15', edit_comment='Existing Finishes Source, Same Data'
TRUNCATE batch_test_update.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update.batch_upsert_target; ALTER SEQUENCE batch_test_update.batch_upsert_target_id_seq RESTART WITH 1;


-- Cleanup
DROP FUNCTION batch_test_update.show_target_table(INT);
DROP TABLE batch_test_update.batch_upsert_source;
DROP TABLE batch_test_update.batch_upsert_target;
DROP SEQUENCE batch_test_update.batch_upsert_target_id_seq;
DROP SCHEMA batch_test_update CASCADE;

SET client_min_messages TO NOTICE; -- Revert client_min_messages at the end (or to original if known)
ROLLBACK;

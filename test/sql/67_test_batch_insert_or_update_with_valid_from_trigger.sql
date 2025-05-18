BEGIN;
\i test/setup.sql

\echo '----------------------------------------------------------------------------'
\echo 'Test: import.batch_insert_or_update_generic_valid_time_table (with valid_from trigger)'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE; -- Reverted for cleaner output

CREATE SCHEMA IF NOT EXISTS batch_test_update_vf; 
CREATE SEQUENCE IF NOT EXISTS batch_test_update_vf.batch_upsert_target_id_seq;

CREATE TABLE batch_test_update_vf.batch_upsert_target (
    id INT NOT NULL DEFAULT nextval('batch_test_update_vf.batch_upsert_target_id_seq'),
    valid_from DATE NOT NULL, -- Added for this test
    valid_after DATE NOT NULL, 
    valid_to DATE NOT NULL,    
    value_a TEXT,
    value_b INT,
    value_c TEXT, 
    updated_on DATE, -- Changed from updated_at TIMESTAMPTZ
    edit_comment TEXT,
    PRIMARY KEY (id, valid_after) 
);

CREATE TRIGGER trg_target_synchronize_valid_from_after
    BEFORE INSERT OR UPDATE ON batch_test_update_vf.batch_upsert_target
    FOR EACH ROW EXECUTE FUNCTION public.synchronize_valid_from_after();

CREATE TABLE batch_test_update_vf.batch_upsert_source (
    row_id BIGSERIAL PRIMARY KEY,
    target_id INT,
    valid_after DATE NOT NULL, 
    valid_to DATE,             
    value_a TEXT,
    value_b INT,
    value_c TEXT, 
    updated_on DATE, -- Changed from updated_at TIMESTAMPTZ
    edit_comment TEXT
);

\set target_schema 'batch_test_update_vf'
\set target_table 'batch_upsert_target'
\set source_schema 'batch_test_update_vf'
\set source_table 'batch_upsert_source'
\set source_row_id_col 'row_id'
\set unique_cols '[ "value_a" ]'
\set temporal_cols '{valid_after, valid_to}'
\set ephemeral_cols '{edit_comment, updated_on}'
\set id_col 'id'

CREATE OR REPLACE FUNCTION batch_test_update_vf.show_target_table(p_filter_id INT DEFAULT NULL)
RETURNS TABLE (id INT, valid_from DATE, valid_after DATE, valid_to DATE, value_a TEXT, value_b INT, value_c TEXT, updated_on DATE, edit_comment TEXT) AS $$
BEGIN
    IF p_filter_id IS NULL THEN
        RETURN QUERY SELECT tgt.id, tgt.valid_from, tgt.valid_after, tgt.valid_to, tgt.value_a, tgt.value_b, tgt.value_c, tgt.updated_on, tgt.edit_comment 
                     FROM batch_test_update_vf.batch_upsert_target tgt ORDER BY tgt.id, tgt.valid_after;
    ELSE
        RETURN QUERY SELECT tgt.id, tgt.valid_from, tgt.valid_after, tgt.valid_to, tgt.value_a, tgt.value_b, tgt.value_c, tgt.updated_on, tgt.edit_comment 
                     FROM batch_test_update_vf.batch_upsert_target tgt WHERE tgt.id = p_filter_id ORDER BY tgt.valid_after;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Scenario 1: Initial Insert
\echo 'Scenario 1: Initial Insert'
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(NULL, '2023-12-31', '2024-12-31', 'A', 10, 'Initial C1', '2024-01-15', 'Initial A'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    :'unique_cols'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table();
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 2: Update existing - Full Overlap, Non-Null Update
\echo 'Scenario 2: Update existing - Full Overlap, Non-Null Update'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-12-31', 'A', 10, 'Original C', '2024-01-10', 'Original'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 20, 'Updated C', '2024-01-15', 'Update B and C'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); 
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 3: Update existing - Full Overlap, Partial Null Update (value_b is NULL in source)
\echo 'Scenario 3: Update existing - Full Overlap, Partial Null Update'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-12-31', 'A', 10, 'Original C', '2024-01-10', 'Original'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', NULL, 'Updated C by partial null', '2024-01-15', 'Update C, B is null in source'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); 
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 4: Update existing - Inside Different (Split with Update)
\echo 'Scenario 4: Update existing - Inside Different (Split with Update)'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-12-31', 'A', 10, 'Original C', '2024-01-10', 'Original Jan-Dec'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-03-31', '2024-08-31', 'A', 20, NULL, '2024-01-15', 'Update Apr-Aug, C is null'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); 
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 5: No data change, only temporal adjustment (adjacent equivalent merge)
\echo 'Scenario 5: No data change, only temporal adjustment (adjacent equivalent merge)'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-06-30', 'A', 10, 'C val', '2024-01-10', 'First half'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-06-30', '2024-12-31', 'A', 10, 'C val', '2024-01-15', 'Second half'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); -- Expect updated_on from source, edit_comment from source
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 6: Source overlaps start of existing, data different
\echo 'Scenario 6: Source overlaps start of existing, data different'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-03-01', '2024-02-29', '2024-10-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Mid-Year'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 20, 'Updated C by Source Overlap Start', '2024-01-15', 'Source Overlaps Start'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1);
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 7: Source overlaps end of existing, data different
\echo 'Scenario 7: Source overlaps end of existing, data different'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-08-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Early-Mid Year'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-05-31', '2024-12-31', 'A', 30, 'Updated C by Source Overlap End', '2024-01-15', 'Source Overlaps End'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1);
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 8: Existing is contained within source, data different
\echo 'Scenario 8: Existing is contained within source, data different'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-03-01', '2024-02-29', '2024-08-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Mid-Period'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 40, 'Updated C by Source Contains Existing', '2024-01-15', 'Source Contains Existing'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1);
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 9: Existing is contained within source, data equivalent
\echo 'Scenario 9: Existing is contained within source, data equivalent'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-03-01', '2024-02-29', '2024-08-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Mid-Period, Same Data'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-12-31', 'A', 10, 'Same C', '2024-01-15', 'Source Contains Existing, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); -- Expect ephemeral from source (updated_on='2024-01-15')
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 10: Source overlaps start of existing, data equivalent
\echo 'Scenario 10: Source overlaps start of existing, data equivalent'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-03-01', '2024-02-29', '2024-10-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Mid-Year, Same Data'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 10, 'Same C', '2024-01-15', 'Source Overlaps Start, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); -- Expect ephemeral from source (updated_on='2024-01-15')
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 11: Source overlaps end of existing, data equivalent
\echo 'Scenario 11: Source overlaps end of existing, data equivalent'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-08-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Early-Mid Year, Same Data'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-05-31', '2024-12-31', 'A', 10, 'Same C', '2024-01-15', 'Source Overlaps End, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); -- Expect ephemeral from source (updated_on='2024-01-15')
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 12: Source starts existing, data different
\echo 'Scenario 12: Source starts existing, data different'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-10-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Full Year'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 50, 'Updated C by Source Starts Existing', '2024-01-15', 'Source Starts Existing'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1);
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 13: Existing starts source, data different
\echo 'Scenario 13: Existing starts source, data different'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-05-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Shorter Period'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 60, 'Updated C by Existing Starts Source', '2024-01-15', 'Existing Starts Source'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1);
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 14: Existing finishes source, data different
\echo 'Scenario 14: Existing finishes source, data different'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-04-01', '2024-03-31', '2024-10-31', 'A', 10, 'Original C', '2024-01-10', 'Existing Later Part'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 70, 'Updated C by Existing Finishes Source', '2024-01-15', 'Existing Finishes Source'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1);
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 15: Source starts existing, data equivalent
\echo 'Scenario 15: Source starts existing, data equivalent'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Full Year, Same Data'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-05-31', 'A', 10, 'Same C', '2024-01-15', 'Source Starts Existing, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); -- Expect ephemeral from source (updated_on='2024-01-15')
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 16: Existing starts source, data equivalent
\echo 'Scenario 16: Existing starts source, data equivalent'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-05-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Shorter, Same Data'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-15', 'Existing Starts Source, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); -- Expect ephemeral from source (updated_on='2024-01-15')
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 17: Source finishes existing, data equivalent
\echo 'Scenario 17: Source finishes existing, data equivalent'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Full Year, Same Data'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-03-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-15', 'Source Finishes Existing, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); -- Expect ephemeral from source (updated_on='2024-01-15')
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 18: Existing finishes source, data equivalent
\echo 'Scenario 18: Existing finishes source, data equivalent'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-04-01', '2024-03-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-10', 'Existing Later Part, Same Data'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2023-12-31', '2024-10-31', 'A', 10, 'Same C', '2024-01-15', 'Existing Finishes Source, Same Data'); 
SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); -- Expect ephemeral from source (updated_on='2024-01-15')
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Scenario 19: Yearly Override with Equivalent Core Data (Update Strategy)
\echo 'Scenario 19: Yearly Override with Equivalent Core Data (Update Strategy)'
INSERT INTO batch_test_update_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', 'infinity', 'EQ_DATA', 100, 'C_VAL', '2024-01-10', 'Year 1 Import Data'); 
INSERT INTO batch_test_update_vf.batch_upsert_source (target_id, valid_after, valid_to, value_a, value_b, value_c, updated_on, edit_comment) VALUES
(1, '2024-12-31', 'infinity', 'EQ_DATA', 100, 'C_VAL', '2025-01-15', 'Year 2 Import Data'); -- Source for "next year"

SELECT * FROM import.batch_insert_or_update_generic_valid_time_table(
    :'target_schema', :'target_table', :'source_schema', :'source_table', :'source_row_id_col',
    '[]'::JSONB, 
    :'temporal_cols'::TEXT[], :'ephemeral_cols'::TEXT[], NULL, :'id_col'
);
SELECT * FROM batch_test_update_vf.show_target_table(1); 
-- Expected (NEW): 1 row, ephemeral data (edit_comment, updated_on) updated from source.
-- Row 1: id=1, vf=2024-01-01, va=2023-12-31, vt=infinity, value_a='EQ_DATA', value_b=100, value_c='C_VAL', 
--        updated_on='2025-01-15', comment='Year 2 Import Data'
TRUNCATE batch_test_update_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_update_vf.batch_upsert_target; ALTER SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- Cleanup
DROP FUNCTION batch_test_update_vf.show_target_table(INT);
DROP TABLE batch_test_update_vf.batch_upsert_source;
DROP TABLE batch_test_update_vf.batch_upsert_target; -- Trigger will be dropped with the table
DROP SEQUENCE batch_test_update_vf.batch_upsert_target_id_seq;
DROP SCHEMA batch_test_update_vf CASCADE;

SET client_min_messages TO NOTICE; -- Revert client_min_messages at the end
ROLLBACK;

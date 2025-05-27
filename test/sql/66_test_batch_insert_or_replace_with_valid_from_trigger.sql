BEGIN;
\i test/setup.sql

\echo '----------------------------------------------------------------------------'
\echo 'Test: import.batch_insert_or_replace_generic_valid_time_table (with valid_from trigger)'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE;

CREATE SCHEMA IF NOT EXISTS batch_test_replace_vf; 
CREATE SEQUENCE IF NOT EXISTS batch_test_replace_vf.batch_upsert_target_id_seq;

CREATE TABLE batch_test_replace_vf.batch_upsert_target (
    id INT NOT NULL DEFAULT nextval('batch_test_replace_vf.batch_upsert_target_id_seq'),
    valid_from DATE NOT NULL, -- Added for this test
    valid_after DATE NOT NULL, 
    valid_to DATE NOT NULL,    
    value_a TEXT,
    value_b INT,
    updated_on DATE, -- Added
    edit_comment TEXT, 
    PRIMARY KEY (id, valid_after) 
);

CREATE TRIGGER trg_target_synchronize_valid_from_after
    BEFORE INSERT OR UPDATE ON batch_test_replace_vf.batch_upsert_target
    FOR EACH ROW EXECUTE FUNCTION public.synchronize_valid_from_after();

CREATE TABLE batch_test_replace_vf.batch_upsert_source (
    row_id BIGSERIAL PRIMARY KEY,
    founding_row_id BIGINT,
    target_id INT, 
    valid_after DATE NOT NULL, 
    valid_to DATE,             
    value_a TEXT,
    value_b INT,
    updated_on DATE, -- Added
    edit_comment TEXT
);

\set target_schema 'batch_test_replace_vf'
\set target_table 'batch_upsert_target'
\set source_schema 'batch_test_replace_vf'
\set source_table 'batch_upsert_source'
-- \set source_row_id_col 'row_id' -- Removed
\set unique_cols '[ "value_a" ]'
-- \set temporal_cols '{valid_after, valid_to}' -- Removed
\set ephemeral_cols '{edit_comment, updated_on}'
\set id_col 'id'

CREATE OR REPLACE FUNCTION batch_test_replace_vf.show_target_table(p_filter_id INT DEFAULT NULL)
RETURNS TABLE (id INT, valid_from DATE, valid_after DATE, valid_to DATE, value_a TEXT, value_b INT, updated_on DATE, edit_comment TEXT) AS $$
BEGIN
    IF p_filter_id IS NULL THEN
        RETURN QUERY SELECT tgt.id, tgt.valid_from, tgt.valid_after, tgt.valid_to, tgt.value_a, tgt.value_b, tgt.updated_on, tgt.edit_comment 
                     FROM batch_test_replace_vf.batch_upsert_target tgt ORDER BY tgt.id, tgt.valid_after;
    ELSE
        RETURN QUERY SELECT tgt.id, tgt.valid_from, tgt.valid_after, tgt.valid_to, tgt.value_a, tgt.value_b, tgt.updated_on, tgt.edit_comment 
                     FROM batch_test_replace_vf.batch_upsert_target tgt WHERE tgt.id = p_filter_id ORDER BY tgt.id, tgt.valid_after;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 1. Initial Insert
\echo 'Scenario 1: Initial Insert'
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, NULL, '2023-12-31', '2024-12-31', 'A', 10, '2024-01-15', 'Initial A'); -- row_id=1, founding_row_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(); 
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE;
DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 2. Adjacent Equivalent Merge
\echo 'Scenario 2: Adjacent Equivalent Merge'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-06-30', 'A', 10, '2024-01-10', 'First half');
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2024-06-30', '2024-12-31', 'A', 10, '2024-01-15', 'Second half'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected: 1 row, va=2023-12-31, vt=2024-12-31, updated_on='2024-01-15', edit_comment='Second half'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 3. Adjacent Different (No Merge)
\echo 'Scenario 3: Adjacent Different (No Merge)'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-06-30', 'A', 10, '2024-01-10', 'First half');
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2024-06-30', '2024-12-31', 'B', 20, '2024-01-15', 'Second half different'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected: 2 rows, first unchanged, second is the new source record.
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 4. Overlap Start Equivalent
\echo 'Scenario 4: Overlap Start Equivalent'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-03-01', '2024-02-29', '2024-12-31', 'A', 10, '2024-01-10', 'Existing March-Dec'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2023-12-31', '2024-05-31', 'A', 10, '2024-01-15', 'New Jan-May'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected: 1 row, va=2023-12-31, vt=2024-12-31, updated_on='2024-01-15', edit_comment='New Jan-May'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 5. Overlap Start Different
\echo 'Scenario 5: Overlap Start Different'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-03-01', '2024-02-29', '2024-12-31', 'A', 10, '2024-01-10', 'Existing March-Dec'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2023-12-31', '2024-05-31', 'B', 20, '2024-01-15', 'New Jan-May Different'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected: 2 rows. Source: (Dec 31, May 31] value B. Existing: (May 31, Dec 31] value A.
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 6. Overlap End Equivalent
\echo 'Scenario 6: Overlap End Equivalent'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-09-30', 'A', 10, '2024-01-10', 'Existing Jan-Sep'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2024-06-30', '2024-12-31', 'A', 10, '2024-01-15', 'New Jul-Dec'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected: 1 row, va=2023-12-31, vt=2024-12-31, updated_on='2024-01-15', edit_comment='New Jul-Dec'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 7. Overlap End Different
\echo 'Scenario 7: Overlap End Different'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-09-30', 'A', 10, '2024-01-10', 'Existing Jan-Sep'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2024-06-30', '2024-12-31', 'B', 20, '2024-01-15', 'New Jul-Dec Different'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected: 2 rows. Existing: (Dec 31, June 30] value A. Source: (June 30, Dec 31] value B.
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 8. Inside Equivalent
\echo 'Scenario 8: Inside Equivalent'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-12-31', 'A', 10, '2024-01-10', 'Existing Jan-Dec'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2024-03-31', '2024-08-31', 'A', 10, '2024-01-15', 'New Apr-Aug'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected: 1 row, va=2023-12-31, vt=2024-12-31, updated_on='2024-01-15', edit_comment='New Apr-Aug'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 9. Inside Different (Split)
\echo 'Scenario 9: Inside Different (Split)'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-12-31', 'A', 10, '2024-01-10', 'Existing Jan-Dec'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2024-03-31', '2024-08-31', 'B', 20, '2024-01-15', 'New Apr-Aug Different'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected: 3 rows. Existing: (Dec 31, Mar 31] value A. Source: (Mar 31, Aug 31] value B. Existing: (Aug 31, Dec 31] value A.
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 10. Contains Existing
\echo 'Scenario 10: Contains Existing'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-04-01', '2024-03-31', '2024-08-31', 'A', 10, '2024-01-10', 'Existing Apr-Aug'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2023-12-31', '2024-12-31', 'B', 20, '2024-01-15', 'New Jan-Dec Different'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected: 1 row, va=2023-12-31, vt=2024-12-31, value_b=20 (from source)
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 11. Batch Processing (Multiple IDs, Multiple Scenarios)
\echo 'Scenario 11: Batch Processing (Multiple IDs and Scenarios)'
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, NULL, '2023-12-31', '2024-12-31', 'ID1', 11, '2024-01-15', 'ID1 Initial'); -- row_id=1, founding_row_id=1
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(2, '2024-01-01', '2023-12-31', '2024-12-31', 'ID2-Old', 22, '2024-01-10', 'ID2 Existing'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(2, 2, '2024-04-30', '2024-08-31', 'ID2-New', 23, '2024-01-15', 'ID2 Split'); -- row_id=2, founding_row_id=target_id=2
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(3, '2024-01-01', '2023-12-31', '2024-06-30', 'ID3', 33, '2024-01-10', 'ID3 First Half'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(3, 3, '2024-06-30', '2024-12-31', 'ID3', 33, '2024-01-15', 'ID3 Second Half Merge'); -- row_id=3, founding_row_id=target_id=3
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(4, 4, '2023-12-31', NULL, 'ID4-Error', 44, '2024-01-15', 'ID4 Error'); -- row_id=4, founding_row_id=target_id=4

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
) ORDER BY source_row_id;

\echo 'Target table after batch:'
SELECT * FROM batch_test_replace_vf.show_target_table();
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 12. ID Lookup using unique_columns
\echo 'Scenario 12: ID Lookup'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(5, '2024-01-01', '2023-12-31', '2024-12-31', 'LookupMe', 50, '2024-01-10', 'Existing Lookup'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(5, NULL, '2024-05-31', '2024-09-30', 'LookupMe', 55, '2024-01-15', 'Update via Lookup'); -- founding_row_id=expected_target_id=5

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(5); 
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 13. Identical Period, Different Data, Full Replacement
\echo 'Scenario 13: Identical Period, Different Data, Full Replacement'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-12-31', 'KeyForID1', 100, '2024-01-10', 'Original Version'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2023-12-31', '2024-12-31', 'KeyForID1', 200, '2024-01-15', 'Updated Version'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => '[]'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 14. Equals Relation, Equivalent Data (No Change Expected)
\echo 'Scenario 14: Equals Relation, Equivalent Data'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', '2024-12-31', 'Equivalent', 100, '2024-01-10', 'Original Comment'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2023-12-31', '2024-12-31', 'Equivalent', 100, '2024-01-15', 'Source Comment, Should Update Ephemeral'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => '[]'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected: 1 row, updated_on='2024-01-15', edit_comment='Source Comment, Should Update Ephemeral'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 15. Precedes Relation (Non-Overlapping, New record should be added)
\echo 'Scenario 15: Precedes Relation'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-07-01', '2024-06-30', '2024-12-31', 'Later', 200, '2024-01-10', 'Later Record'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2023-12-31', '2024-03-31', 'Earlier', 100, '2024-01-15', 'Earlier Record'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => '[]'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 16. Yearly Override with Equivalent Core Data
\echo 'Scenario 16: Yearly Override with Equivalent Core Data'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2024-01-01', '2023-12-31', 'infinity', 'EQ_DATA', 100, '2024-01-10', 'Year 1 Import Data'); 
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2024-12-31', 'infinity', 'EQ_DATA', 100, '2025-01-15', 'Year 2 Import Data'); -- founding_row_id=target_id=1

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => '[]'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1); 
-- Expected (NEW): 1 row, va=2023-12-31, vt=infinity, updated_on='2025-01-15', edit_comment='Year 2 Import Data'
-- The valid_from should remain 2024-01-01 as the original record's valid_after is not changed.
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 17. A-A-B-A Sequence with yearly 'infinity' inputs (4 inputs -> 3 outputs) and valid_from trigger
\echo 'Scenario 17: A-A-B-A Sequence with yearly ''infinity'' inputs (4 inputs -> 3 outputs) and valid_from trigger'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target; ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Step 1: Insert A1 (CoreA, val_b=10) for 2021 (valid_to=infinity)
\echo 'Step 17.1: Insert A1 (CoreA, val_b=10) for 2021 (valid_to=infinity)'
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, NULL, '2020-12-31', 'infinity', 'CoreA', 10, '2021-01-10', 'CommentA1_2021'); -- row_id=1, founding_row_id=1
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table();
-- Expected: 1 row for ID 1: (CoreA,10) valid_from='2021-01-01', valid_after='2020-12-31', valid_to='infinity', updated_on='2021-01-10', comment='CommentA1_2021'

-- Step 2: Insert A2 (CoreA, val_b=10) for 2022 (valid_to=infinity) - meets A1, equivalent core
\echo 'Step 17.2: Insert A2 (CoreA, val_b=10) for 2022 (valid_to=infinity) - meets A1, equivalent core'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE;
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2021-12-31', 'infinity', 'CoreA', 10, '2022-01-10', 'CommentA2_2022'); -- founding_row_id=target_id=1
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => '[]'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1);
-- Expected: 1 row for ID 1: (CoreA,10) valid_from='2021-01-01', valid_after='2020-12-31', valid_to='infinity', updated_on='2022-01-10', comment='CommentA2_2022'

-- Step 3: Insert B1 (CoreB, val_b=20) for 2023 (valid_to=infinity) - meets A1A2, different core
\echo 'Step 17.3: Insert B1 (CoreB, val_b=20) for 2023 (valid_to=infinity) - meets A1A2, different core'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE;
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2022-12-31', 'infinity', 'CoreB', 20, '2023-01-10', 'CommentB1_2023'); -- founding_row_id=target_id=1
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => '[]'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1);
-- Expected: 2 rows for ID 1:
-- 1: (CoreA,10) valid_from='2021-01-01', valid_after='2020-12-31', valid_to='2022-12-31', updated_on='2022-01-10', comment='CommentA2_2022'
-- 2: (CoreB,20) valid_from='2023-01-01', valid_after='2022-12-31', valid_to='infinity', updated_on='2023-01-10', comment='CommentB1_2023'

-- Step 4: Insert A3 (CoreA, val_b=10) for 2024 (valid_to=infinity) - meets B1, different core from B1
\echo 'Step 17.4: Insert A3 (CoreA, val_b=10) for 2024 (valid_to=infinity) - meets B1, different core from B1'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE;
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2023-12-31', 'infinity', 'CoreA', 10, '2024-01-10', 'CommentA3_2024'); -- founding_row_id=target_id=1
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => '[]'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1);
-- Expected: 3 rows for ID 1:
-- 1: (CoreA,10) valid_from='2021-01-01', valid_after='2020-12-31', valid_to='2022-12-31', updated_on='2022-01-10', comment='CommentA2_2022'
-- 2: (CoreB,20) valid_from='2023-01-01', valid_after='2022-12-31', valid_to='2023-12-31', updated_on='2023-01-10', comment='CommentB1_2023'
-- 3: (CoreA,10) valid_from='2024-01-01', valid_after='2023-12-31', valid_to='infinity', updated_on='2024-01-10', comment='CommentA3_2024'

TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- 18. Yearly Imports with Infinity and Equivalent Data (Simulating Test 50 issue)
\echo 'Scenario 18: Yearly Imports with Infinity and Equivalent Data'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target; ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Step 18.1: Insert data for Year 1 (e.g., 2024 data, valid from 2024-01-01 to infinity)
\echo 'Step 18.1: Insert Year 1 data (valid_to=infinity)'
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, NULL, '2023-12-31', 'infinity', 'YearlyInc', 100, '2024-01-10', 'Year 1 Data (2024)'); -- row_id=1, founding_row_id=1
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table();
-- Expected: 1 row for ID 1: (YearlyInc,100) valid_from='2024-01-01', valid_after='2023-12-31', valid_to='infinity', updated_on='2024-01-10', comment='Year 1 Data (2024)'

-- Step 18.2: Insert data for Year 2 (e.g., 2025 data, valid from 2025-01-01 to infinity)
-- Core data (value_a, value_b) is the same, ephemeral data (updated_on, edit_comment) changes.
\echo 'Step 18.2: Insert Year 2 data (valid_to=infinity, equivalent core data)'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE;
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2024-12-31', 'infinity', 'YearlyInc', 100, '2025-01-10', 'Year 2 Data (2025)'); -- target_id is now known (1), founding_row_id=target_id=1
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => '[]'::JSONB, -- Use empty unique_cols as target_id is provided
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1);
-- Expected: 1 rows for ID 1:
-- 1: (YearlyInc,100) valid_from='2024-01-01', valid_after='2023-12-31', valid_to='infinity', updated_on='2025-01-10', comment='Year 2 Data (2024)' (new ephemeral)

TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- New Scenario: Multiple Edits to Same New Entity in One Batch (founding_row_id cache test)
\echo 'Scenario N1: Multiple Edits to Same New Entity in One Batch (founding_row_id cache test)'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE;
DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;

INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(101, NULL, '2023-01-01', '2023-06-30', 'MultiEditNewVF', 10, '2023-01-15', 'First part new VF'), -- row_id=1
(101, NULL, '2023-07-01', '2023-12-31', 'MultiEditNewVF', 20, '2023-07-15', 'Second part new VF, value_b changed'); -- row_id=2

SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => :'unique_cols'::JSONB,
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
) ORDER BY source_row_id;
SELECT * FROM batch_test_replace_vf.show_target_table();
-- Expected: A single new ID (e.g., 1) should be created for 'MultiEditNewVF'.
-- Two rows for this ID due to different value_b in different periods.
-- ID (e.g. 1): (MultiEditNewVF, 10) valid_from='2023-01-02', valid_after='2023-01-01', valid_to='2023-06-30', updated_on='2023-01-15'
-- ID (e.g. 1): (MultiEditNewVF, 20) valid_from='2023-07-02', valid_after='2023-07-01', valid_to='2023-12-31', updated_on='2023-07-15'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE; DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- Scenario 19: Fix Verification - Sequential Equivalent Segments with Infinity
\echo 'Scenario 19: Fix Verification - Sequential Equivalent Segments with Infinity'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE;
DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;

-- Step 19.1: Manually insert initial record for Year 1 (ends before infinity to set a base)
\echo 'Step 19.1: Insert Year 1 data (e.g., 2021)'
INSERT INTO batch_test_replace_vf.batch_upsert_target (id, valid_from, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, '2021-01-01', '2020-12-31', '2021-12-31', 'FixVerifyInf', 100, '2021-01-10', 'Year 1 Data');
SELECT * FROM batch_test_replace_vf.show_target_table(1);
-- Expected: 1 row for ID 1: (FixVerifyInf,100) vf='2021-01-01', va='2020-12-31', vt='2021-12-31', updated_on='2021-01-10', comment='Year 1 Data'

-- Step 19.2: Process Year 2 data (meets Year 1, equivalent core, new ephemeral, ends infinity)
\echo 'Step 19.2: Process Year 2 data (meets Year 1, equivalent core, new ephemeral, ends infinity)'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE;
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2021-12-31', 'infinity', 'FixVerifyInf', 100, '2022-01-10', 'Year 2 Data'); -- target_id=1
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => '[]'::JSONB, -- ID is provided
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1);
-- Expected: 1 row for ID 1:
-- vf='2021-01-01', va='2020-12-31', vt='infinity'
-- value_a='FixVerifyInf', value_b=100
-- updated_on='2022-01-10', comment='Year 2 Data'

-- Step 19.3: Process Year 3 data (meets Year 2 period, equivalent core, new ephemeral, ends infinity)
\echo 'Step 19.3: Process Year 3 data (meets Year 2, equivalent core, new ephemeral, ends infinity)'
TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE;
INSERT INTO batch_test_replace_vf.batch_upsert_source (founding_row_id, target_id, valid_after, valid_to, value_a, value_b, updated_on, edit_comment) VALUES
(1, 1, '2022-12-31', 'infinity', 'FixVerifyInf', 100, '2023-01-10', 'Year 3 Data'); -- target_id=1
SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
    p_target_schema_name           => :'target_schema',
    p_target_table_name            => :'target_table',
    p_source_schema_name           => :'source_schema',
    p_source_table_name            => :'source_table',
    p_unique_columns               => '[]'::JSONB, -- ID is provided
    p_ephemeral_columns            => :'ephemeral_cols'::TEXT[],
    p_id_column_name               => :'id_col',
    p_generated_columns_override   => NULL
);
SELECT * FROM batch_test_replace_vf.show_target_table(1);
-- Expected: 1 row for ID 1:
-- vf='2021-01-01', va='2020-12-31', vt='infinity'
-- value_a='FixVerifyInf', value_b=100
-- updated_on='2023-01-10', comment='Year 3 Data'

TRUNCATE batch_test_replace_vf.batch_upsert_source RESTART IDENTITY CASCADE;
DELETE FROM batch_test_replace_vf.batch_upsert_target;
ALTER SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq RESTART WITH 1;


-- Cleanup
DROP FUNCTION batch_test_replace_vf.show_target_table(INT);
DROP TABLE batch_test_replace_vf.batch_upsert_source;
DROP TABLE batch_test_replace_vf.batch_upsert_target; -- Trigger will be dropped with the table
DROP SEQUENCE batch_test_replace_vf.batch_upsert_target_id_seq;
DROP SCHEMA batch_test_replace_vf CASCADE; 

SET client_min_messages TO NOTICE; 
ROLLBACK; 

BEGIN;
\i test/setup.sql

\echo '----------------------------------------------------------------------------'
\echo 'Test: sql_saga trigger behavior for synchronized valid_to/valid_until'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE;

-- Setup: Create a test table with valid_from, valid_until, and valid_to
CREATE SCHEMA IF NOT EXISTS trigger_test;

CREATE TABLE trigger_test.temporal_table (
    id SERIAL,
    description TEXT,
    valid_from DATE NOT NULL,
    valid_until DATE, -- sql_saga will enforce NOT NULL in trigger
    valid_to DATE -- sql_saga will enforce NOT NULL in trigger
);

-- Register with sql_saga and enable synchronization
-- This creates the trigger automatically.
SELECT sql_saga.add_era(
    'trigger_test.temporal_table'::regclass,
    synchronize_valid_to_column => 'valid_to'
);
SELECT sql_saga.add_unique_key('trigger_test.temporal_table',ARRAY['id'], key_type => 'primary'::sql_saga.unique_key_type);

-- Function to display table contents
CREATE OR REPLACE FUNCTION trigger_test.show_table()
RETURNS TABLE (id INT, description TEXT, valid_from DATE, valid_until DATE, valid_to DATE) AS $$
BEGIN
    RETURN QUERY SELECT tt.id, tt.description, tt.valid_from, tt.valid_until, tt.valid_to
                 FROM trigger_test.temporal_table tt ORDER BY tt.id, tt.valid_from;
END;
$$ LANGUAGE plpgsql;

-- Test INSERT scenarios
\echo '--- INSERT Scenarios ---'

-- 1. INSERT with only valid_until
\echo 'Test 1: INSERT with only valid_until'
INSERT INTO trigger_test.temporal_table (description, valid_from, valid_until) VALUES ('Test 1', '2024-01-01', '2025-01-01');
SELECT * FROM trigger_test.show_table(); -- Expected: valid_to = 2024-12-31

-- 2. INSERT with only valid_to
\echo 'Test 2: INSERT with only valid_to'
INSERT INTO trigger_test.temporal_table (description, valid_from, valid_to) VALUES ('Test 2', '2024-01-16', '2024-11-30');
SELECT * FROM trigger_test.show_table(); -- Expected: valid_until = 2024-12-01

-- 3. INSERT with both valid_until and valid_to (consistent)
\echo 'Test 3: INSERT with both (consistent)'
INSERT INTO trigger_test.temporal_table (description, valid_from, valid_until, valid_to) VALUES ('Test 3', '2024-02-01', '2024-11-01', '2024-10-31');
SELECT * FROM trigger_test.show_table(); -- Expected: No error, values as inserted

-- 4. INSERT with both (inconsistent) - Expect error
\echo 'Test 4: INSERT with both (inconsistent) - Expect error'
DO $$
BEGIN
    INSERT INTO trigger_test.temporal_table (description, valid_from, valid_until, valid_to) VALUES ('Test 4 Fail', '2024-03-01', '2024-10-01', '2024-10-01');
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Test 4 Caught expected error: %', SQLERRM;
END $$;
SELECT * FROM trigger_test.show_table(); -- Should not contain 'Test 4 Fail'

-- 5. INSERT with neither valid_until nor valid_to - Expect error (NOT NULL constraint)
\echo 'Test 5: INSERT with neither valid_until nor valid_to - Expect error'
DO $$
BEGIN
    INSERT INTO trigger_test.temporal_table (description, valid_from) VALUES ('Test 5 Fail', '2024-07-01');
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Test 5 Caught expected error: %', SQLERRM;
END $$;
SELECT * FROM trigger_test.show_table(); -- Should not contain 'Test 5 Fail'

-- Test UPDATE scenarios
\echo '--- UPDATE Scenarios ---'
-- Setup a base row for UPDATE tests
INSERT INTO trigger_test.temporal_table (description, valid_from, valid_to) VALUES ('Base Update Row', '2025-01-01', '2025-12-31') RETURNING id \gset base_update_id_

-- 6. UPDATE changing valid_until
\echo 'Test 6: UPDATE changing valid_until'
UPDATE trigger_test.temporal_table SET valid_until = '2025-02-01' WHERE id = :base_update_id_id;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Expected: valid_to = 2025-01-31

-- 7. UPDATE changing valid_to
\echo 'Test 7: UPDATE changing valid_to'
UPDATE trigger_test.temporal_table SET valid_to = '2025-03-01' WHERE id = :base_update_id_id;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Expected: valid_until = 2025-03-02

-- 8. UPDATE changing both consistently
\echo 'Test 8: UPDATE changing both consistently'
UPDATE trigger_test.temporal_table SET valid_until = '2025-04-01', valid_to = '2025-03-31' WHERE id = :base_update_id_id;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Expected: No error, values as updated

-- 9. UPDATE changing both inconsistently - Expect error
\echo 'Test 9: UPDATE changing both inconsistently - Expect error'
SET app.current_base_id = :base_update_id_id;
DO $$
DECLARE
  target_id INT := current_setting('app.current_base_id')::INT;
BEGIN
    EXECUTE format('UPDATE trigger_test.temporal_table SET valid_until = %L, valid_to = %L WHERE id = %L',
                   '2025-05-02'::DATE, '2025-05-02'::DATE, target_id);
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Test 9 Caught expected error: %', SQLERRM;
END $$;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Should reflect state from Test 8

-- 10. UPDATE setting valid_until to NULL - Expect error
\echo 'Test 10: UPDATE setting valid_until to NULL - Expect error'
SET app.current_base_id = :base_update_id_id;
DO $$
DECLARE
  target_id INT := current_setting('app.current_base_id')::INT;
BEGIN
    EXECUTE format('UPDATE trigger_test.temporal_table SET valid_until = NULL WHERE id = %L', target_id);
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Test 10 Caught expected error: %', SQLERRM;
END $$;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Should reflect state from Test 8

-- 11. UPDATE setting valid_to to NULL - Expect error
\echo 'Test 11: UPDATE setting valid_to to NULL - Expect error'
SET app.current_base_id = :base_update_id_id;
DO $$
DECLARE
  target_id INT := current_setting('app.current_base_id')::INT;
BEGIN
    EXECUTE format('UPDATE trigger_test.temporal_table SET valid_to = NULL WHERE id = %L', target_id);
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Test 11 Caught expected error: %', SQLERRM;
END $$;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Should reflect state from Test 8

-- 12. UPDATE changing only valid_from (should not affect valid_to/valid_until)
\echo 'Test 12: UPDATE changing only valid_from'
UPDATE trigger_test.temporal_table SET valid_from = '2025-01-15' WHERE id = :base_update_id_id;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Expected: valid_to/valid_until as per Test 8, valid_from updated

-- Cleanup
-- No need to drop trigger, sql_saga does it with drop_era
SELECT sql_saga.drop_unique_key('trigger_test.temporal_table',ARRAY['id']);
SELECT sql_saga.drop_era('trigger_test.temporal_table'::regclass);
DROP TABLE trigger_test.temporal_table;
DROP FUNCTION trigger_test.show_table();
DROP SCHEMA trigger_test CASCADE;

ROLLBACK;

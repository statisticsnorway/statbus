BEGIN;
\i test/setup.sql

\echo '----------------------------------------------------------------------------'
\echo 'Test: public.synchronize_valid_from_after trigger behavior'
\echo '----------------------------------------------------------------------------'
SET client_min_messages TO NOTICE;

-- Setup: Create a test table with valid_from, valid_after, and valid_to
CREATE SCHEMA IF NOT EXISTS trigger_test;

CREATE TABLE trigger_test.temporal_table (
    id SERIAL PRIMARY KEY,
    description TEXT,
    valid_from DATE,
    valid_after DATE,
    valid_to DATE NOT NULL,
    CONSTRAINT valid_period_check CHECK (valid_after < valid_to AND valid_from <= valid_to AND valid_from = (valid_after + INTERVAL '1 day'))
);

-- Apply the trigger to the test table
CREATE TRIGGER synchronize_valid_from_after_trigger
BEFORE INSERT OR UPDATE ON trigger_test.temporal_table
FOR EACH ROW EXECUTE FUNCTION public.synchronize_valid_from_after();

-- Function to display table contents
CREATE OR REPLACE FUNCTION trigger_test.show_table()
RETURNS TABLE (id INT, description TEXT, valid_from DATE, valid_after DATE, valid_to DATE) AS $$
BEGIN
    RETURN QUERY SELECT tt.id, tt.description, tt.valid_from, tt.valid_after, tt.valid_to
                 FROM trigger_test.temporal_table tt ORDER BY tt.id, tt.valid_after;
END;
$$ LANGUAGE plpgsql;

-- Test INSERT scenarios
\echo '--- INSERT Scenarios ---'

-- 1. INSERT with only valid_from
\echo 'Test 1: INSERT with only valid_from'
INSERT INTO trigger_test.temporal_table (description, valid_from, valid_to) VALUES ('Test 1', '2024-01-01', '2024-12-31');
SELECT * FROM trigger_test.show_table(); -- Expected: valid_after = 2023-12-31

-- 2. INSERT with only valid_after
\echo 'Test 2: INSERT with only valid_after'
INSERT INTO trigger_test.temporal_table (description, valid_after, valid_to) VALUES ('Test 2', '2024-01-15', '2024-11-30');
SELECT * FROM trigger_test.show_table(); -- Expected: valid_from = 2024-01-16

-- 3. INSERT with both valid_from and valid_after (consistent)
\echo 'Test 3: INSERT with both valid_from and valid_after (consistent)'
INSERT INTO trigger_test.temporal_table (description, valid_from, valid_after, valid_to) VALUES ('Test 3', '2024-02-01', '2024-01-31', '2024-10-31');
SELECT * FROM trigger_test.show_table(); -- Expected: No error, values as inserted

-- 4. INSERT with both valid_from and valid_after (inconsistent) - Expect error
\echo 'Test 4: INSERT with both valid_from and valid_after (inconsistent) - Expect error'
DO $$
BEGIN
    INSERT INTO trigger_test.temporal_table (description, valid_from, valid_after, valid_to) VALUES ('Test 4 Fail', '2024-03-01', '2024-03-01', '2024-09-30');
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Test 4 Caught expected error: %', SQLERRM;
END $$;
SELECT * FROM trigger_test.show_table(); -- Should not contain 'Test 4 Fail'

-- 5. INSERT with neither valid_from nor valid_after - Expect error
\echo 'Test 5: INSERT with neither valid_from nor valid_after - Expect error'
DO $$
BEGIN
    INSERT INTO trigger_test.temporal_table (description, valid_to) VALUES ('Test 5 Defaulted But Fails Check', '2024-07-31');
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Test 5 Caught expected error: %', SQLERRM;
END $$;
SELECT * FROM trigger_test.show_table(); -- Should not contain 'Test 5 Defaulted But Fails Check'

-- Test UPDATE scenarios
\echo '--- UPDATE Scenarios ---'
-- Setup a base row for UPDATE tests
INSERT INTO trigger_test.temporal_table (description, valid_from, valid_after, valid_to) VALUES ('Base Update Row', '2025-01-01', '2024-12-31', '2025-12-31') RETURNING id \gset base_update_id_

-- 6. UPDATE changing valid_from
\echo 'Test 6: UPDATE changing valid_from'
UPDATE trigger_test.temporal_table SET valid_from = '2025-02-01' WHERE id = :base_update_id_id;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Expected: valid_after = 2025-01-31

-- 7. UPDATE changing valid_after
\echo 'Test 7: UPDATE changing valid_after'
UPDATE trigger_test.temporal_table SET valid_after = '2025-02-28' WHERE id = :base_update_id_id;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Expected: valid_from = 2025-03-01

-- 8. UPDATE changing valid_from, and valid_after consistently
\echo 'Test 8: UPDATE changing valid_from, and valid_after consistently'
UPDATE trigger_test.temporal_table SET valid_from = '2025-04-01', valid_after = '2025-03-31' WHERE id = :base_update_id_id;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Expected: No error, values as updated

-- 9. UPDATE changing valid_from, and valid_after inconsistently - Expect error
\echo 'Test 9: UPDATE changing valid_from, and valid_after inconsistently - Expect error'
SET app.current_base_id = :base_update_id_id;
DO $$
DECLARE
  target_id INT := current_setting('app.current_base_id')::INT;
BEGIN
    EXECUTE format('UPDATE trigger_test.temporal_table SET valid_from = %L, valid_after = %L WHERE id = %L',
                   '2025-05-01'::DATE, '2025-05-01'::DATE, target_id);
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Test 9 Caught expected error: %', SQLERRM;
END $$;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Should reflect state from Test 8

-- 10. UPDATE setting valid_from to NULL - Expect error
\echo 'Test 10: UPDATE setting valid_from to NULL - Expect error'
SET app.current_base_id = :base_update_id_id;
DO $$
DECLARE
  target_id INT := current_setting('app.current_base_id')::INT;
BEGIN
    EXECUTE format('UPDATE trigger_test.temporal_table SET valid_from = NULL WHERE id = %L', target_id);
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Test 10 Caught expected error: %', SQLERRM;
END $$;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Should reflect state from Test 8

-- 11. UPDATE setting valid_after to NULL - Expect error
\echo 'Test 11: UPDATE setting valid_after to NULL - Expect error'
SET app.current_base_id = :base_update_id_id;
DO $$
DECLARE
  target_id INT := current_setting('app.current_base_id')::INT;
BEGIN
    EXECUTE format('UPDATE trigger_test.temporal_table SET valid_after = NULL WHERE id = %L', target_id);
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Test 11 Caught expected error: %', SQLERRM;
END $$;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Should reflect state from Test 8

-- 12. UPDATE changing only valid_to (should not affect valid_from/valid_after)
\echo 'Test 12: UPDATE changing only valid_to'
UPDATE trigger_test.temporal_table SET valid_to = '2026-01-31' WHERE id = :base_update_id_id;
SELECT * FROM trigger_test.show_table() WHERE id = :base_update_id_id; -- Expected: valid_from/valid_after as per Test 8, valid_to updated

-- Cleanup
DROP TABLE trigger_test.temporal_table; -- Trigger will be dropped with the table
DROP FUNCTION trigger_test.show_table();
DROP SCHEMA trigger_test CASCADE;

ROLLBACK;

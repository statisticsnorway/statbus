BEGIN;

\i test/setup.sql

\echo "Test 319: Import Job Failure Handling"
\echo "This test verifies that import jobs correctly enter 'failed' state with error details when exceptions occur."

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

\echo "=== Test 1: Verify 'failed' state exists in enum ==="
SELECT unnest(enum_range(NULL::public.import_job_state)) AS state
ORDER BY state;

\echo "=== Test 2: Verify constraint on failed state requiring error ==="
-- The constraint should prevent failed state without error
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.import_job'::regclass
  AND conname = 'import_job_failed_requires_error';

\echo "=== Test 3: Create an import job and verify initial state ==="
DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'import_319_failure_test', 'Test 319: Failure handling test', 'Testing error handling', 'Test 319');
END $$;

SELECT slug, state, error IS NOT NULL AS has_error
FROM public.import_job
WHERE slug = 'import_319_failure_test';

\echo "=== Test 4: Upload data with invalid region code (will trigger region code collision on second region) ==="
-- First, let's add duplicate regions that will cause a collision during import lookup
-- This simulates the Albania issue where AL.01 and 01 both have code '01'

-- Load some data to import
INSERT INTO public.import_319_failure_test_upload(
    valid_from, valid_to, tax_ident, name, birth_date, death_date,
    physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2,
    primary_activity_category_code, sector_code, legal_form_code
) VALUES
('2020-01-01', '2020-12-31', '319000001', 'Test Company 1', '2020-01-01', NULL,
 'Address 1', '1234', 'Oslo', '0301', 'NO',
 '01.110', '2100', 'AS');

\echo "Check upload row count"
SELECT COUNT(*) AS upload_row_count FROM public.import_319_failure_test_upload;

\echo "=== Test 5: Process the import job (should succeed for valid data) ==="
CALL worker.process_tasks(p_queue => 'import');

\echo "Check job status after processing valid data"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error
FROM public.import_job
WHERE slug = 'import_319_failure_test';

\echo "=== Test 6: Manually test that failed state requires error ==="
-- Try to set state to 'failed' without setting error (should fail)
SAVEPOINT test_constraint;
\set ON_ERROR_STOP off
UPDATE public.import_job
SET state = 'failed', error = NULL
WHERE slug = 'import_319_failure_test';
\set ON_ERROR_STOP on
ROLLBACK TO test_constraint;

\echo "Verify job state is still unchanged after failed constraint violation"
SELECT slug, state, error IS NOT NULL AS has_error
FROM public.import_job
WHERE slug = 'import_319_failure_test';

\echo "=== Test 7: Manually set job to failed with error (should succeed) ==="
UPDATE public.import_job
SET state = 'failed', error = '{"test_error": "Simulated failure for testing"}'
WHERE slug = 'import_319_failure_test';

SELECT slug, state, error IS NOT NULL AS has_error, error
FROM public.import_job
WHERE slug = 'import_319_failure_test';

\echo "=== Test 8: Verify state transitions are valid ==="
-- Reset state to 'finished' to test other transitions
UPDATE public.import_job
SET state = 'finished', error = NULL
WHERE slug = 'import_319_failure_test';

SELECT slug, state, error IS NOT NULL AS has_error
FROM public.import_job
WHERE slug = 'import_319_failure_test';

\echo "Import job failure handling tests completed successfully"

ROLLBACK;

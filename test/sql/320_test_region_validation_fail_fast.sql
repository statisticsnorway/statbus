SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

\echo "Test 320: Region Validation Fail-Fast Behavior"
\echo "Testing ACTIONABLE FAIL FAST when settings.country_id is not configured"

-- A Super User configures statbus WITHOUT settings
CALL test.set_user_from_email('test.admin@statbus.org');

-- Don't load activity categories or regions - they require settings to be configured first.
-- We only need the import_definition (which exists by default) to test analyse_location.

-- Explicitly clear settings to test fail-fast behavior
DELETE FROM public.settings;

\echo "Verify settings table is empty (no country_id configured)"
SELECT COUNT(*) as settings_count FROM public.settings;

\echo "Test 320.1: Direct test of analyse_location procedure without configured country_id - MUST FAIL FAST"

SAVEPOINT test_320_1_start;

DO $$
DECLARE 
    v_definition_id INT; 
    v_definition_slug TEXT := 'legal_unit_job_provided';
    v_job_id INT;
    error_caught BOOLEAN := FALSE;
    error_message TEXT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN 
        RAISE EXCEPTION 'Import definition % not found.', v_definition_slug; 
    END IF;
    
    -- Create job WITH required time fields (this was the bug!)
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment, 
                                  default_valid_from, default_valid_to)
    VALUES (v_definition_id, 'import_320_01_fail_fast_test', 'Test 320.1: Fail Fast Test', 'Test 320.1',
            '2023-01-01'::date, '2023-12-31'::date)
    RETURNING id INTO v_job_id;

    -- Try to directly call the analyse_location procedure that SHOULD fail fast
    BEGIN
        CALL import.analyse_location(v_job_id, 1, 'physical_location');
        -- If we get here, the fail-fast did NOT work
        RAISE EXCEPTION 'FAIL-FAST VALIDATION NOT WORKING: analyse_location should fail when settings.country_id is not configured';
    EXCEPTION
        WHEN OTHERS THEN
            error_caught := TRUE;
            error_message := SQLERRM;
    END;
    
    -- Verify we caught an error
    IF NOT error_caught THEN
        RAISE EXCEPTION 'CRITICAL: analyse_location should fail when settings.country_id is not configured';
    END IF;
    
    -- Verify the error message contains the expected fail-fast text
    IF error_message NOT LIKE '%No country_id configured in settings table%' THEN
        RAISE EXCEPTION 'CRITICAL: Error message incorrect. Expected fail-fast message, got: %', error_message;
    END IF;
    
    -- Output success without job-specific details (job IDs change between runs)
    RAISE NOTICE 'Test 320.1 PASSED: analyse_location correctly fails fast when settings.country_id is not configured';
END $$;

ROLLBACK TO SAVEPOINT test_320_1_start;

-- Note: Test 320.2 (invalid country_id) was removed because the FK constraint on
-- settings.country_id already provides fail-fast behavior at the schema level,
-- which is even better than runtime validation. We cannot insert an invalid
-- country_id, so the code path checking for it is unreachable in normal operation.

\echo "Test 320.2: Test analyse_location with CORRECT settings - should succeed"

-- Configure settings properly
INSERT INTO public.settings(activity_category_standard_id, country_id)
SELECT (SELECT id FROM activity_category_standard WHERE code = 'nace_v2.1')
     , (SELECT id FROM public.country WHERE iso_2 = 'NO');

\echo "Settings now configured correctly:"
SELECT s.country_id, c.name as country_name 
FROM public.settings s 
JOIN public.country c ON s.country_id = c.id;

DO $$
DECLARE 
    v_definition_id INT; 
    v_definition_slug TEXT := 'legal_unit_job_provided';
    v_job_id INT;
    success BOOLEAN := TRUE;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment, 
                                  default_valid_from, default_valid_to)
    VALUES (v_definition_id, 'import_320_03_success_test', 'Test 320.3: Success Test', 'Test 320.3',
            '2023-01-01'::date, '2023-12-31'::date)
    RETURNING id INTO v_job_id;

    -- This should succeed with proper configuration (even with no data to process)
    BEGIN
        CALL import.analyse_location(v_job_id, 1, 'physical_location');
    EXCEPTION
        WHEN OTHERS THEN
            success := FALSE;
            RAISE EXCEPTION 'CRITICAL: analyse_location should succeed when settings.country_id is properly configured. Error: %', SQLERRM;
    END;
    
    -- Output success without job-specific details
    RAISE NOTICE 'Test 320.2 PASSED: analyse_location succeeds when settings.country_id is properly configured';
END $$;

\echo "Test 320 Summary: All FAIL FAST validation tests completed"
SELECT 'PASS' as test_result, 'All fail-fast scenarios working correctly' as message;

ROLLBACK;
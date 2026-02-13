-- Test: activity_category code recalculation when activity_category_standard.code_pattern changes
-- Verifies that changing code_pattern cascades to recalculate all related activity_category.code values

\echo '>>> Test Suite: Activity Category Code Pattern Cascade <<<'
SET client_min_messages TO NOTICE;

-- =============================================================================
-- Setup: Create a test activity_category_standard and some activity_category entries
-- =============================================================================

\echo '--- Setup: Create test data ---'

-- Insert a test standard with 'digits' pattern
INSERT INTO public.activity_category_standard(code, name, description, code_pattern)
VALUES ('test_std', 'Test Standard', 'Test Standard for code pattern cascade', 'digits');

-- Get the standard_id for our test standard
\echo '-- Verify test standard created --'
SELECT code, code_pattern FROM public.activity_category_standard WHERE code = 'test_std';

-- Insert some activity categories with paths that will show the difference between patterns
-- Path 'A.01.1.1.0' should become:
--   - 'digits':              '01110'
--   - 'dot_after_two_digits': '01.110'
INSERT INTO public.activity_category(standard_id, path, name, description, enabled, custom)
SELECT acs.id, 'A', 'Section A', 'Agriculture', true, false
FROM public.activity_category_standard AS acs WHERE acs.code = 'test_std';

INSERT INTO public.activity_category(standard_id, path, name, description, enabled, custom)
SELECT acs.id, 'A.01', 'Division 01', 'Crop production', true, false
FROM public.activity_category_standard AS acs WHERE acs.code = 'test_std';

INSERT INTO public.activity_category(standard_id, path, name, description, enabled, custom)
SELECT acs.id, 'A.01.1', 'Group 01.1', 'Growing of non-perennial crops', true, false
FROM public.activity_category_standard AS acs WHERE acs.code = 'test_std';

INSERT INTO public.activity_category(standard_id, path, name, description, enabled, custom)
SELECT acs.id, 'A.01.1.1', 'Class 01.11', 'Growing of cereals', true, false
FROM public.activity_category_standard AS acs WHERE acs.code = 'test_std';

INSERT INTO public.activity_category(standard_id, path, name, description, enabled, custom)
SELECT acs.id, 'A.01.1.1.0', 'Subclass 01.110', 'Growing of cereals (detailed)', true, false
FROM public.activity_category_standard AS acs WHERE acs.code = 'test_std';

-- Also insert a disabled category to verify disabled categories are also updated
INSERT INTO public.activity_category(standard_id, path, name, description, enabled, custom)
SELECT acs.id, 'B.05', 'Division 05 (disabled)', 'Mining of coal', false, false
FROM public.activity_category_standard AS acs WHERE acs.code = 'test_std';

\echo '-- Verify activity categories with digits pattern --'
SELECT ac.path, ac.code, ac.enabled
FROM public.activity_category AS ac
JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
WHERE acs.code = 'test_std'
ORDER BY ac.path;

-- =============================================================================
-- Test 1: Verify initial codes are correct for 'digits' pattern
-- =============================================================================

\echo '--- Test 1: Verify initial codes with digits pattern ---'
DO $$
BEGIN
    BEGIN
        RAISE NOTICE 'Test 1: Verifying initial codes with digits pattern';
        
        -- Check that codes are correctly derived with 'digits' pattern
        ASSERT (SELECT ac.code FROM public.activity_category AS ac
                JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
                WHERE acs.code = 'test_std' AND ac.path::text = 'A.01.1.1.0') = '01110',
               'Path A.01.1.1.0 should have code 01110 with digits pattern';
        
        ASSERT (SELECT ac.code FROM public.activity_category AS ac
                JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
                WHERE acs.code = 'test_std' AND ac.path::text = 'A.01') = '01',
               'Path A.01 should have code 01 with digits pattern';
        
        ASSERT (SELECT ac.code FROM public.activity_category AS ac
                JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
                WHERE acs.code = 'test_std' AND ac.path::text = 'B.05') = '05',
               'Path B.05 (disabled) should have code 05 with digits pattern';
        
        RAISE NOTICE 'Test 1: PASSED - Initial codes correct for digits pattern';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 1: FAILED (ASSERT_FAILURE): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 1: FAILED (OTHER ERROR): %', SQLERRM;
    END;
END;
$$;

-- =============================================================================
-- Test 2: Change code_pattern and verify codes are recalculated
-- =============================================================================

\echo '--- Test 2: Change code_pattern to dot_after_two_digits ---'

-- Change the code_pattern - this should trigger recalculation
UPDATE public.activity_category_standard
SET code_pattern = 'dot_after_two_digits'
WHERE code = 'test_std';

\echo '-- Verify activity categories after code_pattern change --'
SELECT ac.path, ac.code, ac.enabled
FROM public.activity_category AS ac
JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
WHERE acs.code = 'test_std'
ORDER BY ac.path;

DO $$
BEGIN
    BEGIN
        RAISE NOTICE 'Test 2: Verifying codes after changing to dot_after_two_digits pattern';
        
        -- Check that codes are correctly recalculated with 'dot_after_two_digits' pattern
        ASSERT (SELECT ac.code FROM public.activity_category AS ac
                JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
                WHERE acs.code = 'test_std' AND ac.path::text = 'A.01.1.1.0') = '01.110',
               'Path A.01.1.1.0 should have code 01.110 with dot_after_two_digits pattern';
        
        ASSERT (SELECT ac.code FROM public.activity_category AS ac
                JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
                WHERE acs.code = 'test_std' AND ac.path::text = 'A.01') = '01',
               'Path A.01 should still have code 01 (no change for 2-digit codes)';
        
        ASSERT (SELECT ac.code FROM public.activity_category AS ac
                JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
                WHERE acs.code = 'test_std' AND ac.path::text = 'A.01.1') = '01.1',
               'Path A.01.1 should have code 01.1 with dot_after_two_digits pattern';
        
        -- Verify disabled categories are also updated
        ASSERT (SELECT ac.code FROM public.activity_category AS ac
                JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
                WHERE acs.code = 'test_std' AND ac.path::text = 'B.05') = '05',
               'Path B.05 (disabled) should still have code 05 (no change for 2-digit codes)';
        
        RAISE NOTICE 'Test 2: PASSED - Codes correctly recalculated after code_pattern change';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 2: FAILED (ASSERT_FAILURE): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 2: FAILED (OTHER ERROR): %', SQLERRM;
    END;
END;
$$;

-- =============================================================================
-- Test 3: Change code_pattern back and verify codes revert
-- =============================================================================

\echo '--- Test 3: Change code_pattern back to digits ---'

UPDATE public.activity_category_standard
SET code_pattern = 'digits'
WHERE code = 'test_std';

\echo '-- Verify activity categories after reverting code_pattern --'
SELECT ac.path, ac.code, ac.enabled
FROM public.activity_category AS ac
JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
WHERE acs.code = 'test_std'
ORDER BY ac.path;

DO $$
BEGIN
    BEGIN
        RAISE NOTICE 'Test 3: Verifying codes after reverting to digits pattern';
        
        ASSERT (SELECT ac.code FROM public.activity_category AS ac
                JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
                WHERE acs.code = 'test_std' AND ac.path::text = 'A.01.1.1.0') = '01110',
               'Path A.01.1.1.0 should revert to code 01110 with digits pattern';
        
        ASSERT (SELECT ac.code FROM public.activity_category AS ac
                JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
                WHERE acs.code = 'test_std' AND ac.path::text = 'A.01.1') = '011',
               'Path A.01.1 should revert to code 011 with digits pattern';
        
        RAISE NOTICE 'Test 3: PASSED - Codes correctly reverted to digits pattern';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 3: FAILED (ASSERT_FAILURE): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 3: FAILED (OTHER ERROR): %', SQLERRM;
    END;
END;
$$;

-- =============================================================================
-- Test 4: Verify no-op when code_pattern doesn't change
-- =============================================================================

\echo '--- Test 4: Verify no recalculation when code_pattern unchanged ---'

DO $$
DECLARE
    original_updated_at timestamptz;
    new_updated_at timestamptz;
BEGIN
    BEGIN
        RAISE NOTICE 'Test 4: Verifying no recalculation when code_pattern is unchanged';
        
        -- Get the current updated_at for a category
        SELECT updated_at INTO original_updated_at
        FROM public.activity_category AS ac
        JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
        WHERE acs.code = 'test_std' AND ac.path::text = 'A.01.1.1.0';
        
        -- Wait a tiny bit to ensure timestamp would change if update happened
        PERFORM pg_sleep(0.01);
        
        -- Update the standard but don't change code_pattern (change name instead)
        UPDATE public.activity_category_standard
        SET name = 'Test Standard Updated'
        WHERE code = 'test_std';
        
        -- Get the updated_at again
        SELECT updated_at INTO new_updated_at
        FROM public.activity_category AS ac
        JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
        WHERE acs.code = 'test_std' AND ac.path::text = 'A.01.1.1.0';
        
        -- The updated_at should NOT have changed
        ASSERT original_updated_at = new_updated_at,
               format('updated_at should not change when code_pattern is unchanged (was %s, now %s)', 
                      original_updated_at, new_updated_at);
        
        RAISE NOTICE 'Test 4: PASSED - No recalculation when code_pattern unchanged';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 4: FAILED (ASSERT_FAILURE): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 4: FAILED (OTHER ERROR): %', SQLERRM;
    END;
END;
$$;

-- =============================================================================
-- Cleanup: Remove test data
-- =============================================================================

\echo '--- Cleanup: Remove test data ---'

-- Delete activity categories first (due to FK constraint)
DELETE FROM public.activity_category
WHERE standard_id = (SELECT id FROM public.activity_category_standard WHERE code = 'test_std');

-- Delete the test standard
DELETE FROM public.activity_category_standard WHERE code = 'test_std';

\echo '>>> Test Suite: Activity Category Code Pattern Cascade Complete <<<'

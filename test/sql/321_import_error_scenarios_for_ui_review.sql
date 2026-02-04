--
-- Test: Import Error Scenarios for UI Review
--
-- This test creates import jobs with various error types to allow visual
-- inspection of how errors and invalid_codes are displayed in the UI.
--
-- Run with PERSIST=true to keep data for UI review:
--   ./devops/manage-statbus.sh psql --variable=PERSIST=true < test/sql/404_import_error_scenarios_for_ui_review.sql
--
-- Then view in the UI:
--   - Job list: http://localhost:3012/import/jobs
--   - Job data: http://localhost:3012/import/jobs/errors_lu_analysis/data
--
-- Error types demonstrated:
--   1. Hard errors (errors column) - rows that cannot be imported:
--      - Invalid codes (sector, legal_form, activity)
--      - Malformed dates (birth_date, valid_from, valid_to)
--      - Invalid period (valid_from > valid_to)
--      - Invalid region/country codes
--      - Missing required identifiers
--
--   2. Soft errors (invalid_codes column) - rows imported with warnings:
--      - Invalid status code (falls back to default)
--      - Invalid postal region (location still created)
--      - Domestic unit missing region (warning only)
--
-- Structure:
--   0. Cleanup phase: Ensure clean state from prior runs
--   1. Setup phase: Create Norway environment and import definitions
--   2. Create jobs and upload data with errors
--   3. Process imports
--   4. Display results
--   5. Cleanup unless PERSIST=true
--

-- ============================================================================
-- PHASE 0: INITIAL CLEANUP AND PAUSE WORKER
-- ============================================================================
\echo '=== Phase 0: Cleanup and pause worker ==='
-- Use 'data' scope to preserve import_definitions (created by migrations)
-- 'getting-started' would delete them, requiring us to recreate them
SELECT public.reset(true, 'data');
SELECT worker.pause('1 hour'::interval);

-- ============================================================================
-- PHASE 1: SETUP (in transaction for setup.sql helpers)
-- ============================================================================
BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\echo '=== Phase 1: Setting up Norway environment ==='
\i samples/norway/getting-started.sql

COMMIT;

-- ============================================================================
-- PHASE 2: CREATE JOBS AND UPLOAD DATA
-- ============================================================================
\echo '=== Phase 2: Creating import jobs with error scenarios ==='

-- Job 1: Legal Unit with various analysis errors (comprehensive)
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'errors_lu_analysis', 'LU Import with Analysis Errors',
            'Demonstrates various hard errors (invalid codes, malformed dates) and soft errors (invalid_codes that fall back to defaults)',
            'Test 404: Error scenarios for UI review');
END $$;

\echo 'Uploading data with various error types...'
INSERT INTO public.errors_lu_analysis_upload(
    tax_ident, name, valid_from, valid_to, 
    sector_code, legal_form_code, primary_activity_category_code, 
    birth_date, death_date,
    secondary_activity_category_code, 
    physical_address_part1, physical_region_code, physical_country_iso_2, physical_latitude,
    postal_address_part1, postal_region_code, postal_country_iso_2,
    status_code, data_source_code, unit_size_code,
    employees, turnover
) VALUES
-- === VALID ROWS (for comparison) ===
('VALID001', 'Valid Company Alpha', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2020-01-15', NULL, NULL, 'Main Street 1', '0301', 'NO', '59.9139', NULL, NULL, NULL, 'active', NULL, NULL, 50, 1000000),
('VALID002', 'Valid Company Beta', '2023-01-01', '2023-12-31', '2100', 'ENK', '47.110', '2019-06-01', NULL, NULL, 'Market Square 5', '1103', 'NO', '58.9700', NULL, NULL, NULL, 'active', NULL, NULL, 10, 250000),

-- === HARD ERRORS: Invalid Codes ===
('ERR_SEC', 'Invalid Sector Code', '2023-01-01', '2023-12-31', 'INVALID_SECTOR', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
('ERR_LF', 'Invalid Legal Form', '2023-01-01', '2023-12-31', '2100', 'INVALID_LF', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
('ERR_ACT1', 'Invalid Primary Activity', '2023-01-01', '2023-12-31', '2100', 'AS', '99.999', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
('ERR_ACT2', 'Invalid Secondary Activity', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, '88.888', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),

-- === HARD ERRORS: Malformed Dates ===
('ERR_VF', 'Malformed ValidFrom', 'NOT_A_DATE', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
('ERR_VT', 'Malformed ValidTo', '2023-01-01', 'ALSO_NOT_DATE', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
('ERR_BD', 'Malformed BirthDate', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-13-45', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
('ERR_DD', 'Malformed DeathDate', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', '2023-02-30', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'inactive', NULL, NULL, NULL, NULL),

-- === HARD ERRORS: Invalid Period ===
-- NOTE: Commented out because this causes a batch-level exception during
-- analyse_valid_time which stops all row processing. This demonstrates a
-- job-level failure vs row-level errors. Uncomment to test job failures.
-- ('ERR_PER', 'Invalid Period (from > to)', '2023-12-31', '2023-01-01', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),

-- === HARD ERRORS: Missing Required Dates ===
('ERR_NVF', 'Missing ValidFrom', NULL, '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
('ERR_NVT', 'Missing ValidTo', '2023-01-01', NULL, '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),

-- === HARD ERRORS: Location Errors ===
('ERR_REG', 'Invalid Region Code', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, 'Street 1', 'INVALID_REG', 'NO', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
('ERR_CTY', 'Invalid Country Code', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, 'Street 1', '0301', 'ZZ', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
('ERR_LAT', 'Invalid Latitude Format', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, 'NO', 'not_a_number', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
('ERR_LATR', 'Latitude Out of Range', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, 'NO', '95.0', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),

-- === HARD ERRORS: Other Invalid Codes ===
('ERR_DS', 'Invalid DataSource', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'INVALID_DS', NULL, NULL, NULL),
('ERR_US', 'Invalid UnitSize', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'HUGE', NULL, NULL),

-- === HARD ERRORS: Invalid Statistical Variables ===
('ERR_EMP', 'Invalid Employees (not integer)', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'fifty', NULL),
('ERR_TUR', 'Invalid Turnover (not numeric)', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'one million'),

-- === SOFT ERRORS: Invalid Codes with Fallback (invalid_codes column) ===
('WARN_STS', 'Invalid Status (uses default)', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'sleeping_unknown', NULL, NULL, 25, 500000),
('WARN_PREG', 'Invalid Postal Region', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, 'Office Park 10', '0301', 'NO', NULL, 'PO Box 123', 'INVALID_POSTAL', NULL, 'active', NULL, NULL, 15, 300000),
('WARN_PCTY', 'Invalid Postal Country', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, 'Harbor Street 7', '1103', 'NO', NULL, 'Overseas Box', NULL, 'XX', 'active', NULL, NULL, 8, 150000),

-- === SOFT ERRORS: Missing Region Warnings ===
('WARN_NREG', 'Domestic Missing Region (warning)', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, 'Unknown Location', NULL, 'NO', NULL, NULL, NULL, NULL, 'active', NULL, NULL, 5, 100000),
('OK_FREG', 'Foreign Missing Region (ok)', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, 'International HQ', NULL, 'SE', NULL, NULL, NULL, NULL, 'active', NULL, NULL, 100, 5000000),
('WARN_FDREG', 'Foreign with Domestic Region (error)', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110', '2023-01-01', NULL, NULL, 'Mixed Location', '0301', 'SE', NULL, NULL, NULL, NULL, 'active', NULL, NULL, 20, 400000);

\echo 'Upload complete. Row count:'
SELECT COUNT(*) as uploaded_rows FROM public.errors_lu_analysis_upload;

-- Job 2: Formal Establishment with link errors
DO $$
DECLARE 
    v_lu_def_id INT;
    v_es_def_id INT;
BEGIN
    SELECT id INTO v_lu_def_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    SELECT id INTO v_es_def_id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
    
    -- First create some valid LUs for the ES to link to
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_lu_def_id, 'errors_lu_for_es', 'Valid LUs for Establishment Tests',
            'These LUs are created to test establishment linking errors',
            'Test 404');
    
    -- Then create ES job with link errors
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_es_def_id, 'errors_es_formal', 'Formal ES with Link Errors',
            'Demonstrates establishment-to-LU linking errors',
            'Test 404');
END $$;

-- Upload valid LUs first
INSERT INTO public.errors_lu_for_es_upload(tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, primary_activity_category_code)
VALUES
('LU_FOR_ES_001', 'Parent Company One', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110'),
('LU_FOR_ES_002', 'Parent Company Two', '2023-01-01', '2023-12-31', '2100', 'ENK', '47.110');

-- Upload ES with various link errors
INSERT INTO public.errors_es_formal_upload(tax_ident, name, valid_from, valid_to, primary_activity_category_code, legal_unit_tax_ident)
VALUES
-- Valid establishment
('ES_VALID', 'Valid Establishment', '2023-01-01', '2023-12-31', '01.110', 'LU_FOR_ES_001'),
-- Missing LU link
('ES_NO_LINK', 'ES Missing LU Link', '2023-01-01', '2023-12-31', '01.110', NULL),
-- Non-existent LU
('ES_BAD_LINK', 'ES Links to Non-Existent LU', '2023-01-01', '2023-12-31', '01.110', 'LU_DOES_NOT_EXIST'),
-- Invalid activity code
('ES_BAD_ACT', 'ES Invalid Activity', '2023-01-01', '2023-12-31', '99.999', 'LU_FOR_ES_002');

-- Job 3: Missing identifier errors
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'errors_lu_missing_ident', 'LU Missing Identifiers',
            'Demonstrates errors when required identifiers are missing',
            'Test 404');
END $$;

INSERT INTO public.errors_lu_missing_ident_upload(tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, primary_activity_category_code)
VALUES
(NULL, 'Missing Tax Ident', '2023-01-01', '2023-12-31', '2100', 'AS', '01.110'),
('HAS_IDENT', NULL, '2023-01-01', '2023-12-31', '2100', 'AS', '01.110');

-- ============================================================================
-- PHASE 3: PROCESS IMPORTS
-- ============================================================================
\echo '=== Phase 3: Processing imports ==='

-- Process all pending import tasks
CALL worker.process_tasks(p_queue => 'import');

-- Resume worker for normal operation
SELECT worker.resume();

-- ============================================================================
-- PHASE 4: DISPLAY RESULTS
-- ============================================================================
\echo '=== Phase 4: Results Summary ==='

\echo ''
\echo '--- Import Job Status ---'
SELECT 
    slug,
    state,
    total_rows,
    imported_rows,
    total_rows - COALESCE(imported_rows, 0) as failed_rows,
    error IS NOT NULL AS has_job_error
FROM public.import_job 
WHERE slug LIKE 'errors_%'
ORDER BY slug;

\echo ''
\echo '--- Job 1: LU Analysis Errors (errors_lu_analysis) ---'
\echo 'Job-level error (if any):'
SELECT error FROM public.import_job WHERE slug = 'errors_lu_analysis';

\echo 'All rows (showing state, action, errors, invalid_codes):'
SELECT 
    row_id,
    tax_ident_raw as tax_ident,
    LEFT(name_raw, 30) as name,
    state,
    action,
    CASE WHEN errors IS NOT NULL AND errors != '{}' THEN errors ELSE NULL END as errors,
    CASE WHEN invalid_codes IS NOT NULL AND invalid_codes != '{}' THEN invalid_codes ELSE NULL END as invalid_codes
FROM public.errors_lu_analysis_data
ORDER BY row_id;

\echo ''
\echo '--- Job 2: Formal ES Link Errors (errors_es_formal) ---'
SELECT 
    row_id,
    tax_ident_raw as tax_ident,
    name_raw as name,
    state,
    action,
    errors,
    invalid_codes
FROM public.errors_es_formal_data
ORDER BY row_id;

\echo ''
\echo '--- Job 3: Missing Identifier Errors (errors_lu_missing_ident) ---'
SELECT 
    row_id,
    tax_ident_raw as tax_ident,
    name_raw as name,
    state,
    action,
    errors,
    invalid_codes
FROM public.errors_lu_missing_ident_data
ORDER BY row_id;

\echo ''
\echo '=== Summary Statistics ==='
SELECT 
    slug,
    COUNT(*) as total_rows,
    COUNT(*) FILTER (WHERE state = 'processed') as processed,
    COUNT(*) FILTER (WHERE state = 'error') as errors,
    COUNT(*) FILTER (WHERE action = 'skip') as skipped,
    COUNT(*) FILTER (WHERE errors IS NOT NULL AND errors != '{}') as rows_with_errors,
    COUNT(*) FILTER (WHERE invalid_codes IS NOT NULL AND invalid_codes != '{}') as rows_with_warnings
FROM (
    SELECT slug, state, action, errors, invalid_codes FROM public.errors_lu_analysis_data, (SELECT 'errors_lu_analysis' as slug) s
    UNION ALL
    SELECT slug, state, action, errors, invalid_codes FROM public.errors_es_formal_data, (SELECT 'errors_es_formal' as slug) s
    UNION ALL
    SELECT slug, state, action, errors, invalid_codes FROM public.errors_lu_missing_ident_data, (SELECT 'errors_lu_missing_ident' as slug) s
) combined
GROUP BY slug
ORDER BY slug;

\echo ''
\echo '=== View in UI ==='
\echo 'Job list:     http://localhost:3012/import/jobs'
\echo 'LU Errors:    http://localhost:3012/import/jobs/errors_lu_analysis/data'
\echo 'ES Errors:    http://localhost:3012/import/jobs/errors_es_formal/data'
\echo 'Missing ID:   http://localhost:3012/import/jobs/errors_lu_missing_ident/data'

-- ============================================================================
-- PHASE 5: CLEANUP UNLESS PERSIST
-- ============================================================================
\i test/cleanup_unless_persist_is_specified.sql

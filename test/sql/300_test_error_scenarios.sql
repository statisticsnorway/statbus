SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

\echo "Test 70: Sad Path - Error Scenarios"
\echo "Setting up Statbus environment for test 70"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id,only_one_setting)
SELECT id, true FROM activity_category_standard WHERE code = 'nace_v2.1'
ON CONFLICT (only_one_setting)
DO UPDATE SET
   activity_category_standard_id =(SELECT id FROM activity_category_standard WHERE code = 'nace_v2.1')
   WHERE settings.id = EXCLUDED.id;
SELECT acs.code FROM public.settings AS s JOIN activity_category_standard AS acs ON s.activity_category_standard_id = acs.id;

\echo "User uploads the sample activity categories, regions, legal forms, sectors"
\copy public.activity_category_available_custom(path,name,description) FROM 'samples/norway/activity_category/activity_category_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
\copy public.region_upload(path, name) FROM 'samples/norway/regions/norway-regions-2024.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
\copy public.legal_form_custom_only(code,name) FROM 'samples/norway/legal_form/legal_form_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
\copy public.sector_custom_only(path,name,description) FROM 'samples/norway/sector/sector_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SAVEPOINT main_test_70_start;
\echo "Initial counts before any test block for Test 70"
SELECT
    (SELECT COUNT(*) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(*) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(*) FROM public.enterprise) AS enterprise_count;

-- Scenario 70.1: Invalid Codes in Input Data
SAVEPOINT scenario_70_1_invalid_codes;
\echo "Scenario 70.1: Invalid Codes in Input Data"

-- Sub-Scenario 70.1.1: LU Import with Various Analysis Errors
\echo "Sub-Scenario 70.1.1: LU Import with Various Analysis Errors (analyse_valid_time_from_source, analyse_legal_unit, analyse_activity, analyse_tags, analyse_statistical_variables, analyse_location, analyse_status)"
DO $$
DECLARE v_definition_id INT; v_definition_slug TEXT := 'legal_unit_source_dates';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN RAISE EXCEPTION 'Import definition % not found.', v_definition_slug; END IF;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_70_01_01_lu_analysis_errors', 'Test 70.1.1: LU Analysis Errors', 'Test 70.1.1');
END $$;
INSERT INTO public.import_70_01_01_lu_analysis_errors_upload(
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, primary_activity_category_code, birth_date, death_date,
    secondary_activity_category_code, tag_path, employees, turnover,
    physical_address_part1, physical_region_code, physical_country_iso_2, physical_latitude,
    status_code, data_source_code, unit_size_code,
    postal_address_part1, postal_region_code, postal_country_iso_2
) VALUES
-- Existing errors from original test (NULLs added for new columns)
('700100001','LU Invalid Sector','2023-01-01','2023-12-31','INVALID_SEC','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
('700100002','LU Invalid LF','2023-01-01','2023-12-31','2100','INV_LF','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
('700100003','LU Invalid Activity','2023-01-01','2023-12-31','2100','AS','99.999','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
('700100004','LU Malformed Birth','2023-01-01','2023-12-31','2100','AS','01.110','2023-13-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
('700100005','LU Malformed ValidFrom','NOT_A_DATE','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
('700100006','LU Invalid Period','2023-01-01','2022-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
-- New errors for analyse_valid_time_from_source (NULLs added for new columns)
('700100007','LU Malformed ValidTo','2023-01-01','NOT_A_DATE_TOO','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
('700100008','LU Missing ValidFrom Source',NULL,'2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
('700100009','LU Missing ValidTo Source','2023-01-01',NULL,'2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),
-- New errors for analyse_legal_unit (NULLs added for new columns)
('700100010','LU Invalid DataSource','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'inactive_unknown','INVALID_DS',NULL,NULL,NULL,NULL),
('700100011','LU Invalid UnitSize','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'inactive_unknown',NULL,'BIGGER',NULL,NULL,NULL),
('700100012','LU Malformed DeathDate','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01','2023-02-30',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'inactive_unknown',NULL,NULL,NULL,NULL,NULL),
-- New error for analyse_activity (secondary) (NULLs added for new columns)
('700100013','LU Invalid SecondaryActivity','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,'88.888',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'inactive_unknown',NULL,NULL,NULL,NULL,NULL),
-- New errors for analyse_tags (NULLs added for new columns)
('700100014','LU Invalid Tag Format','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,'a b c',NULL,NULL,NULL,NULL,NULL,NULL,'inactive_unknown',NULL,NULL,NULL,NULL,NULL),
('700100015','LU Tag NotFound','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,'non.existent.tag',NULL,NULL,NULL,NULL,NULL,NULL,'inactive_unknown',NULL,NULL,NULL,NULL,NULL),
-- New errors for analyse_statistical_variables (NULLs added for new columns)
('700100016','LU Invalid Int Stat','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,'abc',NULL,NULL,NULL,NULL,NULL,'inactive_unknown',NULL,NULL,NULL,NULL,NULL),
('700100017','LU Invalid Float Stat','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,'xyz',NULL,NULL,NULL,NULL,'inactive_unknown',NULL,NULL,NULL,NULL,NULL),
-- New errors for analyse_location (physical) (NULLs added for new columns)
('700100018','LU Invalid PhysRegion','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,'XX','NO',NULL,'inactive_unknown',NULL,NULL,NULL,NULL,NULL),
('700100019','LU Invalid PhysCountry NF','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'ZZ',NULL,'inactive_unknown',NULL,NULL,NULL,NULL,NULL),
('700100020','LU Invalid PhysCountry F','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,'Street 1','01','ZZ',NULL,'inactive_unknown',NULL,NULL,NULL,NULL,NULL),
('700100021','LU Invalid PhysLat Format','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NO','abc','inactive_unknown',NULL,NULL,NULL,NULL,NULL),
('700100022','LU PhysLat Range','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NO','91.0','inactive_unknown',NULL,NULL,NULL,NULL,NULL),
-- Row for postal location tests (NULLs added for new columns)
('700100023','LU For Postal Location','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NO',NULL,'inactive_unknown',NULL,NULL,NULL,NULL,NULL),
-- New soft error test cases
('700100026','LU Invalid Status (Default Active)','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'sleeping_unknown',NULL,NULL,NULL,NULL,NULL), -- invalid_codes: {status_code}, uses default
('700100028','LU Invalid PostalRegion','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'active',NULL,NULL,NULL,'POSTAL_XX',NULL), -- invalid_codes: {postal_region_code}
('700100029','LU Invalid PostalCountry NF','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'active',NULL,NULL,NULL,NULL,'P_ZZ'); -- invalid_codes: {postal_country_iso_2}

CALL worker.process_tasks(p_queue => 'import');
\echo "Job status for import_70_01_01_lu_analysis_errors:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_70_01_01_lu_analysis_errors' ORDER BY slug;
\echo "Data table for import_70_01_01_lu_analysis_errors (expect various errors and invalid_codes):"
SELECT
    row_id,
    name_raw as name,
    state,
    action,
    valid_from,
    valid_to,
    errors,
    invalid_codes,
    merge_status,
    -- Include potentially affected resolved IDs to verify soft error handling
    status_id,
    (SELECT COUNT(*) FROM public.location l WHERE l.legal_unit_id = (SELECT legal_unit_id FROM public.import_70_01_01_lu_analysis_errors_data d_lu WHERE d_lu.row_id = d.row_id AND d_lu.legal_unit_id IS NOT NULL) AND l.type='postal') as postal_location_count
FROM public.import_70_01_01_lu_analysis_errors_data d ORDER BY row_id;

-- Test for analyse_status errors (requires temporarily disabling default status)
SAVEPOINT before_no_default_status_test_70_1_1;
\echo "Temporarily disabling default status for analyse_status tests..."
UPDATE public.status SET assigned_by_default = false WHERE code = 'active'; -- Assuming 'active' is the default

DO $$
DECLARE v_definition_id INT; v_definition_slug TEXT := 'legal_unit_source_dates';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN RAISE EXCEPTION 'Import definition % not found.', v_definition_slug; END IF;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_70_01_01_lu_status_errors', 'Test 70.1.1: LU Status Errors (No Default)', 'Test 70.1.1');
END $$;
INSERT INTO public.import_70_01_01_lu_status_errors_upload(
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, primary_activity_category_code, birth_date, status_code
) VALUES
('700100024','LU Invalid Status NoDefault','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01','INVALID_STATUS'), -- error: {status_code: "Provided status_code 'INVALID_STATUS' not found/active and no default available"}, action: skip
('700100025','LU No Status NoDefault','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL); -- error: {status_code: "Status code not provided and no active default status found"}, action: skip

CALL worker.process_tasks(p_queue => 'import');
\echo "Job status for import_70_01_01_lu_status_errors:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_70_01_01_lu_status_errors' ORDER BY slug;
\echo "Data table for import_70_01_01_lu_status_errors (expect status_code errors):"
SELECT row_id, name_raw as name, state, action, status_id, errors, invalid_codes, merge_status FROM public.import_70_01_01_lu_status_errors_data ORDER BY row_id;

\echo "Restoring default status..."
ROLLBACK TO before_no_default_status_test_70_1_1;


-- Sub-Scenario 70.1.2: Formal ES Import with Invalid Codes
\echo "Sub-Scenario 70.1.2: Formal ES Import with Invalid Codes"
DO $$
DECLARE v_lu_def_id INT; v_es_def_id INT;
BEGIN
    SELECT id INTO v_lu_def_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    IF v_lu_def_id IS NULL THEN RAISE EXCEPTION 'Import definition legal_unit_source_dates not found.'; END IF;
    SELECT id INTO v_es_def_id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
    IF v_es_def_id IS NULL THEN RAISE EXCEPTION 'Import definition establishment_for_lu_source_dates not found.'; END IF;

    INSERT INTO public.import_job (definition_id, slug, description, edit_comment) VALUES (v_lu_def_id, 'import_70_01_02_lu_for_es', 'Test 70.1.2: Valid LU for ES', 'Test 70.1.2');
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment) VALUES (v_es_def_id, 'import_70_01_02_es_invalid', 'Test 70.1.2: Formal ES Invalid Codes', 'Test 70.1.2');
END $$;
INSERT INTO public.import_70_01_02_lu_for_es_upload(tax_ident,name,valid_from,valid_to,primary_activity_category_code,sector_code,legal_form_code) VALUES
('700102001','Valid LU for ES Test','2023-01-01','2023-12-31','01.110','2100','AS');
INSERT INTO public.import_70_01_02_es_invalid_upload(tax_ident,name,valid_from,valid_to,primary_activity_category_code,legal_unit_tax_ident) VALUES
('E70010201','Formal ES Invalid Activity','2023-01-01','2023-12-31','99.998','700102001');
CALL worker.process_tasks(p_queue => 'import');
\echo "Job status for import_70_01_02_es_invalid:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug = 'import_70_01_02_es_invalid' ORDER BY slug;
\echo "Data table for import_70_01_02_es_invalid (expect errors):"
SELECT row_id, state, action, valid_from, valid_to, errors, invalid_codes, merge_status FROM public.import_70_01_02_es_invalid_data ORDER BY row_id;

-- Sub-Scenario 70.1.3: Informal ES Import with Invalid Codes
\echo "Sub-Scenario 70.1.3: Informal ES Import with Invalid Codes"
DO $$
DECLARE v_definition_id INT; v_definition_slug TEXT := 'establishment_without_lu_source_dates';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN RAISE EXCEPTION 'Import definition % not found.', v_definition_slug; END IF;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_70_01_03_es_inf_invalid', 'Test 70.1.3: Informal ES Invalid Codes', 'Test 70.1.3');
END $$;
INSERT INTO public.import_70_01_03_es_inf_invalid_upload(tax_ident,name,valid_from,valid_to,primary_activity_category_code) VALUES
('E70010301','Informal ES Invalid Activity','2023-01-01','2023-12-31','99.997');
CALL worker.process_tasks(p_queue => 'import');
\echo "Job status for import_70_01_03_es_inf_invalid:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug = 'import_70_01_03_es_inf_invalid' ORDER BY slug;
\echo "Data table for import_70_01_03_es_inf_invalid (expect errors):"
SELECT row_id, state, action, valid_from, valid_to, errors, invalid_codes, merge_status FROM public.import_70_01_03_es_inf_invalid_data ORDER BY row_id;
ROLLBACK TO scenario_70_1_invalid_codes;


-- Scenario 70.2: Missing Mandatory Data
SAVEPOINT scenario_70_2_missing_data;
\echo "Scenario 70.2: Missing Mandatory Data"
-- Sub-Scenario 70.2.1: LU Import - Missing Core Fields
\echo "Sub-Scenario 70.2.1: LU Import - Missing Core Fields"
DO $$
DECLARE v_definition_id INT; v_definition_slug TEXT := 'legal_unit_source_dates';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN RAISE EXCEPTION 'Import definition % not found.', v_definition_slug; END IF;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_70_02_01_lu_missing', 'Test 70.2.1: LU Missing Core', 'Test 70.2.1');
END $$;
INSERT INTO public.import_70_02_01_lu_missing_upload(tax_ident,name,valid_from,valid_to,primary_activity_category_code,sector_code,legal_form_code) VALUES
(NULL,'LU Missing TaxIdent','2023-01-01','2023-12-31','01.110','2100','AS'),
('700201002',NULL,'2023-01-01','2023-12-31','01.110','2100','AS'),
('700201003','LU Missing ValidFrom',NULL,'2023-12-31','01.110','2100','AS');
CALL worker.process_tasks(p_queue => 'import');
\echo "Job status for import_70_02_01_lu_missing:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug = 'import_70_02_01_lu_missing' ORDER BY slug;
\echo "Data table for import_70_02_01_lu_missing (expect errors, e.g., in analyse_external_idents):"
SELECT row_id, state, action, valid_from, valid_to, errors, invalid_codes, merge_status FROM public.import_70_02_01_lu_missing_data ORDER BY row_id;

-- Sub-Scenario 70.2.2: Formal ES Import - Missing Link
\echo "Sub-Scenario 70.2.2: Formal ES Import - Missing Link to LU"
DO $$
DECLARE v_lu_def_id INT; v_es_def_id INT;
BEGIN
    SELECT id INTO v_lu_def_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    IF v_lu_def_id IS NULL THEN RAISE EXCEPTION 'Import definition legal_unit_source_dates not found.'; END IF;
    SELECT id INTO v_es_def_id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
    IF v_es_def_id IS NULL THEN RAISE EXCEPTION 'Import definition establishment_for_lu_source_dates not found.'; END IF;

    INSERT INTO public.import_job (definition_id, slug, description, edit_comment) VALUES (v_lu_def_id, 'import_70_02_02_lu_for_es_link', 'Test 70.2.2: Valid LU for ES', 'Test 70.2.2');
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment) VALUES (v_es_def_id, 'import_70_02_02_es_missing_link', 'Test 70.2.2: Formal ES Missing LU Link', 'Test 70.2.2');
END $$;
INSERT INTO public.import_70_02_02_lu_for_es_link_upload(tax_ident,name,valid_from,valid_to,primary_activity_category_code,sector_code,legal_form_code) VALUES
('700202001','Valid LU for ES Link Test','2023-01-01','2023-12-31','01.110','2100','AS');
INSERT INTO public.import_70_02_02_es_missing_link_upload(tax_ident,name,valid_from,valid_to,primary_activity_category_code,legal_unit_tax_ident) VALUES
('E70020201','Formal ES Missing LU Link','2023-01-01','2023-12-31','01.110',NULL);
CALL worker.process_tasks(p_queue => 'import');
\echo "Job status for import_70_02_02_es_missing_link:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug = 'import_70_02_02_es_missing_link' ORDER BY slug;
\echo "Data table for import_70_02_02_es_missing_link (expect errors in analyse_establishment_legal_unit_link):"
SELECT row_id, state, action, valid_from, valid_to, errors, invalid_codes, merge_status FROM public.import_70_02_02_es_missing_link_data ORDER BY row_id;
ROLLBACK TO scenario_70_2_missing_data;


-- Scenario 70.3: Referential Integrity Errors during Processing
SAVEPOINT scenario_70_3_referential_integrity;
\echo "Scenario 70.3: Referential Integrity Errors during Processing"
-- Sub-Scenario 70.3.1: Formal ES links to Non-Existent LU
\echo "Sub-Scenario 70.3.1: Formal ES links to Non-Existent LU"
DO $$
DECLARE v_definition_id INT; v_definition_slug TEXT := 'establishment_for_lu_source_dates';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN RAISE EXCEPTION 'Import definition % not found.', v_definition_slug; END IF;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_70_03_01_es_bad_lu_link', 'Test 70.3.1: ES Bad LU Link', 'Test 70.3.1');
END $$;
INSERT INTO public.import_70_03_01_es_bad_lu_link_upload(tax_ident,name,valid_from,valid_to,primary_activity_category_code,legal_unit_tax_ident) VALUES
('E70030101','Formal ES Bad LU Link','2023-01-01','2023-12-31','01.110','NON_EXISTENT_LU_TAX_ID');
CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_70_03_01_es_bad_lu_link:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug = 'import_70_03_01_es_bad_lu_link' ORDER BY slug;
\echo "Data table for import_70_03_01_es_bad_lu_link (expect errors in process_establishment or analyse_establishment_legal_unit_link):"
SELECT row_id, state, action, valid_from, valid_to, errors, invalid_codes, merge_status FROM public.import_70_03_01_es_bad_lu_link_data ORDER BY row_id;
ROLLBACK TO scenario_70_3_referential_integrity;


-- Scenario 70.4: Constraint Violations Not Caught by Analysis (Placeholder)
SAVEPOINT scenario_70_4_constraint_violations;
\echo "Scenario 70.4: Constraint Violations Not Caught by Analysis (Placeholder - difficult to reliably simulate if analysis is robust)"
-- No specific tests here yet, as these often depend on specific DB constraints not covered by analysis.
ROLLBACK TO scenario_70_4_constraint_violations;


-- Scenario 70.5: File-Level Errors (Placeholder)
SAVEPOINT scenario_70_5_file_errors;
\echo "Scenario 70.5: File-Level Errors (Placeholder - \copy errors are typically fatal to the psql script itself or hard to verify at job level)"
-- These errors (e.g. wrong delimiter, column count mismatch) usually cause \copy to fail.
-- The import job might not even reach a state where its status can be easily checked for these specific \copy failures.
-- If \copy succeeds but data is malformed leading to prepare step failure, that's a different case.
ROLLBACK TO scenario_70_5_file_errors;


-- Scenario 70.6: Errors in batch_insert_or_replace_generic_valid_time_table
SAVEPOINT scenario_70_6_batch_replace_errors;
\echo "Scenario 70.6: Errors in batch_insert_or_replace_generic_valid_time_table"
-- Sub-Scenario 70.6.1: Unexpected NULL for NOT NULL column (e.g. empty name for LU)
\echo "Sub-Scenario 70.6.1: LU with empty name (assuming name is NOT NULL in public.legal_unit)"
DO $$
DECLARE v_definition_id INT; v_definition_slug TEXT := 'legal_unit_source_dates';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN RAISE EXCEPTION 'Import definition % not found.', v_definition_slug; END IF;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_70_06_01_lu_empty_name', 'Test 70.6.1: LU Empty Name', 'Test 70.6.1');
END $$;
INSERT INTO public.import_70_06_01_lu_empty_name_upload(tax_ident,name,valid_from,valid_to,primary_activity_category_code,sector_code,legal_form_code) VALUES
('700601001',NULL,'2023-01-01','2023-12-31','01.110','2100','AS');
CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_70_06_01_lu_empty_name:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug = 'import_70_06_01_lu_empty_name' ORDER BY slug;
\echo "Data table for import_70_06_01_lu_empty_name (expect errors in process_legal_unit from batch_replace):"
SELECT row_id, state, action, valid_from, valid_to, errors, invalid_codes, merge_status FROM public.import_70_06_01_lu_empty_name_data ORDER BY row_id;
ROLLBACK TO scenario_70_6_batch_replace_errors;

-- Scenario 70.7: analyse_external_idents Errors
SAVEPOINT scenario_70_7_external_idents_errors;
\echo "Scenario 70.7: analyse_external_idents Errors"

-- Setup common to 70.7.x: Create some LUs, ESTs for conflict checks
DO $$
DECLARE
    v_user_id INT;
    v_lu1_id INT; v_lu2_id INT;
    v_est1_id INT; v_est2_id INT; v_est_formal_id INT;
    v_ent1_id INT;
    v_ent_for_lu1_id INT; v_ent_for_lu2_id INT; -- Added variables for LU enterprises

    -- Variables for patching definitions
    v_lu_def_id_patch INT;
    v_esf_def_id_patch INT;
    v_esi_def_id_patch INT;
    v_def_ids_to_patch INT[];
    v_current_def_id_patch INT;
    v_ext_idents_step_id_patch INT;
    v_custom_ident_data_col_id_patch INT;
    v_new_source_col_id_patch INT;
    v_max_priority_patch INT;
BEGIN
    SELECT id INTO v_user_id FROM public.user WHERE email = 'test.admin@statbus.org';

    -- Ensure custom_est_ident type exists for this test block. The INSERT will trigger
    -- lifecycle callbacks that should create the data column, source columns, and mappings
    -- for 'custom_est_ident' in all relevant default import definitions, making them
    -- available for use in the import jobs below.
    INSERT INTO public.external_ident_type (code, name, description, priority)
    VALUES ('custom_est_ident', 'Custom Establishment Identifier', 'A custom identifier type for testing establishment scenarios.', 10)
    ON CONFLICT (code) DO NOTHING;

    -- Enterprise for LU1
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('ENT for LU1 70.7', v_user_id, now()) RETURNING id INTO v_ent_for_lu1_id;

    -- LU1
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES (v_ent_for_lu1_id, 'LU1 for 70.7', (SELECT id FROM public.status WHERE code = 'active'), true, v_user_id, now(), '2000-01-01') RETURNING id INTO v_lu1_id;
    INSERT INTO public.external_ident (legal_unit_id, type_id, ident, edit_by_user_id, edit_at)
    VALUES (v_lu1_id, (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident'), 'LU7071_TAX', v_user_id, now()),
           (v_lu1_id, (SELECT id FROM public.external_ident_type WHERE code = 'stat_ident'), 'LU7071_STAT', v_user_id, now());

    -- Enterprise for LU2
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('ENT for LU2 70.7', v_user_id, now()) RETURNING id INTO v_ent_for_lu2_id;

    -- LU2
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES (v_ent_for_lu2_id, 'LU2 for 70.7', (SELECT id FROM public.status WHERE code = 'active'), true, v_user_id, now(), '2000-01-01') RETURNING id INTO v_lu2_id;
    INSERT INTO public.external_ident (legal_unit_id, type_id, ident, edit_by_user_id, edit_at)
    VALUES (v_lu2_id, (SELECT id FROM public.external_ident_type WHERE code = 'stat_ident'), 'LU7072_STAT', v_user_id, now());

    -- EST1 (Informal)
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at) VALUES ('ENT1 70.7 EST1', v_user_id, now()) RETURNING id INTO v_ent1_id;
    INSERT INTO public.establishment (name, status_id, enterprise_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES ('EST1 for 70.7 (Informal)', (SELECT id FROM public.status WHERE code = 'active'), v_ent1_id, true, v_user_id, now(), '2000-01-01') RETURNING id INTO v_est1_id;
    INSERT INTO public.external_ident (establishment_id, type_id, ident, edit_by_user_id, edit_at)
    VALUES (v_est1_id, (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident'), 'EST7071_TAX', v_user_id, now());

    -- EST2 (Informal, different enterprise)
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at) VALUES ('ENT2 70.7 EST2', v_user_id, now()) RETURNING id INTO v_ent1_id; -- Re-use v_ent1_id for new enterprise
    INSERT INTO public.establishment (name, status_id, enterprise_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES ('EST2 for 70.7 (Informal)', (SELECT id FROM public.status WHERE code = 'active'), v_ent1_id, true, v_user_id, now(), '2000-01-01') RETURNING id INTO v_est2_id;
    INSERT INTO public.external_ident (establishment_id, type_id, ident, edit_by_user_id, edit_at)
    VALUES (v_est2_id, (SELECT id FROM public.external_ident_type WHERE code = 'custom_est_ident'), 'EST7072_CUSTOM', v_user_id, now());

    -- EST_FORMAL (Formal, linked to LU1)
    INSERT INTO public.establishment (name, status_id, legal_unit_id, primary_for_legal_unit, edit_by_user_id, edit_at, valid_from)
    VALUES ('EST_FORMAL for 70.7', (SELECT id FROM public.status WHERE code = 'active'), v_lu1_id, true, v_user_id, now(), '2000-01-01') RETURNING id INTO v_est_formal_id;
    INSERT INTO public.external_ident (establishment_id, type_id, ident, edit_by_user_id, edit_at)
    VALUES (v_est_formal_id, (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident'), 'EST707F_TAX', v_user_id, now());

END $$;

-- Sub-Scenario 70.7.1: Mode 'legal_unit' (using 'legal_unit_source_dates')
\echo "Sub-Scenario 70.7.1: analyse_external_idents - Mode 'legal_unit'"
DO $$
DECLARE v_definition_id INT; v_definition_slug TEXT := 'legal_unit_source_dates';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_70_07_01_lu_idents', 'Test 70.7.1: LU Ident Errors', 'Test 70.7.1');
END $$;
INSERT INTO public.import_70_07_01_lu_idents_upload(tax_ident, stat_ident, name, valid_from, valid_to, sector_code, legal_form_code, primary_activity_category_code, birth_date, custom_est_ident) VALUES
(NULL,NULL,'LU NoIdents','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL), -- Error: missing_identifier_value
('LU7071_TAX','LU7072_STAT','LU Inconsistent','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL), -- Error: inconsistent_legal_unit
('EST7071_TAX',NULL,'LU CrossType EST','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL), -- Error: cross-type conflict (tax_ident used by EST1)
('LU7071_TAX','LU7071_STAT_CHANGED','LU Unstable Ident','2023-01-01','2023-12-31','2100','AS','01.110','2023-01-01',NULL) -- Error: unstable_identifier (attempts to change existing LU1.stat_ident)
;
-- The previous attempt to test an 'unknown_identifier_type' error by inserting into a
-- non-existent column in the _upload table was removed, as this causes a direct SQL error
-- rather than testing the import logic for unknown identifier type codes.
CALL worker.process_tasks(p_queue => 'import');
\echo "Data table for import_70_07_01_lu_idents (expect external_idents errors):"
SELECT row_id, name_raw as name, state, action, operation, errors, invalid_codes, merge_status, legal_unit_id FROM public.import_70_07_01_lu_idents_data ORDER BY row_id;

-- Sub-Scenario 70.7.2: Mode 'establishment_formal' (using 'establishment_for_lu_source_dates')
\echo "Sub-Scenario 70.7.2: analyse_external_idents - Mode 'establishment_formal'"
DO $$
DECLARE v_definition_id INT; v_definition_slug TEXT := 'establishment_for_lu_source_dates';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_70_07_02_est_f_idents', 'Test 70.7.2: Formal EST Ident Errors', 'Test 70.7.2');
END $$;
INSERT INTO public.import_70_07_02_est_f_idents_upload(tax_ident, name, valid_from, valid_to, primary_activity_category_code, legal_unit_tax_ident) VALUES
('EST7071_TAX','ESTF Inconsistent','2023-01-01','2023-12-31','01.110','LU7071_TAX'), -- Error: inconsistent_establishment (EST1 vs EST2) - Note: custom_est_ident 'EST7072_CUSTOM' removed due to upload table structure
('LU7071_TAX','ESTF CrossType LU','2023-01-01','2023-12-31','01.110','LU7071_TAX'); -- Error: cross-type conflict (tax_ident used by LU1)
CALL worker.process_tasks(p_queue => 'import');
\echo "Data table for import_70_07_02_est_f_idents (expect external_idents errors):"
SELECT row_id, name_raw as name, state, action, operation, errors, invalid_codes, merge_status, establishment_id FROM public.import_70_07_02_est_f_idents_data ORDER BY row_id;

-- Sub-Scenario 70.7.3: Mode 'establishment_informal' (using 'establishment_without_lu_source_dates')
\echo "Sub-Scenario 70.7.3: analyse_external_idents - Mode 'establishment_informal'"
DO $$
DECLARE v_definition_id INT; v_definition_slug TEXT := 'establishment_without_lu_source_dates';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_70_07_03_est_inf_idents', 'Test 70.7.3: Informal EST Ident Errors', 'Test 70.7.3');
END $$;
INSERT INTO public.import_70_07_03_est_inf_idents_upload(tax_ident, name, valid_from, valid_to, primary_activity_category_code) VALUES
('LU7071_TAX','ESTINF CrossType LU','2023-01-01','2023-12-31','01.110'), -- Error: cross-type conflict (tax_ident used by LU1)
('EST707F_TAX','ESTINF CrossType FormalEST','2023-01-01','2023-12-31','01.110'); -- Error: cross-type conflict (tax_ident used by EST_FORMAL)
CALL worker.process_tasks(p_queue => 'import');
\echo "Data table for import_70_07_03_est_inf_idents (expect external_idents errors):"
SELECT row_id, name_raw as name, state, action, operation, errors, invalid_codes, merge_status, establishment_id FROM public.import_70_07_03_est_inf_idents_data ORDER BY row_id;

ROLLBACK TO scenario_70_7_external_idents_errors;


-- Scenario 70.8: analyse_link_establishment_to_legal_unit Errors
SAVEPOINT scenario_70_8_link_est_lu_errors;
\echo "Scenario 70.8: analyse_link_establishment_to_legal_unit Errors (Mode 'establishment_formal')"
DO $$
DECLARE
    v_definition_id INT; v_definition_slug TEXT := 'establishment_for_lu_source_dates';
    rec RECORD;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;

    RAISE NOTICE 'Diagnostic for Scenario 70.8: Expected source input columns for definition "%" (ID: %) like "legal_unit_%%":', v_definition_slug, v_definition_id;
    FOR rec IN
        SELECT dc.column_name, s.code AS step_code
        FROM public.import_data_column dc
        JOIN public.import_step s ON dc.step_id = s.id
        JOIN public.import_definition_step ds ON ds.step_id = s.id
        WHERE ds.definition_id = v_definition_id
          AND dc.purpose = 'source_input'
          AND dc.column_name ILIKE 'legal_unit_%'
        ORDER BY s.priority, dc.column_name
    LOOP
        RAISE NOTICE '  -> Found source input data column: % (for step: %)', rec.column_name, rec.step_code;
    END LOOP;
    IF NOT FOUND THEN
        RAISE NOTICE '  -> No source input data columns found matching "legal_unit_%%" for definition "%".', v_definition_slug;
    END IF;

    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_70_08_link_est_lu', 'Test 70.8: Link EST to LU Errors', 'Test 70.8');
END $$;
-- Setup: LU1 (tax_ident='LU7071_TAX', stat_ident='LU7071_STAT'), LU2 (stat_ident='LU7072_STAT') from 70.7 setup are available.
-- The diagnostic RAISE NOTICE above should confirm that legal_unit_tax_ident and legal_unit_stat_ident are expected source columns.
INSERT INTO public.import_70_08_link_est_lu_upload(tax_ident, name, valid_from, valid_to, primary_activity_category_code, legal_unit_tax_ident, legal_unit_stat_ident) VALUES
('E7081', 'EST No LUIdent', '2023-01-01', '2023-12-31', '01.110', NULL, NULL), -- Error: missing_identifier
('E7082', 'EST LU NotFound', '2023-01-01', '2023-12-31', '01.110', 'LU_NONEXISTENT_TAX', NULL), -- Error: not_found
('E7083', 'EST LU Inconsistent', '2023-01-01', '2023-12-31', '01.110', 'LU7071_TAX', 'LU7072_STAT'); -- Error: inconsistent_legal_unit
CALL worker.process_tasks(p_queue => 'import');
\echo "Data table for import_70_08_link_est_lu (expect link_establishment_to_legal_unit errors):"
SELECT row_id, name_raw as name, state, action, errors, invalid_codes, merge_status, legal_unit_id FROM public.import_70_08_link_est_lu_data ORDER BY row_id;
ROLLBACK TO scenario_70_8_link_est_lu_errors;


-- Scenario 70.9: Job Creation Validation Errors (Time Context & Default Dates)
SAVEPOINT scenario_70_9_job_creation_errors;
\echo "Scenario 70.9: Job Creation Validation Errors (Time Context & Default Dates)"
DO $$
DECLARE
    v_def_context_id INT;
    v_def_source_id INT;
BEGIN
    SELECT id INTO v_def_context_id FROM public.import_definition WHERE slug = 'legal_unit_job_provided';
    IF v_def_context_id IS NULL THEN RAISE EXCEPTION 'Setup for Test 70.9 FAILED: Definition "legal_unit_job_provided" not found.'; END IF;

    SELECT id INTO v_def_source_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    IF v_def_source_id IS NULL THEN RAISE EXCEPTION 'Setup for Test 70.9 FAILED: Definition "legal_unit_source_dates" not found.'; END IF;

    -- Test 70.9.1: Create job for 'time_context' definition WITHOUT providing time_context_ident (should fail)
    BEGIN
        INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
        VALUES (v_def_context_id, 'import_70_09_01_ctx_missing_ident', 'Test 70.9.1: Missing time_context_ident', 'Test 70.9.1');
        RAISE EXCEPTION 'Test 70.9.1 FAILED: Expected INSERT to fail due to missing time_context_ident.';
    EXCEPTION
        WHEN raise_exception THEN
            RAISE NOTICE 'Test 70.9.1 PASSED: Correctly failed to create job for time_context definition without time_context_ident. SQLERRM: %', SQLERRM;
    END;

    -- Test 70.9.2: Create job for 'time_context' definition WITH both time_context_ident AND default_valid_from (should fail)
    BEGIN
        INSERT INTO public.import_job (definition_id, slug, description, edit_comment, time_context_ident, default_valid_from)
        VALUES (v_def_context_id, 'import_70_09_02_ctx_conflict_from', 'Test 70.9.2: time_context_ident conflicts with default_valid_from', 'Test 70.9.2', 'r_year_curr', '2023-01-01');
        RAISE EXCEPTION 'Test 70.9.2 FAILED: Expected INSERT to fail due to conflict between time_context_ident and default_valid_from.';
    EXCEPTION
        WHEN raise_exception THEN
            RAISE NOTICE 'Test 70.9.2 PASSED: Correctly failed to create job with conflicting time_context_ident and default_valid_from. SQLERRM: %', SQLERRM;
    END;

    -- Test 70.9.3: Create job for 'source_columns' definition WITH time_context_ident (should fail)
    BEGIN
        INSERT INTO public.import_job (definition_id, slug, description, edit_comment, time_context_ident)
        VALUES (v_def_source_id, 'import_70_09_03_source_conflict_ctx', 'Test 70.9.3: time_context_ident with source_columns definition', 'Test 70.9.3', 'r_year_curr');
        RAISE EXCEPTION 'Test 70.9.3 FAILED: Expected INSERT to fail due to providing time_context_ident for a source_columns definition.';
    EXCEPTION
        WHEN raise_exception THEN
            RAISE NOTICE 'Test 70.9.3 PASSED: Correctly failed to create job with conflicting time_context_ident for source_columns definition. SQLERRM: %', SQLERRM;
    END;

    -- Test 70.9.4: Job for 'source_columns' definition with default_valid_from/to (should fail)
    BEGIN
        INSERT INTO public.import_job (definition_id, slug, description, edit_comment, default_valid_from, default_valid_to)
        VALUES (v_def_source_id, 'import_70_09_04_job_inv_period', 'Test 70.9.4: Job with default_valid_from/to for source_columns def', 'Test 70.9.4', '2024-01-01', '2023-12-31');
        RAISE EXCEPTION 'Test 70.9.4 FAILED: Expected INSERT to fail due to providing default dates for a source_columns definition.';
    EXCEPTION
        WHEN raise_exception THEN -- The trigger should raise an exception
            RAISE NOTICE 'Test 70.9.4 PASSED: Correctly failed to create job with default dates for a source_columns definition. SQLERRM: %', SQLERRM;
        WHEN others THEN
             RAISE NOTICE 'Test 70.9.4 FAILED: Expected raise_exception but got different error. SQLERRM: %', SQLERRM;
             RAISE; -- Re-raise other unexpected errors
    END;

    -- Test 70.9.5: Job for 'source_columns' definition with default_valid_from/to (should fail)
    BEGIN
        INSERT INTO public.import_job (definition_id, slug, description, edit_comment, default_valid_from, default_valid_to)
        VALUES (v_def_source_id, 'import_70_09_05_job_from_null_to', 'Test 70.9.5: Job with default_valid_from for source_columns def', 'Test 70.9.5', '2023-01-01', NULL);
        RAISE EXCEPTION 'Test 70.9.5 FAILED: Expected INSERT to fail due to providing default dates for a source_columns definition.';
    EXCEPTION
        WHEN raise_exception THEN -- The trigger should raise an exception
            RAISE NOTICE 'Test 70.9.5 PASSED: Correctly failed to create job with default dates for a source_columns definition. SQLERRM: %', SQLERRM;
        WHEN others THEN
            RAISE NOTICE 'Test 70.9.5 FAILED: Expected raise_exception but got different error. SQLERRM: %', SQLERRM;
            RAISE;
    END;

    -- Test 70.9.6: Job for 'source_columns' definition with default_valid_from/to (should fail)
    BEGIN
        INSERT INTO public.import_job (definition_id, slug, description, edit_comment, default_valid_from, default_valid_to)
        VALUES (v_def_source_id, 'import_70_09_06_job_null_from_to', 'Test 70.9.6: Job with default_valid_to for source_columns def', 'Test 70.9.6', NULL, '2023-12-31');
        RAISE EXCEPTION 'Test 70.9.6 FAILED: Expected INSERT to fail due to providing default dates for a source_columns definition.';
    EXCEPTION
        WHEN raise_exception THEN -- The trigger should raise an exception
            RAISE NOTICE 'Test 70.9.6 PASSED: Correctly failed to create job with default dates for a source_columns definition. SQLERRM: %', SQLERRM;
        WHEN others THEN
            RAISE NOTICE 'Test 70.9.6 FAILED: Expected raise_exception but got different error. SQLERRM: %', SQLERRM;
            RAISE;
    END;

END $$;

-- Since the jobs in 70.9 are expected to fail at creation, there will be no _data tables to query.
-- The RAISE NOTICE statements within the EXCEPTION blocks will serve as verification.
\echo "Scenario 70.9: Verification is done via RAISE NOTICE in EXCEPTION blocks above."

ROLLBACK TO scenario_70_9_job_creation_errors;


\echo "Final counts after all test blocks for Test 70 (should be same as initial due to rollbacks)"
SELECT
    (SELECT COUNT(*) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(*) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(*) FROM public.enterprise) AS enterprise_count;

ROLLBACK TO main_test_70_start;
\echo "Test 70 completed and rolled back to main start."

ROLLBACK; -- Final rollback for the entire transaction

BEGIN;

\i test/setup.sql

\echo "Test 342: Hierarchical External Identifiers - Import System Integration"
\echo "Testing hierarchical identifier import: column generation, validation, analysis, and processing"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

SELECT acs.code FROM public.settings AS s JOIN activity_category_standard AS acs ON s.activity_category_standard_id = acs.id;

SAVEPOINT before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) FROM public.enterprise) AS enterprise_count;

-- ============================================================================
-- Test 342.1: Setup - Create Hierarchical Identifier Type and Verify Column Generation
-- ============================================================================
\echo "=============================================================="
\echo "Test 342.1: Hierarchical Identifier Type Setup and Column Generation"
\echo "=============================================================="

-- Setup: Create a hierarchical identifier type (Uganda-style: region.district.seq)
\echo "Creating hierarchical identifier type 'surveyor_ident' with labels 'region.district.seq'"
INSERT INTO public.external_ident_type (code, name, shape, labels, description, priority, enabled)
VALUES ('surveyor_ident', 'Surveyor Identifier', 'hierarchical', 'region.district.seq',
        'Region/District/Sequence hierarchical composite key', 50, true);

-- Verify the type was created correctly
\echo "Verifying hierarchical identifier type:"
SELECT eit.code, eit.shape, eit.labels, eit.priority
FROM public.external_ident_type eit
WHERE eit.code = 'surveyor_ident';

-- Verify data columns were generated for external_idents step
\echo "Verifying import data columns were generated:"
SELECT idc.column_name, idc.column_type, idc.purpose, idc.priority, idc.is_uniquely_identifying
FROM public.import_data_column idc
JOIN public.import_step ist ON ist.id = idc.step_id
WHERE ist.code = 'external_idents'
  AND idc.column_name LIKE 'surveyor_ident%'
ORDER BY idc.priority;

-- Verify we have the expected columns:
-- surveyor_ident_region_raw (source_input, TEXT)
-- surveyor_ident_district_raw (source_input, TEXT)
-- surveyor_ident_seq_raw (source_input, TEXT)
-- surveyor_ident_path (internal, LTREE)
\echo "Expected 4 columns: surveyor_ident_region_raw, surveyor_ident_district_raw, surveyor_ident_seq_raw, surveyor_ident_path"
SELECT COUNT(*) AS column_count FROM public.import_data_column idc
JOIN public.import_step ist ON ist.id = idc.step_id
WHERE ist.code = 'external_idents'
  AND idc.column_name LIKE 'surveyor_ident%';

-- ============================================================================
-- Test 342.2: Happy Path - Import Legal Unit with Hierarchical Identifier
-- ============================================================================
\echo "=============================================================="
\echo "Test 342.2: Happy Path - Import LU with Hierarchical Identifier"
\echo "=============================================================="

-- Note: Lifecycle callbacks are automatically triggered when we insert into external_ident_type
-- The columns are already generated from Test 342.1

-- Create import job
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_342_02_hier_lu',
    'Test 342-02: LU with Hierarchical Ident',
    'Importing LU with surveyor hierarchical identifier.',
    'Test 342';

-- Verify the upload table has the hierarchical columns
\echo "Verifying upload table has hierarchical columns:"
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'import_342_02_hier_lu_upload'
  AND column_name LIKE 'surveyor_ident%'
ORDER BY ordinal_position;

-- Insert data with all hierarchical components provided
-- Note: Upload table uses source column names (without _raw suffix)
INSERT INTO public.import_342_02_hier_lu_upload(
    valid_from, valid_to, tax_ident, name, birth_date, death_date,
    physical_address_part1, physical_postcode, physical_postplace,
    physical_region_code, physical_country_iso_2,
    primary_activity_category_code, secondary_activity_category_code,
    sector_code, legal_form_code,
    surveyor_ident_region, surveyor_ident_district, surveyor_ident_seq
) VALUES
('2020-01-01','2020-12-31','342020001','LU with Surveyor ID','2020-01-01',NULL,
 'Main St 1','1234','Oslo','0301','NO','01.110',NULL,'2100','AS',
 'NORTH', 'KAMPALA', '001');

\echo "Run worker processing for import jobs"
CALL worker.process_tasks(p_queue => 'import');

\echo "Import job status for 342_02_hier_lu:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details
FROM public.import_job WHERE slug = 'import_342_02_hier_lu';

\echo "Data table row status for import_342_02_hier_lu:"
SELECT row_id, state, errors, merge_status, action, operation,
       surveyor_ident_region_raw, surveyor_ident_district_raw, surveyor_ident_seq_raw,
       surveyor_ident_path
FROM public.import_342_02_hier_lu_data;

\echo "Verification: Legal Units created:"
SELECT
    lu.name,
    ei_tax.ident AS tax_ident,
    lu.valid_from, lu.valid_to
FROM public.legal_unit lu
JOIN public.external_ident ei_tax ON ei_tax.legal_unit_id = lu.id
JOIN public.external_ident_type eit_tax ON eit_tax.id = ei_tax.type_id AND eit_tax.code = 'tax_ident'
WHERE ei_tax.ident = '342020001';

\echo "Verification: Hierarchical External Identifiers created:"
SELECT
    eit.code AS type_code,
    eit.shape,
    ei.idents,
    ei.labels,
    nlevel(ei.idents) AS depth,
    lu.name AS legal_unit_name
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id
JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id
WHERE eit.code = 'surveyor_ident';

-- ============================================================================
-- Test 342.3: All-or-Nothing Validation - Partial Components Should Error
-- ============================================================================
\echo "=============================================================="
\echo "Test 342.3: All-or-Nothing Validation - Partial Components Error"
\echo "=============================================================="

-- Create import job for partial test
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_342_03_partial',
    'Test 342-03: Partial Hierarchical Ident',
    'Testing partial hierarchical identifier (should error).',
    'Test 342';

-- Insert data with PARTIAL hierarchical components (missing seq)
INSERT INTO public.import_342_03_partial_upload(
    valid_from, valid_to, tax_ident, name, birth_date, death_date,
    physical_address_part1, physical_postcode, physical_postplace,
    physical_region_code, physical_country_iso_2,
    primary_activity_category_code, secondary_activity_category_code,
    sector_code, legal_form_code,
    surveyor_ident_region, surveyor_ident_district, surveyor_ident_seq
) VALUES
('2020-01-01','2020-12-31','342030001','LU Partial Hier','2020-01-01',NULL,
 'Main St 1','1234','Oslo','0301','NO','01.110',NULL,'2100','AS',
 'NORTH', 'KAMPALA', NULL);  -- seq is NULL (partial)

CALL worker.process_tasks(p_queue => 'import');

\echo "Import job status for 342_03_partial (expect error due to partial hierarchical):"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details
FROM public.import_job WHERE slug = 'import_342_03_partial';

\echo "Data table row status - should show error about missing components:"
SELECT row_id, state, errors, action,
       surveyor_ident_region_raw, surveyor_ident_district_raw, surveyor_ident_seq_raw,
       surveyor_ident_path
FROM public.import_342_03_partial_data;

\echo "Verify no legal unit was created with tax_ident 342030001:"
SELECT COUNT(*) AS lu_count FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident = '342030001';

-- ============================================================================
-- Test 342.4: Invalid ltree Characters - Should Error
-- ============================================================================
\echo "=============================================================="
\echo "Test 342.4: Invalid ltree Characters - Should Error"
\echo "=============================================================="

-- Create import job for invalid chars test
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_342_04_invalid',
    'Test 342-04: Invalid ltree chars',
    'Testing invalid ltree characters (should error).',
    'Test 342';

-- Insert data with invalid characters in hierarchical component (dots are invalid)
INSERT INTO public.import_342_04_invalid_upload(
    valid_from, valid_to, tax_ident, name, birth_date, death_date,
    physical_address_part1, physical_postcode, physical_postplace,
    physical_region_code, physical_country_iso_2,
    primary_activity_category_code, secondary_activity_category_code,
    sector_code, legal_form_code,
    surveyor_ident_region, surveyor_ident_district, surveyor_ident_seq
) VALUES
('2020-01-01','2020-12-31','342040001','LU Invalid Chars','2020-01-01',NULL,
 'Main St 1','1234','Oslo','0301','NO','01.110',NULL,'2100','AS',
 'NORTH', 'KAM.PALA', '001');  -- district has a dot (invalid for ltree label)

CALL worker.process_tasks(p_queue => 'import');

\echo "Import job status for 342_04_invalid (expect error due to invalid chars):"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details
FROM public.import_job WHERE slug = 'import_342_04_invalid';

\echo "Data table row status - should show error about invalid characters:"
SELECT row_id, state, errors, action,
       surveyor_ident_region_raw, surveyor_ident_district_raw, surveyor_ident_seq_raw,
       surveyor_ident_path
FROM public.import_342_04_invalid_data;

-- ============================================================================
-- Test 342.5: Mixed Import - Regular + Hierarchical Identifiers Together
-- ============================================================================
\echo "=============================================================="
\echo "Test 342.5: Mixed Import - Regular + Hierarchical Identifiers"
\echo "=============================================================="

-- Create import job for mixed test
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_342_05_mixed',
    'Test 342-05: Mixed Regular and Hierarchical',
    'Importing with both tax_ident (regular) and surveyor_ident (hierarchical).',
    'Test 342';

-- Insert multiple rows with both regular and hierarchical identifiers
INSERT INTO public.import_342_05_mixed_upload(
    valid_from, valid_to, tax_ident, name, birth_date, death_date,
    physical_address_part1, physical_postcode, physical_postplace,
    physical_region_code, physical_country_iso_2,
    primary_activity_category_code, secondary_activity_category_code,
    sector_code, legal_form_code,
    surveyor_ident_region, surveyor_ident_district, surveyor_ident_seq
) VALUES
-- LU 1: Both regular and hierarchical
('2020-01-01','2020-12-31','342050001','LU Mixed One','2020-01-01',NULL,
 'Main St 1','1234','Oslo','0301','NO','01.110',NULL,'2100','AS',
 'EAST', 'JINJA', '001'),
-- LU 2: Only regular (hierarchical NULL)
('2020-01-01','2020-12-31','342050002','LU Regular Only','2020-01-01',NULL,
 'Main St 2','1234','Oslo','0301','NO','02.200',NULL,'2100','AS',
 NULL, NULL, NULL),
-- LU 3: Both regular and hierarchical (different region)
('2020-01-01','2020-12-31','342050003','LU Mixed Three','2020-01-01',NULL,
 'Main St 3','1234','Oslo','0301','NO','03.100',NULL,'2100','AS',
 'WEST', 'MBARARA', '001');

CALL worker.process_tasks(p_queue => 'import');

\echo "Import job status for 342_05_mixed:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details
FROM public.import_job WHERE slug = 'import_342_05_mixed';

\echo "Data table row status:"
SELECT row_id, state, errors, action, operation, tax_ident_raw,
       surveyor_ident_region_raw, surveyor_ident_district_raw, surveyor_ident_seq_raw,
       surveyor_ident_path
FROM public.import_342_05_mixed_data
ORDER BY row_id;

\echo "Verification: Legal Units created:"
SELECT
    lu.name,
    ei_tax.ident AS tax_ident,
    lu.valid_from, lu.valid_to
FROM public.legal_unit lu
JOIN public.external_ident ei_tax ON ei_tax.legal_unit_id = lu.id
JOIN public.external_ident_type eit_tax ON eit_tax.id = ei_tax.type_id AND eit_tax.code = 'tax_ident'
WHERE ei_tax.ident IN ('342050001', '342050002', '342050003')
ORDER BY ei_tax.ident;

\echo "Verification: All External Identifiers (both regular and hierarchical):"
SELECT
    eit.code AS type_code,
    eit.shape,
    COALESCE(ei.ident, ei.idents::text) AS identifier,
    lu.name AS legal_unit_name
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id
JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id
WHERE ei.legal_unit_id IN (
    SELECT lu2.id FROM public.legal_unit lu2
    JOIN public.external_ident ei2 ON ei2.legal_unit_id = lu2.id
    JOIN public.external_ident_type eit2 ON eit2.id = ei2.type_id AND eit2.code = 'tax_ident'
    WHERE ei2.ident IN ('342050001', '342050002', '342050003')
)
ORDER BY lu.name, eit.code;

-- ============================================================================
-- Test 342.6: Duplicate Detection for Hierarchical Identifiers
-- ============================================================================
\echo "=============================================================="
\echo "Test 342.6: Duplicate Detection for Hierarchical Identifiers"
\echo "=============================================================="

-- Create import job for duplicate test
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_342_06_dupes',
    'Test 342-06: Duplicate Hierarchical Idents',
    'Testing duplicate hierarchical identifier detection.',
    'Test 342';

-- Insert two rows with the SAME hierarchical identifier (should error - duplicates)
INSERT INTO public.import_342_06_dupes_upload(
    valid_from, valid_to, tax_ident, name, birth_date, death_date,
    physical_address_part1, physical_postcode, physical_postplace,
    physical_region_code, physical_country_iso_2,
    primary_activity_category_code, secondary_activity_category_code,
    sector_code, legal_form_code,
    surveyor_ident_region, surveyor_ident_district, surveyor_ident_seq
) VALUES
-- LU 1: First unit with surveyor ID CENTRAL.OSLO.099
('2020-01-01','2020-12-31','342060001','LU First Duplicate','2020-01-01',NULL,
 'Main St 1','1234','Oslo','0301','NO','01.110',NULL,'2100','AS',
 'CENTRAL', 'OSLO', '099'),
-- LU 2: DIFFERENT tax_ident but SAME surveyor ID - should be detected as duplicate
('2020-01-01','2020-12-31','342060002','LU Second Duplicate','2020-01-01',NULL,
 'Main St 2','1234','Oslo','0301','NO','02.200',NULL,'2100','AS',
 'CENTRAL', 'OSLO', '099');  -- Same hierarchical ID as above!

CALL worker.process_tasks(p_queue => 'import');

\echo "Import job status for 342_06_dupes (expect errors for duplicate hierarchical):"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details
FROM public.import_job WHERE slug = 'import_342_06_dupes';

\echo "Data table row status - both rows should show duplicate error:"
SELECT row_id, state, errors, action,
       tax_ident_raw,
       surveyor_ident_region_raw, surveyor_ident_district_raw, surveyor_ident_seq_raw,
       surveyor_ident_path
FROM public.import_342_06_dupes_data
ORDER BY row_id;

-- ============================================================================
-- Test 342.7: Two-Level Hierarchical Identifier (region.district only)
-- ============================================================================
\echo "=============================================================="
\echo "Test 342.7: Two-Level Hierarchical Identifier"
\echo "=============================================================="

-- Create a simpler 2-level hierarchical identifier type
INSERT INTO public.external_ident_type (code, name, shape, labels, description, priority, enabled)
VALUES ('region_code', 'Regional Code', 'hierarchical', 'region.district',
        'Two-level regional code', 51, true);

-- Note: Lifecycle callbacks are automatically triggered when we insert into external_ident_type

\echo "Verifying 2-level hierarchical columns were generated:"
SELECT idc.column_name, idc.column_type, idc.purpose, idc.priority
FROM public.import_data_column idc
JOIN public.import_step ist ON ist.id = idc.step_id
WHERE ist.code = 'external_idents'
  AND idc.column_name LIKE 'region_code%'
ORDER BY idc.priority;

-- Create import job for 2-level test
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_342_07_twolevel',
    'Test 342-07: Two-Level Hierarchical',
    'Testing 2-level hierarchical identifier.',
    'Test 342';

-- Insert data with 2-level hierarchical identifier
INSERT INTO public.import_342_07_twolevel_upload(
    valid_from, valid_to, tax_ident, name, birth_date, death_date,
    physical_address_part1, physical_postcode, physical_postplace,
    physical_region_code, physical_country_iso_2,
    primary_activity_category_code, secondary_activity_category_code,
    sector_code, legal_form_code,
    region_code_region, region_code_district
) VALUES
('2020-01-01','2020-12-31','342070001','LU Two Level','2020-01-01',NULL,
 'Main St 1','1234','Oslo','0301','NO','01.110',NULL,'2100','AS',
 'SOUTHERN', 'BERGEN');

CALL worker.process_tasks(p_queue => 'import');

\echo "Import job status for 342_07_twolevel:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details
FROM public.import_job WHERE slug = 'import_342_07_twolevel';

\echo "Data table row status:"
SELECT row_id, state, errors, action, operation,
       region_code_region_raw, region_code_district_raw, region_code_path
FROM public.import_342_07_twolevel_data;

\echo "Verification: 2-level hierarchical identifier created:"
SELECT
    eit.code AS type_code,
    ei.idents,
    nlevel(ei.idents) AS depth,
    lu.name AS legal_unit_name
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id
JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id
WHERE eit.code = 'region_code';

-- ============================================================================
-- Final Summary
-- ============================================================================
\echo "=============================================================="
\echo "Final Summary - Unit counts after all tests"
\echo "=============================================================="

SELECT
    (SELECT COUNT(DISTINCT id) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) FROM public.enterprise) AS enterprise_count;

\echo "All hierarchical external identifiers created:"
SELECT
    eit.code AS type_code,
    ei.idents,
    nlevel(ei.idents) AS depth,
    CASE 
        WHEN ei.legal_unit_id IS NOT NULL THEN 'legal_unit'
        WHEN ei.establishment_id IS NOT NULL THEN 'establishment'
        ELSE 'unknown'
    END AS unit_type
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id
WHERE eit.shape = 'hierarchical'
ORDER BY eit.code, ei.idents;

ROLLBACK;

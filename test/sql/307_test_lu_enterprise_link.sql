-- Test 72: Enterprise Linking and Temporal Slicing in Batch Imports
-- Implements scenarios from fix-lu-en-link.md

BEGIN;

\i test/setup.sql

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

\echo 'Test 72: Enterprise Linking Scenarios'

-- Common setup: Get Import Definition ID for Legal Units
\set import_definition_slug '''legal_unit_source_dates'''
SELECT id AS import_def_id FROM public.import_definition WHERE slug = :import_definition_slug \gset
\if :{?import_def_id}
\else
    \warn 'FAIL: Could not find import definition with slug :' :import_definition_slug '. This test requires it to exist.'
    \quit
\endif
\echo 'Using import definition: ' :import_definition_slug

-- Define common constants
\set user_email_literal '''test.admin@statbus.org'''
\set default_edit_comment '''Test 72 SC'''

-- Scenario 1 (SC1): Single LU with Multiple Consecutive Temporal Segments
\echo 'SC1: Single LU with Multiple Consecutive Temporal Segments'
SAVEPOINT scenario_1_start;

-- SC1 Constants
\set sc1_lu_tax_ident '''SC1LU001'''
\set sc1_job_slug 'test72_sc1_lu_segments'
\set sc1_p1_from '''2023-01-01'''
\set sc1_p1_to   '''2023-03-31'''
\set sc1_p2_from '''2023-04-01'''
\set sc1_p2_to   '''2023-06-30'''
\set sc1_p3_from '''2023-07-01'''
\set sc1_p3_to   '''2023-09-30'''

-- SC1 Create Job
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc1_job_slug', 'SC1 LU Segments', 'Test 72 SC1', :'default_edit_comment');

-- Removed \gset for sc1_upload_table and sc1_data_table as they will be hardcoded

-- SC1 Insert data into upload table
SELECT format($$
    INSERT INTO public.test72_sc1_lu_segments_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC1 Name P1/P2', %L, %L, '2300', 'AS', 'mi', '2023-01-01', 'Addr SC1 P1/P2', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC1 Name P1/P2', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Addr SC1 P1/P2', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC1 Name P3',    %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Addr SC1 P3',   '1001', 'Oslo', '0301', 'NO', '01.120');
$$, -- No table variable needed here
    :'sc1_lu_tax_ident', :'sc1_p1_from', :'sc1_p1_to',
    :'sc1_lu_tax_ident', :'sc1_p2_from', :'sc1_p2_to',
    :'sc1_lu_tax_ident', :'sc1_p3_from', :'sc1_p3_to'
) \gexec

-- SC1 Simulate import processing steps
CALL worker.process_tasks(p_queue => 'import');

-- SC1 Verifications
\echo 'SC1: Verifying _data table contents'
SELECT
    row_id,
    tax_ident,
    name,
    valid_from,
    valid_to,
    action,
    -- operation, -- Column does not exist
    founding_row_id,
    CASE WHEN legal_unit_id IS NOT NULL THEN 'LU_SET' ELSE 'LU_NULL' END AS data_lu_marker,
    CASE WHEN enterprise_id IS NOT NULL THEN 'EN_SET' ELSE 'EN_NULL' END AS data_en_marker,
    -- Check all rows have same legal_unit_id
    CASE WHEN legal_unit_id = FIRST_VALUE(legal_unit_id) OVER (ORDER BY row_id) THEN 'SAME_LU' ELSE 'DIFF_LU' END AS lu_consistency,
    -- Check all rows have same enterprise_id
    CASE WHEN enterprise_id = FIRST_VALUE(enterprise_id) OVER (ORDER BY row_id) THEN 'SAME_EN' ELSE 'DIFF_EN' END AS en_consistency,
    error,
    invalid_codes,
    state
FROM public.test72_sc1_lu_segments_data -- Hardcoded based on sc1_job_slug
ORDER BY row_id;

\echo 'SC1: Verifying public.legal_unit table (expect 3 slices)'
SELECT
    COUNT(*) OVER() AS total_slices,
    ROW_NUMBER() OVER (ORDER BY lu.valid_from) AS slice_num,
    lu.name,
    lu.valid_from,
    lu.valid_to,
    lu.valid_after,
    CASE WHEN lu.enterprise_id IS NOT NULL THEN 'EN_SET' ELSE 'EN_NULL' END AS en_marker,
    lu.primary_for_enterprise,
    (SELECT code FROM public.sector s WHERE s.id = lu.sector_id) as sector_code,
    (SELECT COUNT(*) FROM public.location loc WHERE loc.legal_unit_id = lu.id AND lu.valid_from <= loc.valid_to AND lu.valid_to >= loc.valid_from) as location_count_for_slice,
    (SELECT COUNT(*) FROM public.activity act WHERE act.legal_unit_id = lu.id AND lu.valid_from <= act.valid_to AND lu.valid_to >= act.valid_from) as activity_count_for_slice,
    -- Check all slices have same enterprise_id
    CASE WHEN MIN(lu.enterprise_id) OVER() = MAX(lu.enterprise_id) OVER() THEN 'SAME_EN_ALL_SLICES' ELSE 'DIFF_EN_ACROSS_SLICES' END AS en_consistency
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = :'sc1_lu_tax_ident'
ORDER BY lu.valid_after, lu.valid_from;

\echo 'SC1: Verifying public.enterprise table (expect 1 new enterprise)'
SELECT
    COUNT(*) AS enterprise_count,
    e.short_name,
    (SELECT COUNT(DISTINCT lu_check.id) FROM public.legal_unit lu_check WHERE lu_check.enterprise_id = e.id AND lu_check.primary_for_enterprise = TRUE) as primary_lu_count
FROM public.enterprise e
WHERE e.id IN (SELECT lu.enterprise_id FROM public.legal_unit lu JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident') WHERE ei.ident = :'sc1_lu_tax_ident')
GROUP BY e.id, e.short_name;

-- Run analytics to populate statistical_unit view
CALL worker.process_tasks(p_queue => 'analytics');

\echo 'SC1: Verifying public.statistical_unit view (expect 3 slices)'
SELECT
    su.name,
    su.external_idents->>'tax_ident' AS tax_ident,
    su.valid_from,
    su.valid_to,
    su.sector_code,
    su.primary_activity_category_code,
    su.physical_address_part1
FROM public.statistical_unit su
WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = :'sc1_lu_tax_ident'
ORDER BY su.valid_from;

ROLLBACK TO scenario_1_start;
\echo 'SC1: Rolled back.'

-- Scenario 2 (SC2): Two Distinct LUs in Same Batch
\echo 'SC2: Two Distinct LUs in Same Batch (should create two separate enterprises)'
SAVEPOINT scenario_2_start;

-- SC2 Constants
\set sc2_lu1_tax_ident '''SC2LU001'''
\set sc2_lu2_tax_ident '''SC2LU002'''
\set sc2_job_slug 'test72_sc2_two_lus'
\set sc2_valid_from '''2023-01-01'''
\set sc2_valid_to   '''2023-12-31'''

-- SC2 Create Job
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc2_job_slug', 'SC2 Two LUs', 'Test 72 SC2', :'default_edit_comment');

-- Removed \gset for sc2_upload_table and sc2_data_table

-- SC2 Insert data into upload table - two distinct LUs
SELECT format($$
    INSERT INTO public.test72_sc2_two_lus_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC2 First Company',  %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'First St 1',  '1000', 'Oslo',   '0301', 'NO', '01.110'),
    (%L, 'LU SC2 Second Company', %L, %L, '3200', 'AS', 'mi', '2023-01-01', 'Second St 2', '5000', 'Bergen', '4601', 'NO', '02.200');
$$, -- No table variable needed here
    :'sc2_lu1_tax_ident', :'sc2_valid_from', :'sc2_valid_to',
    :'sc2_lu2_tax_ident', :'sc2_valid_from', :'sc2_valid_to'
) \gexec

-- SC2 Simulate import processing
CALL worker.process_tasks(p_queue => 'import');

-- SC2 Verifications
\echo 'SC2: Verifying _data table contents'
SELECT
    row_id,
    tax_ident,
    name,
    action,
    -- operation, -- Column does not exist
    CASE WHEN legal_unit_id IS NOT NULL THEN 'LU_SET' ELSE 'LU_NULL' END AS data_lu_marker,
    CASE WHEN enterprise_id IS NOT NULL THEN 'EN_SET' ELSE 'EN_NULL' END AS data_en_marker,
    -- Check that each row has different legal_unit_id
    CASE WHEN COUNT(*) OVER() = COUNT(*) OVER(PARTITION BY legal_unit_id) THEN 'DUPLICATE_LUS' ELSE 'UNIQUE_LUS' END AS lu_uniqueness,
    -- Check that each row has different enterprise_id
    CASE WHEN COUNT(*) OVER() = COUNT(*) OVER(PARTITION BY enterprise_id) THEN 'DUPLICATE_ENS' ELSE 'UNIQUE_ENS' END AS en_uniqueness,
    error,
    invalid_codes,
    state
FROM public.test72_sc2_two_lus_data -- Hardcoded based on sc2_job_slug
ORDER BY row_id;

\echo 'SC2: Verifying public.legal_unit table (expect 2 distinct LUs)'
SELECT
    COUNT(*) OVER() AS total_lus,
    lu.name,
    ei.ident AS tax_ident,
    CASE WHEN lu.enterprise_id IS NOT NULL THEN 'EN_SET' ELSE 'EN_NULL' END AS en_marker,
    lu.primary_for_enterprise,
    -- Check each LU has different enterprise_id
    CASE WHEN MIN(lu.enterprise_id) OVER() = MAX(lu.enterprise_id) OVER() AND COUNT(*) OVER() > 1 THEN 'SHARED_ENS' ELSE 'UNIQUE_ENS' END AS en_uniqueness
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident IN (:'sc2_lu1_tax_ident', :'sc2_lu2_tax_ident')
ORDER BY tax_ident;

\echo 'SC2: Verifying public.enterprise table (expect 2 distinct enterprises)'
SELECT
    COUNT(*) OVER() AS total_enterprises,
    ROW_NUMBER() OVER (ORDER BY (
        SELECT ident FROM (
            SELECT ei.ident, 1 as priority
            FROM public.legal_unit lu
            JOIN public.external_ident ei ON lu.id = ei.legal_unit_id
            JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
            WHERE lu.enterprise_id = e.id AND lu.primary_for_enterprise = TRUE
            UNION ALL
            SELECT ei.ident, 2 as priority
            FROM public.legal_unit lu
            JOIN public.external_ident ei ON lu.id = ei.legal_unit_id
            JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
            WHERE lu.enterprise_id = e.id
            UNION ALL
            SELECT ei.ident, 3 as priority
            FROM public.establishment est
            JOIN public.external_ident ei ON est.id = ei.establishment_id
            JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
            WHERE est.enterprise_id = e.id AND est.primary_for_enterprise = TRUE -- Establishments can also be primary for an enterprise
            UNION ALL
            SELECT ei.ident, 4 as priority
            FROM public.establishment est
            JOIN public.external_ident ei ON est.id = ei.establishment_id
            JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
            WHERE est.enterprise_id = e.id
        ) AS idents ORDER BY priority, ident LIMIT 1
    ) NULLS LAST, e.id) AS en_num,
    e.short_name,
    (SELECT COUNT(*) FROM public.legal_unit lu WHERE lu.enterprise_id = e.id) as total_lus,
    (SELECT string_agg(ei.ident, ', ' ORDER BY ei.ident) 
     FROM public.legal_unit lu 
     JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
     JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
     WHERE lu.enterprise_id = e.id) as linked_lu_tax_idents
FROM public.enterprise e
WHERE e.id IN (
    SELECT lu.enterprise_id 
    FROM public.legal_unit lu 
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
    JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
    WHERE ei.ident IN (:'sc2_lu1_tax_ident', :'sc2_lu2_tax_ident')
)
ORDER BY linked_lu_tax_idents;

\echo 'SC2: Critical Check - Are both LUs linked to the SAME enterprise? (Should be NO)'
SELECT 
    CASE 
        WHEN COUNT(DISTINCT lu.enterprise_id) = 1 THEN 'FAIL: Both LUs linked to same enterprise!'
        WHEN COUNT(DISTINCT lu.enterprise_id) = 2 THEN 'PASS: LUs linked to different enterprises'
        ELSE 'UNEXPECTED: Found ' || COUNT(DISTINCT lu.enterprise_id) || ' distinct enterprises'
    END as test_result,
    COUNT(DISTINCT lu.enterprise_id) as distinct_enterprise_count
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident IN (:'sc2_lu1_tax_ident', :'sc2_lu2_tax_ident');

ROLLBACK TO scenario_2_start;
\echo 'SC2: Rolled back.'

-- Scenario 3 (SC3): Multiple LUs and ESs with Multiple Segments
\echo 'SC3: Multiple LUs and ESs with Multiple Segments (Single Batch)'
SAVEPOINT scenario_3_start;

-- SC3 Constants
\set sc3_lu_a_tax_ident '''SC3LUA001'''
\set sc3_lu_b_tax_ident '''SC3LUB001'''
\set sc3_es_a1_tax_ident '''SC3ESA001'''
\set sc3_es_a2_tax_ident '''SC3ESA002'''
\set sc3_es_a3_tax_ident '''SC3ESA003'''
\set sc3_es_b1_tax_ident '''SC3ESB001'''
\set sc3_es_b2_tax_ident '''SC3ESB002'''
\set sc3_es_b3_tax_ident '''SC3ESB003'''
\set sc3_job_lu_slug 'test72_sc3_lus'
\set sc3_job_es_slug 'test72_sc3_ests'
\set sc3_p1_from '''2023-01-01'''
\set sc3_p1_to   '''2023-03-31'''
\set sc3_p2_from '''2023-04-01'''
\set sc3_p2_to   '''2023-06-30'''
\set sc3_p3_from '''2023-07-01'''
\set sc3_p3_to   '''2023-09-30'''

-- SC3 Create Jobs for LUs
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc3_job_lu_slug', 'SC3 LUs', 'Test 72 SC3 LUs', :'default_edit_comment');

-- Removed \gset for sc3_lu_upload_table and sc3_lu_data_table

-- SC3 Insert LU data - 2 LUs x 3 periods each = 6 rows
SELECT format($$
    INSERT INTO public.test72_sc3_lus_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    -- LU A periods
    (%L, 'LU SC3 Company A', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'A Street 1', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC3 Company A', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'A Street 1', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC3 Company A Changed', %L, %L, '2300', 'AS', 'mi', '2023-01-01', 'A Street 2', '1001', 'Oslo', '0301', 'NO', '01.120'),
    -- LU B periods
    (%L, 'LU SC3 Company B', %L, %L, '3100', 'AS', 'mi', '2023-01-01', 'B Avenue 1', '5000', 'Bergen', '4601', 'NO', '02.100'),
    (%L, 'LU SC3 Company B', %L, %L, '3100', 'AS', 'mi', '2023-01-01', 'B Avenue 1', '5000', 'Bergen', '4601', 'NO', '02.100'),
    (%L, 'LU SC3 Company B Modified', %L, %L, '3200', 'AS', 'mi', '2023-01-01', 'B Avenue 2', '5001', 'Bergen', '4601', 'NO', '02.200');
$$, -- No table variable needed here
    :'sc3_lu_a_tax_ident', :'sc3_p1_from', :'sc3_p1_to',
    :'sc3_lu_a_tax_ident', :'sc3_p2_from', :'sc3_p2_to',
    :'sc3_lu_a_tax_ident', :'sc3_p3_from', :'sc3_p3_to',
    :'sc3_lu_b_tax_ident', :'sc3_p1_from', :'sc3_p1_to',
    :'sc3_lu_b_tax_ident', :'sc3_p2_from', :'sc3_p2_to',
    :'sc3_lu_b_tax_ident', :'sc3_p3_from', :'sc3_p3_to'
) \gexec

-- Process LUs
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC3: Verifying _data table contents for LUs job (test72_sc3_lus)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
       CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc3_lus_data -- Hardcoded based on sc3_job_lu_slug
ORDER BY row_id;

-- Now create and process establishments
-- Get establishment import definition
\set es_import_definition_slug '''establishment_for_lu_source_dates'''
SELECT id AS es_import_def_id FROM public.import_definition WHERE slug = :es_import_definition_slug \gset
\if :{?es_import_def_id}
\else
    \warn 'FAIL: Could not find establishment import definition with slug :' :es_import_definition_slug
    \quit
\endif

-- SC3 Create Job for ESs
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:es_import_def_id, :'sc3_job_es_slug', 'SC3 ESs', 'Test 72 SC3 ESs', :'default_edit_comment');

-- Removed \gset for sc3_es_upload_table and sc3_es_data_table

-- SC3 Insert ES data - 6 ESs x 3 periods each = 18 rows
SELECT format($$
    INSERT INTO public.test72_sc3_ests_upload (tax_ident, name, valid_from, valid_to, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code, legal_unit_tax_ident) VALUES
    -- ES A1 periods
    (%L, 'ES SC3 A1 Shop', %L, %L, '2023-01-01', 'A1 Shop St 1', '1100', 'Oslo', '0301', 'NO', '46.48', %L),
    (%L, 'ES SC3 A1 Shop', %L, %L, '2023-01-01', 'A1 Shop St 1', '1100', 'Oslo', '0301', 'NO', '46.48', %L),
    (%L, 'ES SC3 A1 Shop Renamed', %L, %L, '2023-01-01', 'A1 Shop St 2', '1101', 'Oslo', '0301', 'NO', '47.190', %L),
    -- ES A2 periods
    (%L, 'ES SC3 A2 Office', %L, %L, '2023-01-01', 'A2 Office Rd 1', '1200', 'Oslo', '0301', 'NO', '68.100', %L),
    (%L, 'ES SC3 A2 Office', %L, %L, '2023-01-01', 'A2 Office Rd 1', '1200', 'Oslo', '0301', 'NO', '68.100', %L),
    (%L, 'ES SC3 A2 Office Moved', %L, %L, '2023-01-01', 'A2 Office Rd 2', '1201', 'Oslo', '0301', 'NO', '01.3', %L),
    -- ES A3 periods
    (%L, 'ES SC3 A3 Warehouse', %L, %L, '2023-01-01', 'A3 Storage 1', '1300', 'Oslo', '0301', 'NO', '52.100', %L),
    (%L, 'ES SC3 A3 Warehouse', %L, %L, '2023-01-01', 'A3 Storage 1', '1300', 'Oslo', '0301', 'NO', '52.100', %L),
    (%L, 'ES SC3 A3 Warehouse Exp', %L, %L, '2023-01-01', 'A3 Storage 2', '1301', 'Oslo', '0301', 'NO', '25.93', %L),
    -- ES B1 periods
    (%L, 'ES SC3 B1 Factory', %L, %L, '2023-01-01', 'B1 Factory 1', '5100', 'Bergen', '4601', 'NO', '10.110', %L),
    (%L, 'ES SC3 B1 Factory', %L, %L, '2023-01-01', 'B1 Factory 1', '5100', 'Bergen', '4601', 'NO', '10.110', %L),
    (%L, 'ES SC3 B1 Factory Mod', %L, %L, '2023-01-01', 'B1 Factory 2', '5101', 'Bergen', '4601', 'NO', '10.120', %L),
    -- ES B2 periods
    (%L, 'ES SC3 B2 Lab', %L, %L, '2023-01-01', 'B2 Lab Way 1', '5200', 'Bergen', '4601', 'NO', '72.110', %L),
    (%L, 'ES SC3 B2 Lab', %L, %L, '2023-01-01', 'B2 Lab Way 1', '5200', 'Bergen', '4601', 'NO', '72.110', %L),
    (%L, 'ES SC3 B2 Lab Updated', %L, %L, '2023-01-01', 'B2 Lab Way 2', '5201', 'Bergen', '4601', 'NO', '72.190', %L),
    -- ES B3 periods
    (%L, 'ES SC3 B3 Service', %L, %L, '2023-01-01', 'B3 Service 1', '5300', 'Bergen', '4601', 'NO', '45.200', %L),
    (%L, 'ES SC3 B3 Service', %L, %L, '2023-01-01', 'B3 Service 1', '5300', 'Bergen', '4601', 'NO', '45.200', %L),
    (%L, 'ES SC3 B3 Service New', %L, %L, '2023-01-01', 'B3 Service 2', '5301', 'Bergen', '4601', 'NO', '10.8', %L);
$$, -- No table variable needed here
    -- A1
    :'sc3_es_a1_tax_ident', :'sc3_p1_from', :'sc3_p1_to', :'sc3_lu_a_tax_ident',
    :'sc3_es_a1_tax_ident', :'sc3_p2_from', :'sc3_p2_to', :'sc3_lu_a_tax_ident',
    :'sc3_es_a1_tax_ident', :'sc3_p3_from', :'sc3_p3_to', :'sc3_lu_a_tax_ident',
    -- A2
    :'sc3_es_a2_tax_ident', :'sc3_p1_from', :'sc3_p1_to', :'sc3_lu_a_tax_ident',
    :'sc3_es_a2_tax_ident', :'sc3_p2_from', :'sc3_p2_to', :'sc3_lu_a_tax_ident',
    :'sc3_es_a2_tax_ident', :'sc3_p3_from', :'sc3_p3_to', :'sc3_lu_a_tax_ident',
    -- A3
    :'sc3_es_a3_tax_ident', :'sc3_p1_from', :'sc3_p1_to', :'sc3_lu_a_tax_ident',
    :'sc3_es_a3_tax_ident', :'sc3_p2_from', :'sc3_p2_to', :'sc3_lu_a_tax_ident',
    :'sc3_es_a3_tax_ident', :'sc3_p3_from', :'sc3_p3_to', :'sc3_lu_a_tax_ident',
    -- B1
    :'sc3_es_b1_tax_ident', :'sc3_p1_from', :'sc3_p1_to', :'sc3_lu_b_tax_ident',
    :'sc3_es_b1_tax_ident', :'sc3_p2_from', :'sc3_p2_to', :'sc3_lu_b_tax_ident',
    :'sc3_es_b1_tax_ident', :'sc3_p3_from', :'sc3_p3_to', :'sc3_lu_b_tax_ident',
    -- B2
    :'sc3_es_b2_tax_ident', :'sc3_p1_from', :'sc3_p1_to', :'sc3_lu_b_tax_ident',
    :'sc3_es_b2_tax_ident', :'sc3_p2_from', :'sc3_p2_to', :'sc3_lu_b_tax_ident',
    :'sc3_es_b2_tax_ident', :'sc3_p3_from', :'sc3_p3_to', :'sc3_lu_b_tax_ident',
    -- B3
    :'sc3_es_b3_tax_ident', :'sc3_p1_from', :'sc3_p1_to', :'sc3_lu_b_tax_ident',
    :'sc3_es_b3_tax_ident', :'sc3_p2_from', :'sc3_p2_to', :'sc3_lu_b_tax_ident',
    :'sc3_es_b3_tax_ident', :'sc3_p3_from', :'sc3_p3_to', :'sc3_lu_b_tax_ident'
) \gexec

-- Process ESs
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC3: Verifying _data table contents for ESs job (test72_sc3_ests)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, legal_unit_tax_ident, action, state, error, invalid_codes, -- removed operation
       CASE WHEN establishment_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS establishment_id_status,
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS lu_fk_id_status
FROM public.test72_sc3_ests_data -- Hardcoded based on sc3_job_es_slug
ORDER BY row_id;

-- SC3 Verifications
\echo 'SC3: Verifying results'
\echo 'SC3: Legal Units (expect 2 LUs, each with 2 temporal slices)'
SELECT
    COUNT(*) OVER() AS total_slices,
    (SELECT COUNT(DISTINCT lu2.id) FROM public.legal_unit lu2 
     JOIN public.external_ident ei2 ON ei2.legal_unit_id = lu2.id AND ei2.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
     WHERE ei2.ident IN (:'sc3_lu_a_tax_ident', :'sc3_lu_b_tax_ident')) AS distinct_lus,
    lu.name,
    ei.ident AS tax_ident,
    lu.valid_from,
    lu.valid_to,
    CASE WHEN lu.enterprise_id IS NOT NULL THEN 'EN_SET' ELSE 'EN_NULL' END AS en_marker,
    -- Check each distinct LU has its own enterprise
    CASE 
        WHEN (SELECT COUNT(DISTINCT lu3.enterprise_id) FROM public.legal_unit lu3 
              JOIN public.external_ident ei3 ON ei3.legal_unit_id = lu3.id AND ei3.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
              WHERE ei3.ident IN (:'sc3_lu_a_tax_ident', :'sc3_lu_b_tax_ident')) = 
             (SELECT COUNT(DISTINCT lu4.id) FROM public.legal_unit lu4 
              JOIN public.external_ident ei4 ON ei4.legal_unit_id = lu4.id AND ei4.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
              WHERE ei4.ident IN (:'sc3_lu_a_tax_ident', :'sc3_lu_b_tax_ident'))
        THEN 'UNIQUE_ENS' 
        ELSE 'SHARED_ENS' 
    END AS en_uniqueness
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident IN (:'sc3_lu_a_tax_ident', :'sc3_lu_b_tax_ident')
ORDER BY ei.ident, lu.valid_from;

\echo 'SC3: Establishments (expect 16 slices in total)'
SELECT
    COUNT(*) OVER() AS total_slices,
    (SELECT COUNT(DISTINCT est2.id) FROM public.establishment est2
     JOIN public.external_ident ei2 ON ei2.establishment_id = est2.id AND ei2.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
     WHERE ei2.ident IN (:'sc3_es_a1_tax_ident', :'sc3_es_a2_tax_ident', :'sc3_es_a3_tax_ident',
                         :'sc3_es_b1_tax_ident', :'sc3_es_b2_tax_ident', :'sc3_es_b3_tax_ident')) AS distinct_ests,
    est.name,
    ei.ident AS tax_ident,
    est.valid_from,
    est.valid_to,
    CASE WHEN est.legal_unit_id IS NOT NULL THEN 'LU_LINKED' ELSE 'LU_NULL' END AS lu_link_marker,
    CASE WHEN est.enterprise_id IS NOT NULL THEN 'EN_SET' ELSE 'EN_NULL' END AS en_marker
FROM public.establishment est
JOIN public.external_ident ei ON ei.establishment_id = est.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident IN (:'sc3_es_a1_tax_ident', :'sc3_es_a2_tax_ident', :'sc3_es_a3_tax_ident',
                   :'sc3_es_b1_tax_ident', :'sc3_es_b2_tax_ident', :'sc3_es_b3_tax_ident')
ORDER BY ei.ident, est.valid_from;

\echo 'SC3: Enterprises (expect 2 distinct enterprises)'
SELECT
    COUNT(*) OVER() AS total_enterprises,
    (SELECT COUNT(DISTINCT lu.id) FROM public.legal_unit lu WHERE lu.enterprise_id = e.id) as distinct_lus,
    (SELECT COUNT(DISTINCT est.id) FROM public.establishment est WHERE est.enterprise_id = e.id) as distinct_ests,
    (SELECT string_agg(DISTINCT ei.ident, ', ' ORDER BY ei.ident) 
     FROM public.legal_unit lu 
     JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
     JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
     WHERE lu.enterprise_id = e.id) as linked_lu_tax_idents
FROM public.enterprise e
WHERE e.id IN (
    SELECT DISTINCT lu.enterprise_id 
    FROM public.legal_unit lu 
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
    JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
    WHERE ei.ident IN (:'sc3_lu_a_tax_ident', :'sc3_lu_b_tax_ident')
)
ORDER BY linked_lu_tax_idents;

\echo 'SC3: Critical Check - Enterprise Assignment'
SELECT 
    'LU A Enterprise' as check_type,
    COUNT(DISTINCT lu.enterprise_id) as distinct_enterprises
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident = :'sc3_lu_a_tax_ident'
UNION ALL
SELECT 
    'LU B Enterprise' as check_type,
    COUNT(DISTINCT lu.enterprise_id) as distinct_enterprises
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident = :'sc3_lu_b_tax_ident'
UNION ALL
SELECT 
    'ES A1-A3 Enterprises' as check_type,
    COUNT(DISTINCT est.enterprise_id) as distinct_enterprises
FROM public.establishment est
JOIN public.external_ident ei ON ei.establishment_id = est.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident IN (:'sc3_es_a1_tax_ident', :'sc3_es_a2_tax_ident', :'sc3_es_a3_tax_ident')
UNION ALL
SELECT 
    'ES B1-B3 Enterprises' as check_type,
    COUNT(DISTINCT est.enterprise_id) as distinct_enterprises
FROM public.establishment est
JOIN public.external_ident ei ON ei.establishment_id = est.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident IN (:'sc3_es_b1_tax_ident', :'sc3_es_b2_tax_ident', :'sc3_es_b3_tax_ident');

ROLLBACK TO scenario_3_start;
\echo 'SC3: Rolled back.'

-- Scenario 4 (SC4): Batch Composition and Order Invariance - Row Order
\echo 'SC4: Testing different row orders within a batch'
SAVEPOINT scenario_4_start;

-- SC4 will use same data as SC3 but in different orders
\set sc4_job_slug_v1 'test72_sc4_order_v1'
\set sc4_job_slug_v2 'test72_sc4_order_v2'

-- SC4 Version 1: Interleaved order (A1P1, B1P1, A1P2, B1P2, etc.)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc4_job_slug_v1', 'SC4 Order V1', 'Test 72 SC4 V1', :'default_edit_comment');

-- Removed \gset for sc4_v1_upload_table

-- Insert in interleaved order
SELECT format($$
    INSERT INTO public.test72_sc4_order_v1_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    -- Interleaved: A-P1, B-P1, A-P2, B-P2, A-P3, B-P3
    (%L, 'LU SC4 Company A', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'A Street 1', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC4 Company B', %L, %L, '3100', 'AS', 'mi', '2023-01-01', 'B Avenue 1', '5000', 'Bergen', '4601', 'NO', '02.100'),
    (%L, 'LU SC4 Company A', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'A Street 1', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC4 Company B', %L, %L, '3100', 'AS', 'mi', '2023-01-01', 'B Avenue 1', '5000', 'Bergen', '4601', 'NO', '02.100'),
    (%L, 'LU SC4 Company A Changed', %L, %L, '2300', 'AS', 'mi', '2023-01-01', 'A Street 2', '1001', 'Oslo', '0301', 'NO', '01.120'),
    (%L, 'LU SC4 Company B Modified', %L, %L, '3200', 'AS', 'mi', '2023-01-01', 'B Avenue 2', '5001', 'Bergen', '4601', 'NO', '02.200');
$$, -- No table variable needed here
    :'sc3_lu_a_tax_ident', :'sc3_p1_from', :'sc3_p1_to',
    :'sc3_lu_b_tax_ident', :'sc3_p1_from', :'sc3_p1_to',
    :'sc3_lu_a_tax_ident', :'sc3_p2_from', :'sc3_p2_to',
    :'sc3_lu_b_tax_ident', :'sc3_p2_from', :'sc3_p2_to',
    :'sc3_lu_a_tax_ident', :'sc3_p3_from', :'sc3_p3_to',
    :'sc3_lu_b_tax_ident', :'sc3_p3_from', :'sc3_p3_to'
) \gexec

-- Process V1
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC4: Verifying _data table contents for V1 job (test72_sc4_order_v1)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
       CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc4_order_v1_data -- Hardcoded based on sc4_job_slug_v1
ORDER BY row_id;

-- SC4 Version 2: Reverse temporal order (all P3, then P2, then P1)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc4_job_slug_v2', 'SC4 Order V2', 'Test 72 SC4 V2', :'default_edit_comment');

-- Removed \gset for sc4_v2_upload_table

-- Insert in reverse temporal order
SELECT format($$
    INSERT INTO public.test72_sc4_order_v2_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    -- Reverse temporal: All P3, then all P2, then all P1
    (%L, 'LU SC4 Company A Changed', %L, %L, '2300', 'AS', 'mi', '2023-01-01', 'A Street 2', '1001', 'Oslo', '0301', 'NO', '01.120'),
    (%L, 'LU SC4 Company B Modified', %L, %L, '3200', 'AS', 'mi', '2023-01-01', 'B Avenue 2', '5001', 'Bergen', '4601', 'NO', '02.200'),
    (%L, 'LU SC4 Company A', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'A Street 1', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC4 Company B', %L, %L, '3100', 'AS', 'mi', '2023-01-01', 'B Avenue 1', '5000', 'Bergen', '4601', 'NO', '02.100'),
    (%L, 'LU SC4 Company A', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'A Street 1', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC4 Company B', %L, %L, '3100', 'AS', 'mi', '2023-01-01', 'B Avenue 1', '5000', 'Bergen', '4601', 'NO', '02.100');
$$, -- No table variable needed here
    :'sc3_lu_a_tax_ident', :'sc3_p3_from', :'sc3_p3_to',
    :'sc3_lu_b_tax_ident', :'sc3_p3_from', :'sc3_p3_to',
    :'sc3_lu_a_tax_ident', :'sc3_p2_from', :'sc3_p2_to',
    :'sc3_lu_b_tax_ident', :'sc3_p2_from', :'sc3_p2_to',
    :'sc3_lu_a_tax_ident', :'sc3_p1_from', :'sc3_p1_to',
    :'sc3_lu_b_tax_ident', :'sc3_p1_from', :'sc3_p1_to'
) \gexec

-- Process V2
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC4: Verifying _data table contents for V2 job (test72_sc4_order_v2)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
       CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc4_order_v2_data -- Hardcoded based on sc4_job_slug_v2
ORDER BY row_id;

-- SC4 Verification: Compare results
\echo 'SC4: Comparing enterprise assignments between different row orders'
WITH v1_enterprises AS (
    SELECT 
        ei.ident AS tax_ident,
        lu.enterprise_id
    FROM public.legal_unit lu
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
    JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
    WHERE ei.ident IN (:'sc3_lu_a_tax_ident', :'sc3_lu_b_tax_ident')
    AND lu.valid_from = '2023-01-01'::date -- Use first period to identify the LU
),
v2_enterprises AS (
    SELECT 
        ei.ident AS tax_ident,
        lu.enterprise_id
    FROM public.legal_unit lu
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
    JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
    WHERE ei.ident IN (:'sc3_lu_a_tax_ident', :'sc3_lu_b_tax_ident')
    AND lu.valid_from = '2023-07-01'::date -- Different starting point due to reverse order
)
SELECT 
    CASE 
        WHEN COUNT(DISTINCT v1.enterprise_id) = 2 AND COUNT(DISTINCT v2.enterprise_id) = 2 
             AND COUNT(DISTINCT v1.tax_ident) = 2 AND COUNT(DISTINCT v2.tax_ident) = 2
        THEN 'PASS: Both orderings created 2 distinct enterprises'
        ELSE 'FAIL: Different enterprise counts between orderings'
    END as test_result,
    COUNT(DISTINCT v1.enterprise_id) as v1_enterprise_count,
    COUNT(DISTINCT v2.enterprise_id) as v2_enterprise_count
FROM v1_enterprises v1
FULL OUTER JOIN v2_enterprises v2 ON v1.tax_ident = v2.tax_ident;

ROLLBACK TO scenario_4_start;
\echo 'SC4: Rolled back.'

-- Scenario 5 (SC5): Data Split Across Batches
\echo 'SC5: Testing data split across multiple batches'
SAVEPOINT scenario_5_start;

-- SC5.1: Entity Type Split (All LUs in batch 1, all ESs in batch 2)
\echo 'SC5.1: Entity Type Split'

-- Batch 1: LUs only
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test72_sc5_1_lus', 'SC5.1 LUs', 'Test 72 SC5.1 LUs', :'default_edit_comment');

-- Removed \gset for sc5_1_lu_upload_table

SELECT format($$
    INSERT INTO public.test72_sc5_1_lus_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC5.1 Alpha', '2023-01-01', '2023-12-31', '2100', 'AS', 'mi', '2023-01-01', 'Alpha St', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC5.1 Beta',  '2023-01-01', '2023-12-31', '3100', 'AS', 'mi', '2023-01-01', 'Beta Ave', '5000', 'Bergen', '4601', 'NO', '02.100');
$$, -- No table variable needed here
'''SC5ALPHA''', '''SC5BETA''') \gexec

-- Process LUs
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC5.1: Verifying _data table contents for LUs job (test72_sc5_1_lus)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
       CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc5_1_lus_data -- Hardcoded
ORDER BY row_id;

-- Batch 2: ESs only
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:es_import_def_id, 'test72_sc5_1_ests', 'SC5.1 ESs', 'Test 72 SC5.1 ESs', :'default_edit_comment');

-- Removed \gset for sc5_1_es_upload_table

SELECT format($$
    INSERT INTO public.test72_sc5_1_ests_upload (tax_ident, name, valid_from, valid_to, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code, legal_unit_tax_ident) VALUES
    (%L, 'ES SC5.1 Alpha Shop', '2023-01-01', '2023-12-31', '2023-01-01', 'Alpha Shop 1', '1100', 'Oslo', '0301', 'NO', '46.48', %L),
    (%L, 'ES SC5.1 Beta Factory', '2023-01-01', '2023-12-31', '2023-01-01', 'Beta Factory 1', '5100', 'Bergen', '4601', 'NO', '10.110', %L);
$$, -- No table variable needed here
'''SC5ES001''', '''SC5ALPHA''', '''SC5ES002''', '''SC5BETA''') \gexec

-- Process ESs
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC5.1: Verifying _data table contents for ESs job (test72_sc5_1_ests)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, legal_unit_tax_ident, action, state, error, invalid_codes, -- removed operation
       CASE WHEN establishment_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS establishment_id_status,
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS lu_fk_id_status
FROM public.test72_sc5_1_ests_data -- Hardcoded
ORDER BY row_id;

\echo 'SC5.1: Verifying Entity Type Split results'
SELECT 
    'SC5.1 Enterprises' as check_type,
    COUNT(DISTINCT e.id) as enterprise_count
FROM public.enterprise e
WHERE e.id IN (
    SELECT DISTINCT lu.enterprise_id 
    FROM public.legal_unit lu 
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
    JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
    WHERE ei.ident IN ('''SC5ALPHA''', '''SC5BETA''')
);

SELECT 
    'SC5.1 ES Enterprise Links' as check_type,
    ei_est.ident as est_tax_ident,
    ei_lu.ident as linked_lu_tax_ident,
    est.enterprise_id = lu.enterprise_id as same_enterprise
FROM public.establishment est
JOIN public.external_ident ei_est ON ei_est.establishment_id = est.id 
JOIN public.external_ident_type eit_est ON ei_est.type_id = eit_est.id AND eit_est.code = 'tax_ident'
JOIN public.legal_unit lu ON est.legal_unit_id = lu.id
JOIN public.external_ident ei_lu ON ei_lu.legal_unit_id = lu.id 
JOIN public.external_ident_type eit_lu ON ei_lu.type_id = eit_lu.id AND eit_lu.code = 'tax_ident'
WHERE ei_est.ident IN ('''SC5ES001''', '''SC5ES002''')
ORDER BY ei_est.ident;

ROLLBACK TO scenario_5_start;
\echo 'SC5: Rolled back.'

-- Scenario 6 (SC6): Replace/Update Actions
\echo 'SC6: Testing replace/update actions with different batch compositions'
SAVEPOINT scenario_6_start;

-- SC6 Setup: Create baseline LUs
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test72_sc6_baseline', 'SC6 Baseline', 'Test 72 SC6 Baseline', :'default_edit_comment');

-- Removed \gset for sc6_baseline_upload_table

SELECT format($$
    INSERT INTO public.test72_sc6_baseline_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC6 Original A', '2023-01-01', '2023-12-31', '2100', 'AS', 'mi', '2023-01-01', 'Original A St', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC6 Original B', '2023-01-01', '2023-12-31', '3100', 'AS', 'mi', '2023-01-01', 'Original B Ave', '5000', 'Bergen', '4601', 'NO', '02.100');
$$, -- No table variable needed here
'''SC6LUA''', '''SC6LUB''') \gexec

-- Process baseline
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC6: Verifying _data table contents for Baseline job (test72_sc6_baseline)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
       CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc6_baseline_data -- Hardcoded
ORDER BY row_id;

-- Capture baseline enterprise IDs
SELECT lu.enterprise_id AS sc6_ent_a_id
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident = '''SC6LUA''' LIMIT 1 \gset

SELECT lu.enterprise_id AS sc6_ent_b_id
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident = '''SC6LUB''' LIMIT 1 \gset

\echo 'SC6: Baseline enterprises created'
SELECT 
    CASE 
        WHEN COUNT(DISTINCT lu.enterprise_id) = 2 THEN 'PASS: Two distinct baseline enterprises created'
        ELSE 'FAIL: Expected 2 distinct enterprises, got ' || COUNT(DISTINCT lu.enterprise_id)
    END AS baseline_check
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident IN ('''SC6LUA''', '''SC6LUB''');

-- SC6.1: Single batch update
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test72_sc6_1_single', 'SC6.1 Single Batch', 'Test 72 SC6.1', :'default_edit_comment');

-- Removed \gset for sc6_1_upload_table

SELECT format($$
    INSERT INTO public.test72_sc6_1_single_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC6 Updated A', '2023-01-01', '2023-12-31', '2100', 'AS', 'mi', '2023-01-01', 'Updated A St', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC6 Updated B', '2023-01-01', '2023-12-31', '3100', 'AS', 'mi', '2023-01-01', 'Updated B Ave', '5000', 'Bergen', '4601', 'NO', '02.100');
$$, -- No table variable needed here
'''SC6LUA''', '''SC6LUB''') \gexec

-- Process update
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC6.1: Verifying _data table contents for Single Batch Update job (test72_sc6_1_single)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
       CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc6_1_single_data -- Hardcoded
ORDER BY row_id;

\echo 'SC6.1: Verifying single batch update preserved enterprise links'
WITH updated_lus AS (
    SELECT
        ei.ident,
        lu.enterprise_id,
        lu.name
    FROM public.legal_unit lu
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
    JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
    WHERE ei.ident IN ('''SC6LUA''', '''SC6LUB''')
    AND lu.name LIKE 'LU SC6 Updated%' -- Ensure we are looking at the records after update
)
SELECT
    ul.ident as tax_ident,
    ul.name,
    CASE
        WHEN ul.ident = '''SC6LUA''' AND ul.enterprise_id = :sc6_ent_a_id THEN 'PASS: SC6LUA Kept same enterprise'
        WHEN ul.ident = '''SC6LUB''' AND ul.enterprise_id = :sc6_ent_b_id THEN 'PASS: SC6LUB Kept same enterprise'
        WHEN ul.ident = '''SC6LUA''' THEN 'FAIL: SC6LUA Enterprise changed! Was ' || :sc6_ent_a_id || ', Is ' || ul.enterprise_id
        WHEN ul.ident = '''SC6LUB''' THEN 'FAIL: SC6LUB Enterprise changed! Was ' || :sc6_ent_b_id || ', Is ' || ul.enterprise_id
        ELSE 'FAIL: LU not found or tax_ident mismatch'
    END as test_result,
    (SELECT ei_sub.ident FROM public.enterprise e_sub
     JOIN public.legal_unit lu_sub ON e_sub.id = lu_sub.enterprise_id AND lu_sub.primary_for_enterprise = TRUE
     JOIN public.external_ident ei_sub ON lu_sub.id = ei_sub.legal_unit_id
     JOIN public.external_ident_type eit_sub ON ei_sub.type_id = eit_sub.id AND eit_sub.code = 'tax_ident'
     WHERE e_sub.id = ul.enterprise_id
     LIMIT 1) AS enterprise_main_ident
FROM updated_lus ul
ORDER BY ul.ident;

ROLLBACK TO scenario_6_start;
\echo 'SC6: Rolled back.'

-- Scenario 7 (SC7): Multiple LUs for Same Enterprise (Primary Flag Handling)
\echo 'SC7: Multiple LUs for Same Enterprise - Testing primary_for_enterprise flag'
SAVEPOINT scenario_7_start;

-- SC7 Constants
\set sc7_lu1_tax_ident '''SC7LU001'''
\set sc7_lu2_tax_ident '''SC7LU002'''
\set sc7_lu3_tax_ident '''SC7LU003'''
\set sc7_job_slug 'test72_sc7_multi_lu_same_ent'
\set sc7_valid_from '''2023-01-01'''
\set sc7_valid_to   '''2023-12-31'''

-- Step 1: Create initial two LUs (they will get separate enterprises initially)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc7_job_slug', 'SC7 Initial LUs', 'Test 72 SC7 Initial', :'default_edit_comment');

-- Removed \gset for sc7_upload_table

-- Insert two LUs
SELECT format($$
    INSERT INTO public.test72_sc7_multi_lu_same_ent_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC7 Company One', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'First St 1', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC7 Company Two', %L, %L, '3200', 'AS', 'mi', '2023-01-01', 'Second St 2', '5000', 'Bergen', '4601', 'NO', '02.200');
$$, -- No table variable needed here
    :'sc7_lu1_tax_ident', :'sc7_valid_from', :'sc7_valid_to',
    :'sc7_lu2_tax_ident', :'sc7_valid_from', :'sc7_valid_to'
) \gexec

-- Process initial LUs
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC7: Verifying _data table contents for Initial LUs job (test72_sc7_multi_lu_same_ent)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
       CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc7_multi_lu_same_ent_data -- Hardcoded
ORDER BY row_id;

\echo 'SC7: Initial state - two LUs with separate enterprises'
SELECT 
    lu.name,
    ei.ident AS tax_ident,
    (SELECT ei_sub.ident FROM public.enterprise e_sub
     JOIN public.legal_unit lu_sub ON e_sub.id = lu_sub.enterprise_id AND lu_sub.primary_for_enterprise = TRUE
     JOIN public.external_ident ei_sub ON lu_sub.id = ei_sub.legal_unit_id
     JOIN public.external_ident_type eit_sub ON ei_sub.type_id = eit_sub.id AND eit_sub.code = 'tax_ident'
     WHERE e_sub.id = lu.enterprise_id
     LIMIT 1) AS enterprise_main_ident,
    lu.primary_for_enterprise,
    e.short_name as enterprise_name
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
JOIN public.enterprise e ON lu.enterprise_id = e.id
WHERE ei.ident IN (:'sc7_lu1_tax_ident', :'sc7_lu2_tax_ident')
ORDER BY ei.ident;

-- Step 2: Connect LU2 to LU1's enterprise (mimicking the pattern from test 05)
\echo 'SC7: Connecting LU2 to LU1''s enterprise'
WITH lu1_enterprise AS (
    SELECT lu.enterprise_id 
    FROM public.legal_unit lu
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
    JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
    WHERE ei.ident = :'sc7_lu1_tax_ident'
), lu2_unit AS (
    SELECT lu.id as unit_id
    FROM public.legal_unit lu
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
    JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
    WHERE ei.ident = :'sc7_lu2_tax_ident' LIMIT 1
), raw_connection_output AS (
    SELECT public.connect_legal_unit_to_enterprise(
        lu2_unit.unit_id, 
        lu1_enterprise.enterprise_id, 
        '2023-01-01'::date, 
        'infinity'::date
    ) as result_json
    FROM lu1_enterprise, lu2_unit
), mapped_output AS (
    SELECT
        jsonb_build_object(
            'new_enterprise_ident', (
                SELECT ei_lu.ident 
                FROM public.enterprise e_map
                JOIN public.legal_unit lu_primary ON lu_primary.enterprise_id = e_map.id AND lu_primary.primary_for_enterprise = TRUE
                JOIN public.external_ident ei_lu ON ei_lu.legal_unit_id = lu_primary.id AND ei_lu.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
                WHERE e_map.id = (r.result_json->>'new_enterprise_id')::INT
                LIMIT 1
            ),
            'old_enterprise_ident', (
                SELECT ei_lu.ident 
                FROM public.enterprise e_map
                JOIN public.legal_unit lu_primary ON lu_primary.enterprise_id = e_map.id AND lu_primary.primary_for_enterprise = TRUE
                JOIN public.external_ident ei_lu ON ei_lu.legal_unit_id = lu_primary.id AND ei_lu.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
                WHERE e_map.id = (r.result_json->>'old_enterprise_id')::INT
                LIMIT 1
            ),
            'deleted_enterprise_ident', (
                SELECT ei_lu.ident 
                FROM public.enterprise e_map
                JOIN public.legal_unit lu_primary ON lu_primary.enterprise_id = e_map.id AND lu_primary.primary_for_enterprise = TRUE
                JOIN public.external_ident ei_lu ON ei_lu.legal_unit_id = lu_primary.id AND ei_lu.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
                WHERE e_map.id = (r.result_json->>'deleted_enterprise_id')::INT
                LIMIT 1
            ),
            'updated_legal_unit_idents', COALESCE((
                SELECT jsonb_agg(ei_lu.ident ORDER BY ei_lu.ident)
                FROM jsonb_array_elements_text(r.result_json->'updated_legal_unit_ids') AS lu_id_text
                JOIN public.legal_unit lu_map ON lu_map.id = lu_id_text::INT
                JOIN public.external_ident ei_lu ON ei_lu.legal_unit_id = lu_map.id AND ei_lu.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
            ), '[]'::jsonb)
        ) AS stable_connection_result
    FROM raw_connection_output r
)
SELECT stable_connection_result FROM mapped_output;

\echo 'SC7: After connection - both LUs share same enterprise'
SELECT 
    lu.name,
    ei.ident AS tax_ident,
    (SELECT ei_sub.ident FROM public.enterprise e_sub
     JOIN public.legal_unit lu_sub ON e_sub.id = lu_sub.enterprise_id AND lu_sub.primary_for_enterprise = TRUE
     JOIN public.external_ident ei_sub ON lu_sub.id = ei_sub.legal_unit_id
     JOIN public.external_ident_type eit_sub ON ei_sub.type_id = eit_sub.id AND eit_sub.code = 'tax_ident'
     WHERE e_sub.id = lu.enterprise_id
     LIMIT 1) AS enterprise_main_ident,
    lu.primary_for_enterprise,
    CASE 
        WHEN lu.primary_for_enterprise THEN 'PRIMARY'
        ELSE 'NOT PRIMARY'
    END as primary_status
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident IN (:'sc7_lu1_tax_ident', :'sc7_lu2_tax_ident')
ORDER BY ei.ident;

-- Step 3: Import batch with update to existing LU and a new LU
\echo 'SC7: Import batch with update to LU1 and new LU3'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test72_sc7_update_batch', 'SC7 Update Batch', 'Test 72 SC7 Update', :'default_edit_comment');

-- Removed \gset for sc7_update_upload_table

-- Insert update to LU1 and new LU3
SELECT format($$
    INSERT INTO public.test72_sc7_update_batch_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC7 Company One UPDATED', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'First St 1 Updated', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC7 Company Three NEW', %L, %L, '4100', 'AS', 'mi', '2023-01-01', 'Third St 3', '7000', 'Trondheim', '5001', 'NO', '01.3');
$$, -- No table variable needed here
    :'sc7_lu1_tax_ident', :'sc7_valid_from', :'sc7_valid_to',
    :'sc7_lu3_tax_ident', :'sc7_valid_from', :'sc7_valid_to'
) \gexec

-- Process update batch
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC7: Verifying _data table contents for Update Batch job (test72_sc7_update_batch)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
       CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc7_update_batch_data -- Hardcoded
ORDER BY row_id;

\echo 'SC7: Final state - checking primary_for_enterprise handling'
SELECT 
    lu.name,
    ei.ident AS tax_ident,
    (SELECT ei_sub.ident FROM public.enterprise e_sub
     JOIN public.legal_unit lu_sub ON e_sub.id = lu_sub.enterprise_id AND lu_sub.primary_for_enterprise = TRUE
     JOIN public.external_ident ei_sub ON lu_sub.id = ei_sub.legal_unit_id
     JOIN public.external_ident_type eit_sub ON ei_sub.type_id = eit_sub.id AND eit_sub.code = 'tax_ident'
     WHERE e_sub.id = lu.enterprise_id
     LIMIT 1) AS enterprise_main_ident,
    lu.primary_for_enterprise,
    CASE 
        WHEN lu.primary_for_enterprise THEN 'PRIMARY'
        ELSE 'NOT PRIMARY'
    END as primary_status,
    lu.edit_comment
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident IN (:'sc7_lu1_tax_ident', :'sc7_lu2_tax_ident', :'sc7_lu3_tax_ident')
ORDER BY tax_ident;

\echo 'SC7: Enterprise count check'
SELECT COUNT(DISTINCT lu.enterprise_id) as distinct_enterprises,
       COUNT(DISTINCT lu.enterprise_id) || ' distinct enterprise(s)' as enterprise_info
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident IN (:'sc7_lu1_tax_ident', :'sc7_lu2_tax_ident', :'sc7_lu3_tax_ident');

ROLLBACK TO scenario_7_start;
\echo 'SC7: Rolled back.'

-- Scenario 8 (SC8): Multiple ESs for Same LU (Primary Flag Handling)
\echo 'SC8: Multiple ESs for Same LU - Testing primary_for_legal_unit flag'
SAVEPOINT scenario_8_start;

-- SC8 Constants
\set sc8_lu_tax_ident '''SC8LU001'''
\set sc8_es1_tax_ident '''SC8ES001'''
\set sc8_es2_tax_ident '''SC8ES002'''
\set sc8_es3_tax_ident '''SC8ES003'''
\set sc8_job_lu_slug 'test72_sc8_lu'
\set sc8_job_es_slug 'test72_sc8_multi_es'
\set sc8_valid_from '''2023-01-01'''
\set sc8_valid_to   '''2023-12-31'''

-- Step 1: Create LU
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc8_job_lu_slug', 'SC8 LU', 'Test 72 SC8 LU', :'default_edit_comment');

-- Removed \gset for sc8_lu_upload_table

SELECT format($$
    INSERT INTO public.test72_sc8_lu_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC8 Main Company', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Main St 1', '1000', 'Oslo', '0301', 'NO', '01.110');
$$, -- No table variable needed here
    :'sc8_lu_tax_ident', :'sc8_valid_from', :'sc8_valid_to'
) \gexec

-- Process LU
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC8: Verifying _data table contents for LU job (test72_sc8_lu)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
       CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc8_lu_data -- Hardcoded
ORDER BY row_id;

-- Step 2: Create multiple ESs for the same LU
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:es_import_def_id, :'sc8_job_es_slug', 'SC8 Multiple ESs', 'Test 72 SC8 ESs', :'default_edit_comment');

-- Removed \gset for sc8_es_upload_table

SELECT format($$
    INSERT INTO public.test72_sc8_multi_es_upload (tax_ident, name, valid_from, valid_to, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code, legal_unit_tax_ident) VALUES
    (%L, 'ES SC8 Branch One', %L, %L, '2023-01-01', 'Branch St 1', '1100', 'Oslo', '0301', 'NO', '46.48', %L),
    (%L, 'ES SC8 Branch Two', %L, %L, '2023-01-01', 'Branch St 2', '1200', 'Oslo', '0301', 'NO', '47.190', %L),
    (%L, 'ES SC8 Branch Three', %L, %L, '2023-01-01', 'Branch St 3', '1300', 'Oslo', '0301', 'NO', '47.210', %L);
$$, -- No table variable needed here
    :'sc8_es1_tax_ident', :'sc8_valid_from', :'sc8_valid_to', :'sc8_lu_tax_ident',
    :'sc8_es2_tax_ident', :'sc8_valid_from', :'sc8_valid_to', :'sc8_lu_tax_ident',
    :'sc8_es3_tax_ident', :'sc8_valid_from', :'sc8_valid_to', :'sc8_lu_tax_ident'
) \gexec

-- Process ESs
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC8: Verifying _data table contents for ESs job (test72_sc8_multi_es)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, legal_unit_tax_ident, action, state, error, invalid_codes, -- removed operation
       CASE WHEN establishment_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS establishment_id_status,
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS lu_fk_id_status
FROM public.test72_sc8_multi_es_data -- Hardcoded
ORDER BY row_id;

\echo 'SC8: Checking primary_for_legal_unit handling'
SELECT 
    est.name,
    ei.ident AS tax_ident,
    (SELECT ei_lu.ident
     FROM public.legal_unit lu_link
     JOIN public.external_ident ei_lu ON ei_lu.legal_unit_id = lu_link.id
     JOIN public.external_ident_type eit_lu ON eit_lu.id = ei_lu.type_id AND eit_lu.code = 'tax_ident'
     WHERE lu_link.id = est.legal_unit_id
     LIMIT 1) AS linked_lu_tax_ident,
    est.primary_for_legal_unit,
    CASE 
        WHEN est.primary_for_legal_unit THEN 'PRIMARY'
        ELSE 'NOT PRIMARY'
    END as primary_status,
    est.edit_comment
FROM public.establishment est
JOIN public.external_ident ei ON ei.establishment_id = est.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
WHERE ei.ident IN (:'sc8_es1_tax_ident', :'sc8_es2_tax_ident', :'sc8_es3_tax_ident')
ORDER BY tax_ident;

\echo 'SC8: Verify all ESs linked to same LU'
SELECT 
    COUNT(DISTINCT est.legal_unit_id) as distinct_lus,
    string_agg(DISTINCT lu_ei.ident, ', ') as linked_lu_tax_idents
FROM public.establishment est
JOIN public.external_ident ei ON ei.establishment_id = est.id 
JOIN public.external_ident_type eit ON ei.type_id = eit.id AND eit.code = 'tax_ident'
JOIN public.legal_unit lu ON est.legal_unit_id = lu.id
JOIN public.external_ident lu_ei ON lu_ei.legal_unit_id = lu.id 
JOIN public.external_ident_type lu_eit ON lu_ei.type_id = lu_eit.id AND lu_eit.code = 'tax_ident'
WHERE ei.ident IN (:'sc8_es1_tax_ident', :'sc8_es2_tax_ident', :'sc8_es3_tax_ident');

ROLLBACK TO scenario_8_start;
\echo 'SC8: Rolled back.'

-- Scenario 9 (SC9): LU with Temporally Overlapping Segments in Same Batch
\echo 'SC9: LU with Temporally Overlapping Segments (should error)'
SAVEPOINT scenario_9_start;

-- SC9 Constants
\set sc9_lu_tax_ident '''SC9LU001'''
\set sc9_job_slug 'test72_sc9_lu_overlap'
\set sc9_p1_from '''2023-01-01'''
-- Segment 1
\set sc9_p1_to   '''2023-06-30'''
-- Overlaps with Segment 1
\set sc9_p2_from '''2023-04-01'''
-- Segment 2
\set sc9_p2_to   '''2023-09-30'''

-- SC9 Create Job
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc9_job_slug', 'SC9 LU Overlapping Segments', 'Test 72 SC9', :'default_edit_comment');

-- Removed \gset for sc9_upload_table and sc9_data_table

-- SC9 Insert data into upload table with overlapping segments
SELECT format($$
    INSERT INTO public.test72_sc9_lu_overlap_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC9 Overlap Seg1', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Addr SC9 Seg1', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC9 Overlap Seg2', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Addr SC9 Seg2', '1000', 'Oslo', '0301', 'NO', '01.110');
$$, -- No table variable needed here
    :'sc9_lu_tax_ident', :'sc9_p1_from', :'sc9_p1_to',
    :'sc9_lu_tax_ident', :'sc9_p2_from', :'sc9_p2_to'
) \gexec

-- SC9 Simulate import processing steps
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

-- SC9 Verifications
\echo 'SC9: Verifying _data table contents'
SELECT row_id, tax_ident, name, valid_from, valid_to, error, invalid_codes, state, action 
FROM public.test72_sc9_lu_overlap_data -- Hardcoded based on sc9_job_slug
ORDER BY row_id;

\echo 'SC9: Verifying _data table contents (expecting successful processing and overlap resolution)'
DO $sc9_verify_data_content$
DECLARE
    v_data_table_check_result TEXT;
BEGIN
    -- Query directly using hardcoded table name within the format string
    EXECUTE format($$ 
        WITH data_table_content AS (
            SELECT
                row_id,
                action,
                state,
                CASE
                    WHEN error IS NOT NULL AND error::TEXT <> '{}' THEN 'ERROR_PRESENT'
                    ELSE 'NO_ERROR'
                END as error_status
            FROM public.test72_sc9_lu_overlap_data -- Hardcoded
        )
        SELECT
            CASE
                WHEN COUNT(*) = 2
                 AND SUM(CASE WHEN state = 'processed' THEN 1 ELSE 0 END) = 2
                 AND SUM(CASE WHEN error_status = 'NO_ERROR' THEN 1 ELSE 0 END) = 2
                 AND SUM(CASE WHEN row_id = 1 AND action = 'insert' THEN 1 ELSE 0 END) = 1
                 AND SUM(CASE WHEN row_id = 2 AND action = 'replace' THEN 1 ELSE 0 END) = 1
                THEN 'PASS: Both rows in _data table processed successfully with correct actions.'
                ELSE 'FAIL: _data table verification failed for SC9. ' ||
                     'Total rows: ' || COUNT(*) ||
                     ', Processed rows: ' || SUM(CASE WHEN state = 'processed' THEN 1 ELSE 0 END) ||
                     ', No error rows: ' || SUM(CASE WHEN error_status = 'NO_ERROR' THEN 1 ELSE 0 END) ||
                     ', Row 1 action insert: ' || SUM(CASE WHEN row_id = 1 AND action = 'insert' THEN 1 ELSE 0 END) ||
                     ', Row 2 action replace: ' || SUM(CASE WHEN row_id = 2 AND action = 'replace' THEN 1 ELSE 0 END)
            END
        FROM data_table_content
    $$) INTO v_data_table_check_result; -- No second argument to format needed
    RAISE NOTICE '%', v_data_table_check_result;
END $sc9_verify_data_content$;

\echo 'SC9: Verifying public.legal_unit table (expect 2 resolved slices)'
CREATE TEMP TABLE sc9_lu_results AS
SELECT
    lu.name,
    lu.valid_from,
    lu.valid_to,
    lu.enterprise_id, -- Keep for internal checks
    (SELECT ei_sub.ident FROM public.enterprise e_sub
     JOIN public.legal_unit lu_sub ON e_sub.id = lu_sub.enterprise_id AND lu_sub.primary_for_enterprise = TRUE
     JOIN public.external_ident ei_sub ON lu_sub.id = ei_sub.legal_unit_id
     JOIN public.external_ident_type eit_sub ON ei_sub.type_id = eit_sub.id AND eit_sub.code = 'tax_ident'
     WHERE e_sub.id = lu.enterprise_id
     LIMIT 1) AS enterprise_main_ident, -- Stable identifier for display
    lu.primary_for_enterprise
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = :'sc9_lu_tax_ident'
ORDER BY lu.valid_from;

SELECT name, valid_from, valid_to, enterprise_main_ident, primary_for_enterprise FROM sc9_lu_results ORDER BY valid_from;

SELECT
    CASE
        WHEN COUNT(*) = 2
         AND (SELECT COUNT(*) FROM sc9_lu_results WHERE name = 'LU SC9 Overlap Seg1' AND valid_from = :'sc9_p1_from' AND valid_to = (:'sc9_p2_from'::date - INTERVAL '1 day')) = 1
         AND (SELECT COUNT(*) FROM sc9_lu_results WHERE name = 'LU SC9 Overlap Seg2' AND valid_from = :'sc9_p2_from' AND valid_to = :'sc9_p2_to') = 1
         AND (SELECT COUNT(DISTINCT enterprise_id) FROM sc9_lu_results) = 1
         AND (SELECT bool_and(primary_for_enterprise) FROM sc9_lu_results) = TRUE -- Both resulting slices should be primary for the enterprise
        THEN 'PASS: Legal unit segments correctly resolved, enterprise link consistent, and primary flags set.'
        ELSE 'FAIL: Legal unit segments verification failed for SC9. Check names, dates, enterprise linkage, or primary flags.'
    END as lu_table_check
FROM sc9_lu_results;

DROP TABLE sc9_lu_results;

ROLLBACK TO scenario_9_start;
\echo 'SC9: Rolled back.'

-- Scenario 10 (SC10TB): LU with initial segments, then replaced by new overlapping segments in a subsequent TWO BATCHES
\echo 'SC10 (Two Batches): LU Replace/Update with Overlapping Segments Across Batches'
SAVEPOINT scenario_10_tb_start;

-- SC10TB Constants
\set sc10_tb_lu_tax_ident '''SC10TBLU001'''
\set sc10_tb_job_b1_slug 'test72_sc10_tb_lu_b1'
\set sc10_tb_job_b2_slug 'test72_sc10_tb_lu_b2'

-- Batch 1 Segments (Initial)
\set sc10_tb_b1_p1_from '''2023-01-01'''
\set sc10_tb_b1_p1_to   '''2023-03-31'''
\set sc10_tb_b1_p2_from '''2023-04-01'''
\set sc10_tb_b1_p2_to   '''2023-06-30'''
\set sc10_tb_b1_p3_from '''2023-07-01'''
\set sc10_tb_b1_p3_to   '''2023-09-30'''

-- Batch 2 Segments (Replacement/Overlapping)
\set sc10_tb_b2_pA_from '''2023-02-15''' -- Overlaps B1P1, B1P2
\set sc10_tb_b2_pA_to   '''2023-05-15'''
\set sc10_tb_b2_pB_from '''2023-05-16''' -- Contiguous with pA, overlaps B1P2, B1P3
\set sc10_tb_b2_pB_to   '''2023-08-15'''
\set sc10_tb_b2_pC_from '''2023-08-16''' -- Contiguous with pB, overlaps B1P3, extends
\set sc10_tb_b2_pC_to   '''2023-11-30'''

-- SC10TB Batch 1: Initial LU Insert
\echo 'SC10 (Two Batches) Batch 1: Initial Insert of LU with 3 Segments'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc10_tb_job_b1_slug', 'SC10TB LU Batch 1', 'Test 72 SC10TB Batch 1', :'default_edit_comment');

-- Removed \gset for sc10_tb_b1_upload_table and sc10_tb_b1_data_table

SELECT format($$
    INSERT INTO public.test72_sc10_tb_lu_b1_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC10TB Name B1P1', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Addr SC10TB B1P1', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC10TB Name B1P2', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Addr SC10TB B1P2', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC10TB Name B1P3', %L, %L, '2300', 'AS', 'mi', '2023-01-01', 'Addr SC10TB B1P3', '1001', 'Oslo', '0301', 'NO', '01.120');
$$, -- No table variable needed here
    :'sc10_tb_lu_tax_ident', :'sc10_tb_b1_p1_from', :'sc10_tb_b1_p1_to',
    :'sc10_tb_lu_tax_ident', :'sc10_tb_b1_p2_from', :'sc10_tb_b1_p2_to',
    :'sc10_tb_lu_tax_ident', :'sc10_tb_b1_p3_from', :'sc10_tb_b1_p3_to'
) \gexec

-- SC10TB Batch 1: Process
CALL worker.process_tasks(p_queue => 'import');

\echo 'SC10 (Two Batches) Batch 1: Verifying _data table contents for job (test72_sc10_tb_lu_b1)'
SELECT row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
       CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
       CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc10_tb_lu_b1_data -- Hardcoded based on sc10_tb_job_b1_slug
ORDER BY row_id;

-- SC10TB Batch 1: Verifications
\echo 'SC10 (Two Batches) Batch 1: Verifying LU (expect 3 slices, 1 enterprise, all primary)'
SELECT
    lu.name,
    lu.valid_from,
    lu.valid_to,
    (SELECT ei_sub.ident FROM public.enterprise e_sub
     JOIN public.legal_unit lu_sub ON e_sub.id = lu_sub.enterprise_id AND lu_sub.primary_for_enterprise = TRUE
     JOIN public.external_ident ei_sub ON lu_sub.id = ei_sub.legal_unit_id
     JOIN public.external_ident_type eit_sub ON ei_sub.type_id = eit_sub.id AND eit_sub.code = 'tax_ident'
     WHERE e_sub.id = lu.enterprise_id
     LIMIT 1) AS enterprise_main_ident,
    lu.primary_for_enterprise,
    (SELECT COUNT(*) FROM public.legal_unit lu_check WHERE lu_check.enterprise_id = lu.enterprise_id) as slices_in_enterprise
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
ORDER BY lu.valid_from;

SELECT lu.enterprise_id AS sc10_tb_enterprise_id_b1 FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = :'sc10_tb_lu_tax_ident' LIMIT 1 \gset

-- SC10TB Batch 2: Replace/Update LU with new Overlapping Segments
\echo 'SC10 (Two Batches) Batch 2: Replace/Update LU with 3 new Overlapping Segments'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc10_tb_job_b2_slug', 'SC10TB LU Batch 2', 'Test 72 SC10TB Batch 2', :'default_edit_comment');

-- Removed \gset for sc10_tb_b2_upload_table and sc10_tb_b2_data_table

SELECT format($$
    INSERT INTO public.test72_sc10_tb_lu_b2_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    (%L, 'LU SC10TB Name B2pA', %L, %L, '2300', 'AS', 'mi', '2023-01-01', 'Addr SC10TB B2pA', '1002', 'Oslo', '0301', 'NO', '01.130'),
    (%L, 'LU SC10TB Name B2pB', %L, %L, '2300', 'AS', 'mi', '2023-01-01', 'Addr SC10TB B2pB', '1002', 'Oslo', '0301', 'NO', '01.130'),
    (%L, 'LU SC10TB Name B2pC', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Addr SC10TB B2pC', '1003', 'Oslo', '0301', 'NO', '01.140');
$$, -- No table variable needed here
    :'sc10_tb_lu_tax_ident', :'sc10_tb_b2_pA_from', :'sc10_tb_b2_pA_to',
    :'sc10_tb_lu_tax_ident', :'sc10_tb_b2_pB_from', :'sc10_tb_b2_pB_to',
    :'sc10_tb_lu_tax_ident', :'sc10_tb_b2_pC_from', :'sc10_tb_b2_pC_to'
) \gexec

-- SC10TB Batch 2: Process
CALL worker.process_tasks(p_queue => 'import');

-- SC10TB Batch 2: Verifications
\echo 'SC10 (Two Batches) Batch 2: Verifying _data table contents after Batch 2 processing'
SELECT
    row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes, -- removed operation
    CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
    CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc10_tb_lu_b2_data -- Hardcoded based on sc10_tb_job_b2_slug
ORDER BY row_id;

\echo 'SC10 (Two Batches) Batch 2: Verifying LU (expect 4 final slices, same enterprise, all primary)'
CREATE TEMP TABLE sc10_tb_final_lu_state AS
SELECT
    lu.name,
    lu.valid_from,
    lu.valid_to,
    lu.enterprise_id, 
    (SELECT ei_sub.ident FROM public.enterprise e_sub
     JOIN public.legal_unit lu_sub ON e_sub.id = lu_sub.enterprise_id AND lu_sub.primary_for_enterprise = TRUE
     JOIN public.external_ident ei_sub ON lu_sub.id = ei_sub.legal_unit_id
     JOIN public.external_ident_type eit_sub ON ei_sub.type_id = eit_sub.id AND eit_sub.code = 'tax_ident'
     WHERE e_sub.id = lu.enterprise_id
     LIMIT 1) AS enterprise_main_ident,
    lu.primary_for_enterprise,
    (SELECT COUNT(*) FROM public.legal_unit lu_check WHERE lu_check.enterprise_id = lu.enterprise_id) as slices_in_enterprise,
    (SELECT COUNT(DISTINCT lu_check.enterprise_id) FROM public.legal_unit lu_check
     JOIN public.external_ident ei_check ON ei_check.legal_unit_id = lu_check.id AND ei_check.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
     WHERE ei_check.ident = :'sc10_tb_lu_tax_ident') as distinct_enterprise_ids_for_lu
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = :'sc10_tb_lu_tax_ident'
ORDER BY lu.valid_from;

SELECT 
    name,
    valid_from,
    valid_to,
    enterprise_main_ident,
    primary_for_enterprise,
    slices_in_enterprise,
    distinct_enterprise_ids_for_lu
FROM sc10_tb_final_lu_state
ORDER BY valid_from;

\echo 'SC10 (Two Batches) Batch 2: Final Checks'
SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM sc10_tb_final_lu_state) = 4 THEN 'PASS: Correct number of final segments (4)'
        ELSE 'FAIL: Incorrect number of final segments. Expected 4, Got ' || (SELECT COUNT(*) FROM sc10_tb_final_lu_state)
    END as segment_count_check;

SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM sc10_tb_final_lu_state WHERE name = 'LU SC10TB Name B1P1' AND valid_from = :'sc10_tb_b1_p1_from' AND valid_to = (:'sc10_tb_b2_pA_from'::date - INTERVAL '1 day')) = 1
         AND (SELECT COUNT(*) FROM sc10_tb_final_lu_state WHERE name = 'LU SC10TB Name B2pA' AND valid_from = :'sc10_tb_b2_pA_from' AND valid_to = :'sc10_tb_b2_pA_to') = 1
         AND (SELECT COUNT(*) FROM sc10_tb_final_lu_state WHERE name = 'LU SC10TB Name B2pB' AND valid_from = :'sc10_tb_b2_pB_from' AND valid_to = :'sc10_tb_b2_pB_to') = 1
         AND (SELECT COUNT(*) FROM sc10_tb_final_lu_state WHERE name = 'LU SC10TB Name B2pC' AND valid_from = :'sc10_tb_b2_pC_from' AND valid_to = :'sc10_tb_b2_pC_to') = 1
        THEN 'PASS: All 4 final segments have correct names and date ranges.'
        ELSE 'FAIL: Verification of final segment names and date ranges failed.'
    END as segment_date_name_check;

SELECT
    CASE
        WHEN (SELECT bool_and(primary_for_enterprise) FROM sc10_tb_final_lu_state) THEN 'PASS: All final segments are primary_for_enterprise'
        ELSE 'FAIL: Not all final segments are primary_for_enterprise'
    END as primary_flag_check;

SELECT
    CASE
        WHEN (SELECT MIN(enterprise_id) FROM sc10_tb_final_lu_state) = :'sc10_tb_enterprise_id_b1'
         AND (SELECT bool_and(enterprise_id = :'sc10_tb_enterprise_id_b1') FROM public.legal_unit WHERE id IN (SELECT legal_unit_id FROM public.external_ident WHERE ident = :'sc10_tb_lu_tax_ident'))
         AND (SELECT distinct_enterprise_ids_for_lu FROM sc10_tb_final_lu_state LIMIT 1) = 1
        THEN 'PASS: Enterprise ID remained consistent and is the same as Batch 1'
        ELSE 'FAIL: Enterprise ID changed or multiple enterprises found for LU. Batch1 Enterprise ID was: ' || :'sc10_tb_enterprise_id_b1' || 
              ', Final Enterprise Main Ident(s) for LU ' || :'sc10_tb_lu_tax_ident' || ': ' || (SELECT string_agg(DISTINCT enterprise_main_ident, ', ') FROM sc10_tb_final_lu_state)
    END as enterprise_consistency_check;

DROP TABLE sc10_tb_final_lu_state;

ROLLBACK TO scenario_10_tb_start;
\echo 'SC10 (Two Batches): Rolled back.'

-- Scenario 11 (SC11SB): LU with initial and overlapping segments processed in a SINGLE BATCH
\echo 'SC11 (Single Batch): LU Replace/Update with Overlapping Segments in Single Batch'
SAVEPOINT scenario_11_sb_start;

-- SC11SB Constants
\set sc11_sb_lu_tax_ident '''SC11SBLU001'''
\set sc11_sb_job_slug 'test72_sc11_sb_lu_overlap'

-- Initial Segments (equivalent to SC10TB Batch 1)
\set sc11_sb_s1_p1_from '''2023-01-01'''
\set sc11_sb_s1_p1_to   '''2023-03-31'''
\set sc11_sb_s1_p2_from '''2023-04-01'''
\set sc11_sb_s1_p2_to   '''2023-06-30'''
\set sc11_sb_s1_p3_from '''2023-07-01'''
\set sc11_sb_s1_p3_to   '''2023-09-30'''

-- Replacing/Overlapping Segments (equivalent to SC10TB Batch 2)
\set sc11_sb_s2_pA_from '''2023-02-15''' 
\set sc11_sb_s2_pA_to   '''2023-05-15'''
\set sc11_sb_s2_pB_from '''2023-05-16'''
\set sc11_sb_s2_pB_to   '''2023-08-15'''
\set sc11_sb_s2_pC_from '''2023-08-16'''
\set sc11_sb_s2_pC_to   '''2023-11-30'''

-- SC11SB Single Batch: Insert all 6 segments
\echo 'SC11 (Single Batch): Inserting all 6 LU segments'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, :'sc11_sb_job_slug', 'SC11SB LU Single Batch Overlap', 'Test 72 SC11SB', :'default_edit_comment');

-- Removed \gset for sc11_sb_upload_table and sc11_sb_data_table

SELECT format($$
    INSERT INTO public.test72_sc11_sb_lu_overlap_upload (tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, data_source_code, birth_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code) VALUES
    -- Initial Segments
    (%L, 'LU SC11SB Initial P1', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Addr SC11SB P1', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC11SB Initial P2', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Addr SC11SB P2', '1000', 'Oslo', '0301', 'NO', '01.110'),
    (%L, 'LU SC11SB Initial P3', %L, %L, '2300', 'AS', 'mi', '2023-01-01', 'Addr SC11SB P3', '1001', 'Oslo', '0301', 'NO', '01.120'),
    -- Replacing/Overlapping Segments
    (%L, 'LU SC11SB Replacing pA', %L, %L, '2300', 'AS', 'mi', '2023-01-01', 'Addr SC11SB pA', '1002', 'Oslo', '0301', 'NO', '01.130'),
    (%L, 'LU SC11SB Replacing pB', %L, %L, '2300', 'AS', 'mi', '2023-01-01', 'Addr SC11SB pB', '1002', 'Oslo', '0301', 'NO', '01.130'),
    (%L, 'LU SC11SB Replacing pC', %L, %L, '2100', 'AS', 'mi', '2023-01-01', 'Addr SC11SB pC', '1003', 'Oslo', '0301', 'NO', '01.140');
$$, -- No table variable needed here
    :'sc11_sb_lu_tax_ident', :'sc11_sb_s1_p1_from', :'sc11_sb_s1_p1_to',
    :'sc11_sb_lu_tax_ident', :'sc11_sb_s1_p2_from', :'sc11_sb_s1_p2_to',
    :'sc11_sb_lu_tax_ident', :'sc11_sb_s1_p3_from', :'sc11_sb_s1_p3_to',
    :'sc11_sb_lu_tax_ident', :'sc11_sb_s2_pA_from', :'sc11_sb_s2_pA_to',
    :'sc11_sb_lu_tax_ident', :'sc11_sb_s2_pB_from', :'sc11_sb_s2_pB_to',
    :'sc11_sb_lu_tax_ident', :'sc11_sb_s2_pC_from', :'sc11_sb_s2_pC_to'
) \gexec

-- SC11SB Process
CALL worker.process_tasks(p_queue => 'import');

-- SC11SB Verifications
\echo 'SC11 (Single Batch): Verifying _data table contents'
-- Display relevant columns from the _data table
SELECT
    row_id, founding_row_id, tax_ident, name, valid_from, valid_to, action, state, error, invalid_codes,
    CASE WHEN legal_unit_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS legal_unit_id_status,
    CASE WHEN enterprise_id IS NOT NULL THEN 'SET' ELSE 'NULL' END AS enterprise_id_status
FROM public.test72_sc11_sb_lu_overlap_data -- Hardcoded based on sc11_sb_job_slug
ORDER BY row_id;

-- Check the processing status of rows in the _data table
WITH data_check_cte AS (
    SELECT
        row_id, action, state, error -- removed operation
    FROM public.test72_sc11_sb_lu_overlap_data -- Hardcoded based on sc11_sb_job_slug
)
SELECT
    CASE
        WHEN COUNT(*) = 6
         AND SUM(CASE WHEN state = 'processed' THEN 1 ELSE 0 END) = 6
         AND SUM(CASE WHEN error IS NOT NULL AND error::TEXT <> '{}' THEN 1 ELSE 0 END) = 0
         AND SUM(CASE WHEN row_id = 1 AND action = 'insert' THEN 1 ELSE 0 END) = 1 -- removed operation check
         AND SUM(CASE WHEN row_id > 1 AND action = 'replace' THEN 1 ELSE 0 END) = 5 -- removed operation check
        THEN 'PASS: All 6 rows in _data table processed successfully with correct actions.'
        ELSE 'FAIL: _data table verification failed for SC11. ' ||
             'Total rows: ' || COUNT(*) ||
             ', Processed rows: ' || SUM(CASE WHEN state = 'processed' THEN 1 ELSE 0 END) ||
             ', Error rows: ' || SUM(CASE WHEN error IS NOT NULL AND error::TEXT <> '{}' THEN 1 ELSE 0 END) ||
             ', Row 1 action insert: ' || SUM(CASE WHEN row_id = 1 AND action = 'insert' THEN 1 ELSE 0 END) ||
             ', Subsequent action replace: ' || SUM(CASE WHEN row_id > 1 AND action = 'replace' THEN 1 ELSE 0 END)
    END as data_table_check
FROM data_check_cte;

\echo 'SC11 (Single Batch): Verifying LU (expect 4 final slices, same enterprise, all primary)'
CREATE TEMP TABLE sc11_sb_final_lu_state AS
SELECT
    lu.name,
    lu.valid_from,
    lu.valid_to,
    lu.enterprise_id,
    (SELECT ei_sub.ident FROM public.enterprise e_sub
     JOIN public.legal_unit lu_sub ON e_sub.id = lu_sub.enterprise_id AND lu_sub.primary_for_enterprise = TRUE
     JOIN public.external_ident ei_sub ON lu_sub.id = ei_sub.legal_unit_id
     JOIN public.external_ident_type eit_sub ON ei_sub.type_id = eit_sub.id AND eit_sub.code = 'tax_ident'
     WHERE e_sub.id = lu.enterprise_id
     LIMIT 1) AS enterprise_main_ident,
    lu.primary_for_enterprise,
    (SELECT COUNT(*) FROM public.legal_unit lu_check WHERE lu_check.enterprise_id = lu.enterprise_id) as slices_in_enterprise,
    (SELECT COUNT(DISTINCT lu_check.enterprise_id) FROM public.legal_unit lu_check
     JOIN public.external_ident ei_check ON ei_check.legal_unit_id = lu_check.id AND ei_check.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
     WHERE ei_check.ident = :'sc11_sb_lu_tax_ident') as distinct_enterprise_ids_for_lu
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = :'sc11_sb_lu_tax_ident'
ORDER BY lu.valid_from;

SELECT 
    name,
    valid_from,
    valid_to,
    enterprise_main_ident,
    primary_for_enterprise,
    slices_in_enterprise,
    distinct_enterprise_ids_for_lu
FROM sc11_sb_final_lu_state
ORDER BY valid_from;

\echo 'SC11 (Single Batch): Final Checks'
SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM sc11_sb_final_lu_state) = 4 THEN 'PASS: Correct number of final segments (4)'
        ELSE 'FAIL: Incorrect number of final segments. Expected 4, Got ' || (SELECT COUNT(*) FROM sc11_sb_final_lu_state)
    END as segment_count_check;

SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM sc11_sb_final_lu_state WHERE name = 'LU SC11SB Initial P1' AND valid_from = :'sc11_sb_s1_p1_from' AND valid_to = (:'sc11_sb_s2_pA_from'::date - INTERVAL '1 day')) = 1
         AND (SELECT COUNT(*) FROM sc11_sb_final_lu_state WHERE name = 'LU SC11SB Replacing pA' AND valid_from = :'sc11_sb_s2_pA_from' AND valid_to = :'sc11_sb_s2_pA_to') = 1
         AND (SELECT COUNT(*) FROM sc11_sb_final_lu_state WHERE name = 'LU SC11SB Replacing pB' AND valid_from = :'sc11_sb_s2_pB_from' AND valid_to = :'sc11_sb_s2_pB_to') = 1
         AND (SELECT COUNT(*) FROM sc11_sb_final_lu_state WHERE name = 'LU SC11SB Replacing pC' AND valid_from = :'sc11_sb_s2_pC_from' AND valid_to = :'sc11_sb_s2_pC_to') = 1
        THEN 'PASS: All 4 final segments have correct names and date ranges.'
        ELSE 'FAIL: Verification of final segment names and date ranges failed for SC11.'
    END as segment_date_name_check;

SELECT
    CASE
        WHEN (SELECT bool_and(primary_for_enterprise) FROM sc11_sb_final_lu_state) THEN 'PASS: All final segments are primary_for_enterprise'
        ELSE 'FAIL: Not all final segments are primary_for_enterprise for SC11'
    END as primary_flag_check;

SELECT
    CASE
        WHEN (SELECT distinct_enterprise_ids_for_lu FROM sc11_sb_final_lu_state LIMIT 1) = 1
        THEN 'PASS: Enterprise ID remained consistent for SC11'
        ELSE 'FAIL: Multiple enterprises found for LU in SC11. Final Enterprise Main Ident(s) for LU ' || :'sc11_sb_lu_tax_ident' || ': ' || (SELECT string_agg(DISTINCT enterprise_main_ident, ', ') FROM sc11_sb_final_lu_state)
    END as enterprise_consistency_check;

DROP TABLE sc11_sb_final_lu_state;

ROLLBACK TO scenario_11_sb_start;
\echo 'SC11 (Single Batch): Rolled back.'

\echo 'Test 72: All scenarios completed.'
ROLLBACK; -- Final rollback for the entire test

SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

\echo "Test 71: Custom Happy Path - Custom Stats (Men/Women Employees) and Custom External Ident (NIN)"
\echo "Setting up Statbus environment for test 71"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

SELECT acs.code FROM public.settings AS s JOIN activity_category_standard AS acs ON s.activity_category_standard_id = acs.id;

\echo "Ensure sample tags are loaded"
INSERT INTO public.tag (path, name, type) VALUES
('TestTag', 'Test Tag Parent', 'custom'),
('TestTag.LU', 'Legal Unit Test Tag', 'custom'),
('TestTag.LU.Updated', 'Legal Unit Updated Test Tag', 'custom'),
('TestTag.ES', 'Establishment Test Tag Parent', 'custom'),
('TestTag.ES.Formal', 'Formal Establishment Test Tag', 'custom'),
('TestTag.ES.Formal.Updated', 'Formal Establishment Updated Test Tag', 'custom'),
('TestTag.ES.Informal', 'Informal Establishment Test Tag', 'custom'),
('TestTag.ES.Informal.Updated', 'Informal Establishment Updated Test Tag', 'custom')
ON CONFLICT (path) DO NOTHING;

\echo "Setup custom stat definitions and external ident types for Test 71"
INSERT INTO public.stat_definition (code, name, type, frequency, description, archived, priority) VALUES
('men_employees', 'Number of Men Employees', 'int', 'yearly', 'Number of men employees in the unit', false, 10),
('women_employees', 'Number of Women Employees', 'int', 'yearly', 'Number of women employees in the unit', false, 11)
ON CONFLICT (code) DO UPDATE SET archived = false; -- Ensure they are active for this test

INSERT INTO public.external_ident_type (code, name, description, priority, archived) VALUES
('nin_ident', 'National Identity Number', 'Custom NIN ident for test 71', 3, false)
ON CONFLICT (code) DO UPDATE SET archived = false; -- Ensure it's active

-- Archive stat_ident for this test to ensure nin_ident is picked up where applicable
UPDATE public.external_ident_type SET archived = true WHERE code = 'stat_ident';

\echo "Define custom import definitions for Test 71"
DO $$
DECLARE
    v_lu_def_id INT;
    v_es_lu_def_id INT;
    v_es_no_lu_def_id INT;
    v_lu_step_ids INT[];
    v_es_formal_step_ids INT[];
    v_es_informal_step_ids INT[];
    v_lu_source_cols TEXT[][] := ARRAY[
        ['tax_ident', '1'], ['nin_ident', '2'], ['valid_from', '3'], ['valid_to', '4'], ['name', '5'],
        ['birth_date', '6'], ['sector_code', '7'], ['status_code', '8'], ['legal_form_code', '9'],
        ['data_source_code', '10'],
        ['physical_address_part1', '11'], ['physical_country_iso_2', '12'], ['physical_postcode', '13'], ['physical_region_code', '14'],
        ['primary_activity_category_code', '15'],
        ['men_employees', '16'], ['women_employees', '17'], ['tag_path', '18'], ['email_address', '19']
    ];
    v_es_source_cols TEXT[][] := ARRAY[
        ['tax_ident', '1'], ['nin_ident', '2'], ['legal_unit_tax_ident', '3'], ['valid_from', '4'], ['valid_to', '5'], ['name', '6'], ['status_code', '7'],
        ['physical_address_part1', '8'], ['physical_country_iso_2', '9'], ['physical_postcode', '10'], ['physical_region_code', '11'],
        ['primary_activity_category_code', '12'],
        ['men_employees', '13'], ['women_employees', '14'], ['tag_path', '15'],
        ['email_address', '16']
    ];
    v_es_no_lu_source_cols TEXT[][] := ARRAY[
        ['tax_ident', '1'], ['nin_ident', '2'], ['valid_from', '3'], ['valid_to', '4'], ['name', '5'], ['status_code', '6'],
        ['physical_address_part1', '7'], ['physical_country_iso_2', '8'], ['physical_postcode', '9'], ['physical_region_code', '10'],
        ['primary_activity_category_code', '11'],
        ['men_employees', '12'], ['women_employees', '13'], ['tag_path', '14'],
        ['email_address', '15']
    ];
    col_rec TEXT[];
BEGIN
    -- Define step ID arrays for different import modes
    SELECT array_agg(s.id) INTO v_lu_step_ids
    FROM public.import_step s
    WHERE s.code IN (
        'external_idents', 'data_source', 'enterprise_link_for_legal_unit', 'valid_time', 'status', 'legal_unit',
        'physical_location', 'postal_location', 'primary_activity', 'secondary_activity',
        'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'
    );

    SELECT array_agg(s.id) INTO v_es_formal_step_ids
    FROM public.import_step s
    WHERE s.code IN (
        'external_idents', 'data_source', 'link_establishment_to_legal_unit', 'enterprise_link_for_establishment', 'valid_time', 'status', 'establishment',
        'physical_location', 'postal_location', 'primary_activity', 'secondary_activity',
        'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'
    );

    SELECT array_agg(s.id) INTO v_es_informal_step_ids
    FROM public.import_step s
    WHERE s.code IN (
        'external_idents', 'data_source', 'enterprise_link_for_establishment', 'valid_time', 'status', 'establishment',
        'physical_location', 'postal_location', 'primary_activity', 'secondary_activity',
        'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'
    );

    -- Create Legal Unit Import Definition for Test 71
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid)
    VALUES ('legal_unit_custom_test71', 'Test 71 LU Custom', 'Imports LUs with NIN and custom stats', 'insert_or_replace', 'legal_unit', 'source_columns', false)
    RETURNING id INTO v_lu_def_id;

    INSERT INTO public.import_definition_step (definition_id, step_id)
    SELECT v_lu_def_id, unnest(v_lu_step_ids);

    FOREACH col_rec SLICE 1 IN ARRAY v_lu_source_cols LOOP
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        VALUES (v_lu_def_id, col_rec[1], col_rec[2]::INT);
    END LOOP;

    INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id)
    SELECT d.id, sc.id, dc.id
    FROM public.import_definition d
    JOIN public.import_source_column sc ON sc.definition_id = d.id
    JOIN public.import_definition_step ds ON ds.definition_id = d.id
    JOIN public.import_data_column dc ON dc.step_id = ds.step_id AND replace(dc.column_name, '_raw', '') = sc.column_name AND dc.purpose = 'source_input'
    WHERE d.id = v_lu_def_id;
    UPDATE public.import_definition SET valid = true WHERE id = v_lu_def_id;

    -- Create Establishment (for LU) Import Definition for Test 71
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid)
    VALUES ('establishment_for_lu_custom_test71', 'Test 71 ES for LU Custom', 'Imports ES for LU with NIN and custom stats', 'insert_or_replace', 'establishment_formal', 'source_columns', false)
    RETURNING id INTO v_es_lu_def_id;

    INSERT INTO public.import_definition_step (definition_id, step_id)
    SELECT v_es_lu_def_id, unnest(v_es_formal_step_ids);

    FOREACH col_rec SLICE 1 IN ARRAY v_es_source_cols LOOP
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        VALUES (v_es_lu_def_id, col_rec[1], col_rec[2]::INT);
    END LOOP;

    INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id)
    SELECT d.id, sc.id, dc.id
    FROM public.import_definition d
    JOIN public.import_source_column sc ON sc.definition_id = d.id
    JOIN public.import_definition_step ds ON ds.definition_id = d.id
    JOIN public.import_data_column dc ON dc.step_id = ds.step_id AND replace(dc.column_name, '_raw', '') = sc.column_name AND dc.purpose = 'source_input'
    WHERE d.id = v_es_lu_def_id;
    UPDATE public.import_definition SET valid = true WHERE id = v_es_lu_def_id;

    -- Create Establishment (without LU) Import Definition for Test 71
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid)
    VALUES ('establishment_without_lu_custom_test71', 'Test 71 ES no LU Custom', 'Imports ES no LU with NIN and custom stats', 'insert_or_replace', 'establishment_informal', 'source_columns', false)
    RETURNING id INTO v_es_no_lu_def_id;

    INSERT INTO public.import_definition_step (definition_id, step_id)
    SELECT v_es_no_lu_def_id, unnest(v_es_informal_step_ids);

    FOREACH col_rec SLICE 1 IN ARRAY v_es_no_lu_source_cols LOOP
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        VALUES (v_es_no_lu_def_id, col_rec[1], col_rec[2]::INT);
    END LOOP;

    INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id)
    SELECT d.id, sc.id, dc.id
    FROM public.import_definition d
    JOIN public.import_source_column sc ON sc.definition_id = d.id
    JOIN public.import_definition_step ds ON ds.definition_id = d.id
    JOIN public.import_data_column dc ON dc.step_id = ds.step_id AND replace(dc.column_name, '_raw', '') = sc.column_name AND dc.purpose = 'source_input'
    WHERE d.id = v_es_no_lu_def_id;
    UPDATE public.import_definition SET valid = true WHERE id = v_es_no_lu_def_id;

END $$;


SAVEPOINT main_test_71_start;
\echo "Initial counts before any test block for Test 71"
SELECT
    (SELECT COUNT(*) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(*) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(*) FROM public.enterprise) AS enterprise_count;

--------------------------------------------------------------------------------
-- Scenario 71.A: Legal Unit - Custom Stats and NIN
--------------------------------------------------------------------------------
SAVEPOINT scenario_71_a_lu_lifecycle;
\echo "Scenario 71.A: Legal Unit - Custom Stats and NIN (LU-71A)"

-- Sub-Scenario 71.A.1: Initial LU Import (1 Row)
\echo "Sub-Scenario 71.A.1: Initial LU Import for LU-71A"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_custom_test71';
    IF v_definition_id IS NULL THEN RAISE EXCEPTION 'Import definition legal_unit_custom_test71 not found.'; END IF;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_71_a1_lu', 'Test 71.A.1: LU-71A Initial', 'Test 71.A.1');
END $$;

\echo '--- Debugging Schema for Job import_71_a1_lu ---'
\d+ public.import_71_a1_lu_data
\echo '------------------------------------------'
INSERT INTO public.import_71_a1_lu_upload(
    tax_ident, nin_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, sector_code, legal_form_code, email_address, men_employees, women_employees, tag_path
) VALUES (
    '71A000001', 'NIN71A001', 'LU-71A Period 1', '2023-01-01', '2023-03-31', 'Addr 1 LU-71A', 'NO', '1001', '0301',
    '01.110', '2100', 'AS', 'lu71a_p1@example.com', '6', '4', 'TestTag.LU'
);
CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_71_a1_lu:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_71_a1_lu';
\echo "Data table for import_71_a1_lu:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, nin_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_71_a1_lu_data ORDER BY row_id;

\echo "Verification for LU-71A ('71A000001') after Sub-Scenario 71.A.1 (all segments shown):"
\echo "Legal Unit External Idents (tax_ident, nin_ident):"
SELECT lu.name, ei.ident as tax_ident, ei_nin.ident as nin_ident, sec.code as sector_code, lf.code as legal_form_code, lu.valid_from, lu.valid_to
FROM public.legal_unit lu
JOIN public.external_ident ei ON lu.id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.external_ident ei_nin ON lu.id = ei_nin.legal_unit_id AND ei_nin.type_id = (SELECT id FROM external_ident_type WHERE code='nin_ident')
LEFT JOIN public.sector sec ON lu.sector_id = sec.id
LEFT JOIN public.legal_form lf ON lu.legal_form_id = lf.id
WHERE ei.ident = '71A000001' ORDER BY lu.valid_from, lu.valid_to;
\echo "Stat (Men/Women Employees):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '71A000001' AND sd.code IN ('men_employees', 'women_employees') ORDER BY sfu.valid_from, sfu.valid_to, sd.code;

-- Sub-Scenario 71.A.2: First Update (Change LU Name, NIN, Men Employees)
\echo "Sub-Scenario 71.A.2: Update LU-71A (Name, NIN, Men Employees)"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_custom_test71';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_71_a2_lu', 'Test 71.A.2: LU-71A Update 1', 'Test 71.A.2');
END $$;
INSERT INTO public.import_71_a2_lu_upload(
    tax_ident, nin_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, sector_code, legal_form_code, email_address, men_employees, women_employees, tag_path
) VALUES (
    '71A000001', 'NIN71A001', 'LU-71A Period 2 Updated Name', '2023-04-01', '2023-06-30', 'Addr 1 LU-71A', 'NO', '1001', '0301',
    '01.110', '2100', 'AS', 'lu71a_p1@example.com', '7', '4', 'TestTag.LU' -- Women employees, address, etc. unchanged. NIN kept same.
);

CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_71_a2_lu:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_71_a2_lu';
\echo "Data table for import_71_a2_lu:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, nin_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_71_a2_lu_data ORDER BY row_id;

\echo "Verification for LU-71A ('71A000001') after Sub-Scenario 71.A.2 (all segments shown):"

\echo "Legal Unit External Idents (tax_ident, nin_ident - nin updated in latest segment):"
SELECT lu.name, ei.ident as tax_ident, ei_nin.ident as nin_ident, sec.code as sector_code, lf.code as legal_form_code, lu.valid_from, lu.valid_to
FROM public.legal_unit lu
JOIN public.external_ident ei ON lu.id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.external_ident ei_nin ON lu.id = ei_nin.legal_unit_id AND ei_nin.type_id = (SELECT id FROM external_ident_type WHERE code='nin_ident')
LEFT JOIN public.sector sec ON lu.sector_id = sec.id
LEFT JOIN public.legal_form lf ON lu.legal_form_id = lf.id
WHERE ei.ident = '71A000001' ORDER BY lu.valid_from, lu.valid_to;

\echo "Stat (Men/Women Employees - men_employees updated in latest segment):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '71A000001' AND sd.code IN ('men_employees', 'women_employees') ORDER BY sfu.valid_from, sfu.valid_to, sd.code;


\echo "Consolidated Statistical Unit view for LU-71A (71A000001) across all periods:"
CALL worker.process_tasks(p_queue => 'analytics');
SELECT
    su.name, su.valid_from, su.valid_to,
    su.external_idents->>'tax_ident' as tax_ident, su.external_idents->>'nin_ident' as nin_ident,
    su.stats->>'men_employees' as men_employees, su.stats->>'women_employees' as women_employees, su.tag_paths
FROM public.statistical_unit su
WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = '71A000001'
ORDER BY su.valid_from, su.valid_to;

ROLLBACK TO scenario_71_a_lu_lifecycle;

--------------------------------------------------------------------------------
-- Scenario 71.B: Formal Establishment - Custom Stats and NIN
--------------------------------------------------------------------------------
SAVEPOINT scenario_71_b_formal_es_lifecycle;
\echo "Scenario 71.B: Formal Establishment - Custom Stats and NIN (ES-71B)"
-- First, create a stable Legal Unit for the Formal Establishment to link to.
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_custom_test71';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_71_b_lu_for_es', 'Test 71.B: Base LU for Formal ES', 'Test 71.B');
END $$;
INSERT INTO public.import_71_b_lu_for_es_upload(tax_ident, nin_ident, name, valid_from, valid_to, sector_code, legal_form_code, primary_activity_category_code) VALUES
('71B000000', 'NIN_LU_FOR_ES_71B', 'Base LU for ES-71B', '2023-01-01', '2023-12-31', '2100', 'AS', '00.000');
CALL worker.process_tasks(p_queue => 'import');

-- Sub-Scenario 71.B.1: Initial Formal ES Import
\echo "Sub-Scenario 71.B.1: Initial Formal ES Import for ES-71B"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'establishment_for_lu_custom_test71';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_71_b1_es', 'Test 71.B.1: ES-71B Initial', 'Test 71.B.1');
END $$;
INSERT INTO public.import_71_b1_es_upload(
    tax_ident, nin_ident, legal_unit_tax_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, email_address, men_employees, women_employees, tag_path
) VALUES (
    'E71B00001', 'NIN_ES_71B001', '71B000000', 'ES-71B Period 1', '2023-01-01', '2023-03-31', 'Addr 1 ES-71B', 'NO', '2001', '0301',
    '02.110', 'es71b_p1@example.com', '3', '2', 'TestTag.ES.Formal'
);
CALL worker.process_tasks(p_queue => 'import');

\echo "Verification for ES-71B ('E71B00001') after Sub-Scenario 71.B.1 (all segments shown):"
\echo "Establishment External Idents (tax_ident, nin_ident):"
SELECT est.name, ei.ident as tax_ident, ei_nin.ident as nin_ident, lu_ei.ident as legal_unit_tax_ident, est.valid_from, est.valid_to
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.external_ident ei_nin ON est.id = ei_nin.establishment_id AND ei_nin.type_id = (SELECT id FROM external_ident_type WHERE code='nin_ident')
LEFT JOIN public.legal_unit lu ON est.legal_unit_id = lu.id
LEFT JOIN public.external_ident lu_ei ON lu.id = lu_ei.legal_unit_id AND lu_ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E71B00001' ORDER BY est.valid_from, est.valid_to;
\echo "Stat (Men/Women Employees):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E71B00001' AND sd.code IN ('men_employees', 'women_employees') ORDER BY sfu.valid_from, sfu.valid_to, sd.code;

\echo "Consolidated Statistical Unit view for ES-71B (E71B00001) across all periods:"
CALL worker.process_tasks(p_queue => 'analytics');
SELECT
    su.name, su.valid_from, su.valid_to,
    su.external_idents->>'tax_ident' as tax_ident, su.external_idents->>'nin_ident' as nin_ident,
    su.external_idents->>'legal_unit_tax_ident' as legal_unit_tax_ident,
    su.stats->>'men_employees' as men_employees, su.stats->>'women_employees' as women_employees, su.tag_paths
FROM public.statistical_unit su
WHERE su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = 'E71B00001'
ORDER BY su.valid_from, su.valid_to;

ROLLBACK TO scenario_71_b_formal_es_lifecycle;

--------------------------------------------------------------------------------
-- Scenario 71.C: Informal Establishment - Custom Stats and NIN
--------------------------------------------------------------------------------
SAVEPOINT scenario_71_c_informal_es_lifecycle;
\echo "Scenario 71.C: Informal Establishment - Custom Stats and NIN (ES-71C)"

-- Sub-Scenario 71.C.1: Initial Informal ES Import
\echo "Sub-Scenario 71.C.1: Initial Informal ES Import for ES-71C"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'establishment_without_lu_custom_test71';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_71_c1_es', 'Test 71.C.1: ES-71C Initial', 'Test 71.C.1');
END $$;
INSERT INTO public.import_71_c1_es_upload(
    tax_ident, nin_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, email_address, men_employees, women_employees, tag_path
) VALUES (
    'E71C00001', 'NIN_ES_71C001', 'ES-71C Period 1', '2023-01-01', '2023-03-31', 'Addr 1 ES-71C', 'NO', '3001', '0301',
    '03.110', 'es71c_p1@example.com', '1', '1', 'TestTag.ES.Informal'
);
CALL worker.process_tasks(p_queue => 'import');

\echo "Verification for ES-71C ('E71C00001') after Sub-Scenario 71.C.1 (all segments shown):"
\echo "Establishment External Idents (tax_ident, nin_ident):"
SELECT est.name, ei.ident as tax_ident, ei_nin.ident as nin_ident, est.valid_from, est.valid_to
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.external_ident ei_nin ON est.id = ei_nin.establishment_id AND ei_nin.type_id = (SELECT id FROM external_ident_type WHERE code='nin_ident')
WHERE ei.ident = 'E71C00001' ORDER BY est.valid_from, est.valid_to;
\echo "Stat (Men/Women Employees):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E71C00001' AND sd.code IN ('men_employees', 'women_employees') ORDER BY sfu.valid_from, sfu.valid_to, sd.code;

\echo "Consolidated Statistical Unit view for ES-71C (E71C00001) across all periods:"
CALL worker.process_tasks(p_queue => 'analytics');
SELECT
    su.name, su.valid_from, su.valid_to,
    su.external_idents->>'tax_ident' as tax_ident, su.external_idents->>'nin_ident' as nin_ident,
    su.stats->>'men_employees' as men_employees, su.stats->>'women_employees' as women_employees, su.tag_paths
FROM public.statistical_unit su
WHERE su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = 'E71C00001'
ORDER BY su.valid_from, su.valid_to;

ROLLBACK TO scenario_71_c_informal_es_lifecycle;

-- Scenario 71.D: import_as_null Configuration - Data Cleaning with Null Representations
SAVEPOINT scenario_71_d_import_as_null;
\echo "Scenario 71.D: Testing import_as_null configuration for data cleaning"

\echo "Create import job for testing null representations (NA, N/A, NULL, NONE, empty string)"
DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_custom_test71';
    IF v_definition_id IS NULL THEN RAISE EXCEPTION 'Import definition legal_unit_custom_test71 not found.'; END IF;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_71_d_null_handling', 'Test 71.D: Null value handling', 'Test import_as_null');
END $$;

\echo "Insert test data with various null representations"
INSERT INTO public.import_71_d_null_handling_upload(
    tax_ident, nin_ident, name, birth_date, valid_from, valid_to, physical_region_code, physical_country_iso_2,
    primary_activity_category_code, legal_form_code, sector_code, men_employees, women_employees, data_source_code
) VALUES
-- Row 1: Normal values (no nulls)
('71D00001', 'NIN71D01', 'Company With Data', '2020-01-01', '2024-01-01', 'infinity', '0301', 'NO', '01.110', 'AS', '2100', '30', '20', 'nlr'),
-- Row 2: Empty strings (should become NULL)
('71D00002', '', 'Company Empty Strings', '2020-01-01', '2024-01-01', 'infinity', '', 'NO', '01.110', 'AS', '2100', '', '', 'nlr'),
-- Row 3: 'NA' uppercase (should become NULL)
('71D00003', 'NA', 'Company NA Uppercase', '2020-01-01', '2024-01-01', 'infinity', 'NA', 'NO', '01.110', 'AS', '2100', 'NA', 'NA', 'nlr'),
-- Row 4: 'na' lowercase (should become NULL, case-insensitive)
('71D00004', 'na', 'Company NA Lowercase', '2020-01-01', '2024-01-01', 'infinity', 'na', 'NO', '01.110', 'AS', '2100', 'na', 'na', 'nlr'),
-- Row 5: 'N/A' uppercase (should become NULL)
('71D00005', 'N/A', 'Company N/A Uppercase', '2020-01-01', '2024-01-01', 'infinity', 'N/A', 'NO', '01.110', 'AS', '2100', 'N/A', 'N/A', 'nlr'),
-- Row 6: 'n/a' lowercase (should become NULL, case-insensitive)
('71D00006', 'n/a', 'Company N/A Lowercase', '2020-01-01', '2024-01-01', 'infinity', 'n/a', 'NO', '01.110', 'AS', '2100', 'n/a', 'n/a', 'nlr'),
-- Row 7: 'NULL' uppercase (should become NULL)
('71D00007', 'NULL', 'Company NULL Uppercase', '2020-01-01', '2024-01-01', 'infinity', 'NULL', 'NO', '01.110', 'AS', '2100', 'NULL', 'NULL', 'nlr'),
-- Row 8: 'null' lowercase (should become NULL, case-insensitive)
('71D00008', 'null', 'Company NULL Lowercase', '2020-01-01', '2024-01-01', 'infinity', 'null', 'NO', '01.110', 'AS', '2100', 'null', 'null', 'nlr'),
-- Row 9: 'Null' mixed case (should become NULL, case-insensitive)
('71D00009', 'Null', 'Company NULL Mixed', '2020-01-01', '2024-01-01', 'infinity', 'Null', 'NO', '01.110', 'AS', '2100', 'Null', 'Null', 'nlr'),
-- Row 10: 'NONE' uppercase (should become NULL)
('71D00010', 'NONE', 'Company NONE Uppercase', '2020-01-01', '2024-01-01', 'infinity', 'NONE', 'NO', '01.110', 'AS', '2100', 'NONE', 'NONE', 'nlr'),
-- Row 11: 'none' lowercase (should become NULL, case-insensitive)
('71D00011', 'none', 'Company NONE Lowercase', '2020-01-01', '2024-01-01', 'infinity', 'none', 'NO', '01.110', 'AS', '2100', 'none', 'none', 'nlr'),
-- Row 12: 'None' mixed case (should become NULL, case-insensitive)
('71D00012', 'None', 'Company NONE Mixed', '2020-01-01', '2024-01-01', 'infinity', 'None', 'NO', '01.110', 'AS', '2100', 'None', 'None', 'nlr'),
-- Row 13: Non-matching value (should NOT become NULL - 'NULLIFY' is not in the list)
('71D00013', 'NULLIFY', 'Company With NULLIFY', '2020-01-01', '2024-01-01', 'infinity', 'NULLIFY', 'NO', '01.110', 'AS', '2100', 'NULLIFY', 'NULLIFY', 'nlr');

\echo "Process the import job"
CALL worker.process_tasks(p_queue => 'import');

\echo "Check import job status - should be finished with all rows processed"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_71_d_null_handling_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job WHERE slug = 'import_71_d_null_handling';

\echo "Verify null conversion in data table - check raw values vs processed values"
SELECT 
    row_id,
    tax_ident_raw,
    nin_ident_raw,
    physical_region_code_raw,
    men_employees_raw,
    women_employees_raw,
    CASE WHEN nin_ident_raw IS NULL THEN '<NULL>' ELSE nin_ident_raw END as nin_check,
    CASE WHEN physical_region_code_raw IS NULL THEN '<NULL>' ELSE physical_region_code_raw END as region_check,
    CASE WHEN men_employees_raw IS NULL THEN '<NULL>' ELSE men_employees_raw END as men_emp_check,
    state
FROM public.import_71_d_null_handling_data
ORDER BY row_id;

\echo "Verify that non-matching values were NOT converted to NULL"
SELECT COUNT(*) as non_null_count
FROM public.import_71_d_null_handling_data
WHERE nin_ident_raw = 'NULLIFY' AND physical_region_code_raw = 'NULLIFY';

\echo "Count rows with NULL values after conversion (should be 11 rows with NULLs, 1 with 'NULLIFY', 1 with actual data)"
SELECT 
    COUNT(*) FILTER (WHERE nin_ident_raw IS NULL) as null_nin_count,
    COUNT(*) FILTER (WHERE nin_ident_raw IS NOT NULL AND nin_ident_raw != 'NULLIFY') as non_null_nin_count,
    COUNT(*) FILTER (WHERE nin_ident_raw = 'NULLIFY') as nullify_count
FROM public.import_71_d_null_handling_data;

ROLLBACK TO scenario_71_d_import_as_null;


\echo "Final counts after all test blocks for Test 71 (should be same as initial due to rollbacks)"
SELECT
    (SELECT COUNT(*) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(*) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(*) FROM public.enterprise) AS enterprise_count;

ROLLBACK TO main_test_71_start;
\echo "Test 71 completed and rolled back to main start."



ROLLBACK; -- Final rollback for the entire transaction

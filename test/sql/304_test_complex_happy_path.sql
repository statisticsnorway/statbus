BEGIN;

\i test/setup.sql

\echo "Test 69: Happy Path - Complex Temporal Attribute Changes and Slicing"
\echo "Setting up Statbus environment for test 69"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

\echo "Ensure sample tags and stat definitions are loaded"
-- Minimal tags for testing
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

-- Minimal stat definition for testing
-- 'employees' and 'turnover' are default. This test uses the default 'employees'.
-- Custom stats like 'men_employees', 'women_employees' are tested in 71_test_custom_happy_path.sql


SAVEPOINT main_test_69_start;
\echo "Initial counts before any test block for Test 69"
SELECT
    (SELECT COUNT(*) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(*) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(*) FROM public.enterprise) AS enterprise_count;

--------------------------------------------------------------------------------
-- Scenario 69.A: Legal Unit - Full Attribute Lifecycle
--------------------------------------------------------------------------------
SAVEPOINT scenario_69_a_lu_lifecycle;
\echo "Scenario 69.A: Legal Unit - Full Attribute Lifecycle (LU-69A)"

-- Sub-Scenario 69.A.1: Initial LU Import (1 Row)
\echo "Sub-Scenario 69.A.1: Initial LU Import for LU-69A"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    IF v_definition_id IS NULL THEN RAISE EXCEPTION 'Import definition legal_unit_source_dates not found.'; END IF;
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_69_a1_lu', 'Test 69.A.1: LU-69A Initial', 'Test 69.A.1');
END $$;
INSERT INTO public.import_69_a1_lu_upload(
    tax_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, sector_code, legal_form_code, email_address, employees, tag_path
) VALUES (
    '69A000001', 'LU-69A Period 1', '2023-01-01', '2023-03-31', 'Addr 1 LU-69A', 'NO', '1001', '0301',
    '01.110', 'S1', 'AS', 'lu69a_p1@example.com', '10', 'TestTag.LU'
);
CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_69_a1_lu:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_69_a1_lu';
\echo "Data table for import_69_a1_lu:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_69_a1_lu_data ORDER BY row_id;

\echo "Verification for LU-69A ('69A000001') after Sub-Scenario 69.A.1 (all segments shown):"
\echo "Legal Unit:"
SELECT lu.name, ei.ident, lu.enterprise_id IS NOT NULL as has_enterprise, lu.primary_for_enterprise, sec.code as sector_code, lf.code as legal_form_code, lu.valid_from, lu.valid_to
FROM public.legal_unit lu
JOIN public.external_ident ei ON lu.id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.sector sec ON lu.sector_id = sec.id
LEFT JOIN public.legal_form lf ON lu.legal_form_id = lf.id
WHERE ei.ident = '69A000001' ORDER BY lu.valid_from, lu.valid_to;
\echo "Location:"
SELECT loc.address_part1, loc.postcode, r.code as region_code, loc.valid_from, loc.valid_to
FROM public.location loc
JOIN public.external_ident ei ON loc.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.region r ON loc.region_id = r.id
WHERE ei.ident = '69A000001' AND loc.type='physical' ORDER BY loc.valid_from, loc.valid_to;
\echo "Activity:"
SELECT ac.code as activity_code, act.type, act.valid_from, act.valid_to
FROM public.activity act
JOIN public.activity_category ac ON act.category_id = ac.id
JOIN public.external_ident ei ON act.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001' AND act.type='primary' ORDER BY act.valid_from, act.valid_to;
\echo "Contact:"
SELECT con.email_address, con.valid_from, con.valid_to
FROM public.contact con
JOIN public.external_ident ei ON con.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001' ORDER BY con.valid_from, con.valid_to;
\echo "Stat (Employees):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001' AND sd.code = 'employees' ORDER BY sfu.valid_from, sfu.valid_to, sd.code;
\echo "Tag:"
SELECT lu.name as lu_name, lu.valid_from AS lu_valid_from, lu.valid_to AS lu_valid_to,
       (SELECT COALESCE(array_agg(t_sub.path ORDER BY t_sub.path), '{}')
        FROM public.tag_for_unit tfu_sub
        JOIN public.tag t_sub ON tfu_sub.tag_id = t_sub.id
        WHERE tfu_sub.legal_unit_id = lu.id) as tag_paths
FROM public.legal_unit lu
JOIN public.external_ident ei ON lu.id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001'
ORDER BY lu.valid_from, lu.valid_to;

-- Sub-Scenario 69.A.2: First Update (Change LU Name, Address, Activity)
\echo "Sub-Scenario 69.A.2: Update LU-69A (Name, Address, Activity)"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_69_a2_lu', 'Test 69.A.2: LU-69A Update 1', 'Test 69.A.2');
END $$;
INSERT INTO public.import_69_a2_lu_upload(
    tax_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, sector_code, legal_form_code, email_address, employees, tag_path
) VALUES (
    '69A000001', 'LU-69A Period 2 Updated Name', '2023-04-01', '2023-06-30', 'Addr 2 LU-69A Updated', 'NO', '1002', '0301', -- Changed postcode too
    '01.120', 'S1', 'AS', 'lu69a_p1@example.com', '10', 'TestTag.LU' -- Sector, email, employees, tag unchanged
);
CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_69_a2_lu:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_69_a2_lu';
\echo "Data table for import_69_a2_lu:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_69_a2_lu_data ORDER BY row_id;

\echo "Verification for LU-69A ('69A000001') after Sub-Scenario 69.A.2 (all segments shown):"
\echo "Legal Unit:"
SELECT lu.name, ei.ident, sec.code as sector_code, lf.code as legal_form_code, lu.valid_from, lu.valid_to
FROM public.legal_unit lu
JOIN public.external_ident ei ON lu.id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.sector sec ON lu.sector_id = sec.id
LEFT JOIN public.legal_form lf ON lu.legal_form_id = lf.id
WHERE ei.ident = '69A000001' ORDER BY lu.valid_from, lu.valid_to;
\echo "Location:"
SELECT loc.address_part1, loc.postcode, r.code as region_code, loc.valid_from, loc.valid_to
FROM public.location loc
JOIN public.external_ident ei ON loc.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.region r ON loc.region_id = r.id
WHERE ei.ident = '69A000001' AND loc.type='physical' ORDER BY loc.valid_from, loc.valid_to;
\echo "Activity:"
SELECT ac.code as activity_code, act.type, act.valid_from, act.valid_to
FROM public.activity act
JOIN public.activity_category ac ON act.category_id = ac.id
JOIN public.external_ident ei ON act.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001' AND act.type='primary' ORDER BY act.valid_from, act.valid_to;
\echo "Contact (should be unchanged from A.1, possibly extended):"
SELECT con.email_address, con.valid_from, con.valid_to
FROM public.contact con
JOIN public.external_ident ei ON con.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001' ORDER BY con.valid_from, con.valid_to;
\echo "Stat (Employees - should be unchanged from A.1, possibly extended):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001' AND sd.code = 'employees' ORDER BY sfu.valid_from, sfu.valid_to, sd.code;
\echo "Tag (should be unchanged from A.1, possibly extended):"
SELECT lu.name as lu_name, lu.valid_from AS lu_valid_from, lu.valid_to AS lu_valid_to,
       (SELECT COALESCE(array_agg(t_sub.path ORDER BY t_sub.path), '{}')
        FROM public.tag_for_unit tfu_sub
        JOIN public.tag t_sub ON tfu_sub.tag_id = t_sub.id
        WHERE tfu_sub.legal_unit_id = lu.id) as tag_paths
FROM public.legal_unit lu
JOIN public.external_ident ei ON lu.id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001'
ORDER BY lu.valid_from, lu.valid_to;

-- Sub-Scenario 69.A.3: Second Update (Change Sector, Email, Employees, Tag)
\echo "Sub-Scenario 69.A.3: Update LU-69A (Sector, Email, Employees, Tag)"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_69_a3_lu', 'Test 69.A.3: LU-69A Update 2', 'Test 69.A.3');
END $$;
INSERT INTO public.import_69_a3_lu_upload(
    tax_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, sector_code, legal_form_code, email_address, employees, tag_path
) VALUES (
    '69A000001', 'LU-69A Period 2 Updated Name', '2023-07-01', '2023-09-30', 'Addr 2 LU-69A Updated', 'NO', '1002', '0301',
    '01.120', '2100', 'AS', 'lu69a_p3_updated@example.com', '15', 'TestTag.LU.Updated' -- Name, address, activity unchanged from A.2
);

--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

\echo "Job status for import_69_a3_lu:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_69_a3_lu';
\echo "Data table for import_69_a3_lu:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_69_a3_lu_data ORDER BY row_id;

\echo "Verification for LU-69A ('69A000001') after Sub-Scenario 69.A.3 (all segments shown):"
\echo "Legal Unit (expect sector 2100 in latest segment):"
SELECT lu.name, ei.ident, sec.code as sector_code, lf.code as legal_form_code, lu.valid_from, lu.valid_to
FROM public.legal_unit lu
JOIN public.external_ident ei ON lu.id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.sector sec ON lu.sector_id = sec.id
LEFT JOIN public.legal_form lf ON lu.legal_form_id = lf.id
WHERE ei.ident = '69A000001' ORDER BY lu.valid_from, lu.valid_to;
\echo "Location (should be unchanged from A.2, possibly extended):"
SELECT loc.address_part1, loc.postcode, r.code as region_code, loc.valid_from, loc.valid_to
FROM public.location loc
JOIN public.external_ident ei ON loc.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.region r ON loc.region_id = r.id
WHERE ei.ident = '69A000001' AND loc.type='physical' ORDER BY loc.valid_from, loc.valid_to;
\echo "Activity (should be unchanged from A.2, possibly extended):"
SELECT ac.code as activity_code, act.type, act.valid_from, act.valid_to
FROM public.activity act
JOIN public.activity_category ac ON act.category_id = ac.id
JOIN public.external_ident ei ON act.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001' AND act.type='primary' ORDER BY act.valid_from, act.valid_to;
\echo "Contact (expect new email):"
SELECT con.email_address, con.valid_from, con.valid_to
FROM public.contact con
JOIN public.external_ident ei ON con.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001' ORDER BY con.valid_from, con.valid_to;
\echo "Stat (Employees - expect new value 15 in latest segment):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.legal_unit_id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001' AND sd.code = 'employees' ORDER BY sfu.valid_from, sfu.valid_to, sd.code;
\echo "Tag (expect new tag TestTag.LU.Updated alongside existing):"
SELECT lu.name as lu_name, lu.valid_from AS lu_valid_from, lu.valid_to AS lu_valid_to,
       (SELECT COALESCE(array_agg(t_sub.path ORDER BY t_sub.path), '{}')
        FROM public.tag_for_unit tfu_sub
        JOIN public.tag t_sub ON tfu_sub.tag_id = t_sub.id
        WHERE tfu_sub.legal_unit_id = lu.id) as tag_paths
FROM public.legal_unit lu
JOIN public.external_ident ei ON lu.id = ei.legal_unit_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = '69A000001'
ORDER BY lu.valid_from, lu.valid_to;

\echo "Consolidated Statistical Unit view for LU-69A (69A000001) across all periods:"
CALL worker.process_tasks(p_queue => 'analytics');
SELECT
    su.name, su.valid_from, su.valid_to,
    su.physical_address_part1, su.physical_postcode, su.physical_region_code,
    su.primary_activity_category_code, su.sector_code, su.legal_form_code,
    su.email_address, su.stats->>'employees' as employees, su.tag_paths
FROM public.statistical_unit su
WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = '69A000001'
ORDER BY su.valid_from, su.valid_to;

ROLLBACK TO scenario_69_a_lu_lifecycle;

--------------------------------------------------------------------------------
-- Scenario 69.B: Formal Establishment - Full Attribute Lifecycle
--------------------------------------------------------------------------------
SAVEPOINT scenario_69_b_formal_es_lifecycle;
\echo "Scenario 69.B: Formal Establishment - Full Attribute Lifecycle (ES-69B)"
-- First, create a stable Legal Unit for the Formal Establishment to link to.
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_69_b_lu_for_es', 'Test 69.B: Base LU for Formal ES', 'Test 69.B');
END $$;
INSERT INTO public.import_69_b_lu_for_es_upload(tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, primary_activity_category_code) VALUES
('69B000000', 'Base LU for ES-69B', '2023-01-01', '2023-12-31', 'S_Base', 'AS', '00.000');
CALL worker.process_tasks(p_queue => 'import');
\echo "Job status for import_69_b_lu_for_es:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_69_b_lu_for_es';
\echo "Data table for import_69_b_lu_for_es:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, name_raw FROM public.import_69_b_lu_for_es_data ORDER BY row_id;

-- Sub-Scenario 69.B.1: Initial Formal ES Import
\echo "Sub-Scenario 69.B.1: Initial Formal ES Import for ES-69B"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_69_b1_es', 'Test 69.B.1: ES-69B Initial', 'Test 69.B.1');
END $$;
\echo Created job - now uploading data
INSERT INTO public.import_69_b1_es_upload(
    tax_ident, legal_unit_tax_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, email_address, employees, tag_path
) VALUES (
    'E69B00001', '69B000000', 'ES-69B Period 1', '2023-01-01', '2023-03-31', 'Addr 1 ES-69B', 'NO', '2001', '0301',
    '02.110', 'es69b_p1@example.com', '5', 'TestTag.ES.Formal'
);
\echo Processing upload
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

\echo "Job status for import_69_b1_es:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_69_b1_es';
\echo "Data table for import_69_b1_es:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_69_b1_es_data ORDER BY row_id;

\echo "Verification for ES-69B ('E69B00001') after Sub-Scenario 69.B.1 (all segments shown):"
\echo "Establishment:"
SELECT est.name, ei.ident, lu_ei.ident as legal_unit_tax_ident, est.valid_from, est.valid_to
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.legal_unit lu ON est.legal_unit_id = lu.id
LEFT JOIN public.external_ident lu_ei ON lu.id = lu_ei.legal_unit_id AND lu_ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' ORDER BY est.valid_from, est.valid_to;
\echo "Location:"
SELECT loc.address_part1, loc.postcode, r.code as region_code, loc.valid_from, loc.valid_to
FROM public.location loc
JOIN public.external_ident ei ON loc.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.region r ON loc.region_id = r.id
WHERE ei.ident = 'E69B00001' AND loc.type='physical' ORDER BY loc.valid_from, loc.valid_to;
\echo "Activity:"
SELECT ac.code as activity_code, act.type, act.valid_from, act.valid_to
FROM public.activity act
JOIN public.activity_category ac ON act.category_id = ac.id
JOIN public.external_ident ei ON act.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' AND act.type='primary' ORDER BY act.valid_from, act.valid_to;
\echo "Contact:"
SELECT con.email_address, con.valid_from, con.valid_to
FROM public.contact con
JOIN public.external_ident ei ON con.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' ORDER BY con.valid_from, con.valid_to;
\echo "Stat (Employees):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' AND sd.code = 'employees' ORDER BY sfu.valid_from, sfu.valid_to, sd.code;
\echo "Tag:"
SELECT est.name as est_name, est.valid_from AS est_valid_from, est.valid_to AS est_valid_to,
       (SELECT COALESCE(array_agg(t_sub.path ORDER BY t_sub.path), '{}')
        FROM public.tag_for_unit tfu_sub
        JOIN public.tag t_sub ON tfu_sub.tag_id = t_sub.id
        WHERE tfu_sub.establishment_id = est.id) as tag_paths
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001'
ORDER BY est.valid_from, est.valid_to;

-- Sub-Scenario 69.B.2: First Update (Change ES Name, Address, Activity)
\echo "Sub-Scenario 69.B.2: Update ES-69B (Name, Address, Activity)"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_69_b2_es', 'Test 69.B.2: ES-69B Update 1', 'Test 69.B.2');
END $$;
INSERT INTO public.import_69_b2_es_upload(
    tax_ident, legal_unit_tax_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, email_address, employees, tag_path
) VALUES (
    'E69B00001', '69B000000', 'ES-69B Period 2 Updated Name', '2023-04-01', '2023-06-30', 'Addr 2 ES-69B Updated', 'NO', '2002', '0301',
    '02.120', 'es69b_p1@example.com', '5', 'TestTag.ES.Formal'
);
CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_69_b2_es:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_69_b2_es';
\echo "Data table for import_69_b2_es:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_69_b2_es_data ORDER BY row_id;

\echo "Verification for ES-69B ('E69B00001') after Sub-Scenario 69.B.2 (all segments shown):"
\echo "Establishment (expect new name in latest segment):"
SELECT est.name, ei.ident, lu_ei.ident as legal_unit_tax_ident, est.valid_from, est.valid_to
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.legal_unit lu ON est.legal_unit_id = lu.id
LEFT JOIN public.external_ident lu_ei ON lu.id = lu_ei.legal_unit_id AND lu_ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' ORDER BY est.valid_from, est.valid_to;
\echo "Location (expect new address):"
SELECT loc.address_part1, loc.postcode, r.code as region_code, loc.valid_from, loc.valid_to
FROM public.location loc
JOIN public.external_ident ei ON loc.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.region r ON loc.region_id = r.id
WHERE ei.ident = 'E69B00001' AND loc.type='physical' ORDER BY loc.valid_from, loc.valid_to;
\echo "Activity (expect new activity code):"
SELECT ac.code as activity_code, act.type, act.valid_from, act.valid_to
FROM public.activity act
JOIN public.activity_category ac ON act.category_id = ac.id
JOIN public.external_ident ei ON act.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' AND act.type='primary' ORDER BY act.valid_from, act.valid_to;
\echo "Contact (should be unchanged from B.1, possibly extended):"
SELECT con.email_address, con.valid_from, con.valid_to
FROM public.contact con
JOIN public.external_ident ei ON con.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' ORDER BY con.valid_from, con.valid_to;
\echo "Stat (Employees - should be unchanged from B.1, possibly extended):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' AND sd.code = 'employees' ORDER BY sfu.valid_from, sfu.valid_to, sd.code;
\echo "Tag (should be unchanged from B.1, possibly extended):"
SELECT est.name as est_name, est.valid_from AS est_valid_from, est.valid_to AS est_valid_to,
       (SELECT COALESCE(array_agg(t_sub.path ORDER BY t_sub.path), '{}')
        FROM public.tag_for_unit tfu_sub
        JOIN public.tag t_sub ON tfu_sub.tag_id = t_sub.id
        WHERE tfu_sub.establishment_id = est.id) as tag_paths
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001'
ORDER BY est.valid_from, est.valid_to;

-- Sub-Scenario 69.B.3: Second Update (Change Email, Employees, Tag)
\echo "Sub-Scenario 69.B.3: Update ES-69B (Email, Employees, Tag)"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_69_b3_es', 'Test 69.B.3: ES-69B Update 2', 'Test 69.B.3');
END $$;
INSERT INTO public.import_69_b3_es_upload(
    tax_ident, legal_unit_tax_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, email_address, employees, tag_path
) VALUES (
    'E69B00001', '69B000000', 'ES-69B Period 2 Updated Name', '2023-07-01', '2023-09-30', 'Addr 2 ES-69B Updated', 'NO', '2002', '0301',
    '02.120', 'es69b_p3_updated@example.com', '7', 'TestTag.ES.Formal.Updated'
);
CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_69_b3_es:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_69_b3_es';
\echo "Data table for import_69_b3_es:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_69_b3_es_data ORDER BY row_id;

\echo "Verification for ES-69B ('E69B00001') after Sub-Scenario 69.B.3 (all segments shown):"
\echo "Establishment (name unchanged from B.2 in latest segment):"
SELECT est.name, ei.ident, lu_ei.ident as legal_unit_tax_ident, est.valid_from, est.valid_to
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.legal_unit lu ON est.legal_unit_id = lu.id
LEFT JOIN public.external_ident lu_ei ON lu.id = lu_ei.legal_unit_id AND lu_ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' ORDER BY est.valid_from, est.valid_to;
\echo "Location (address unchanged from B.2, possibly extended):"
SELECT loc.address_part1, loc.postcode, r.code as region_code, loc.valid_from, loc.valid_to
FROM public.location loc
JOIN public.external_ident ei ON loc.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.region r ON loc.region_id = r.id
WHERE ei.ident = 'E69B00001' AND loc.type='physical' ORDER BY loc.valid_from, loc.valid_to;
\echo "Activity (activity code unchanged from B.2, possibly extended):"
SELECT ac.code as activity_code, act.type, act.valid_from, act.valid_to
FROM public.activity act
JOIN public.activity_category ac ON act.category_id = ac.id
JOIN public.external_ident ei ON act.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' AND act.type='primary' ORDER BY act.valid_from, act.valid_to;
\echo "Contact (expect new email):"
SELECT con.email_address, con.valid_from, con.valid_to
FROM public.contact con
JOIN public.external_ident ei ON con.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' ORDER BY con.valid_from, con.valid_to;
\echo "Stat (Employees - expect new value 7 in latest segment):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001' AND sd.code = 'employees' ORDER BY sfu.valid_from, sfu.valid_to, sd.code;
\echo "Tag (expect new tag TestTag.ES.Formal.Updated alongside existing):"
SELECT est.name as est_name, est.valid_from AS est_valid_from, est.valid_to AS est_valid_to,
       (SELECT COALESCE(array_agg(t_sub.path ORDER BY t_sub.path), '{}')
        FROM public.tag_for_unit tfu_sub
        JOIN public.tag t_sub ON tfu_sub.tag_id = t_sub.id
        WHERE tfu_sub.establishment_id = est.id) as tag_paths
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69B00001'
ORDER BY est.valid_from, est.valid_to;

\echo "Consolidated Statistical Unit view for ES-69B (E69B00001) across all periods:"
CALL worker.process_tasks(p_queue => 'analytics');
SELECT
    su.name, su.valid_from, su.valid_to,
    su.physical_address_part1, su.physical_postcode, su.physical_region_code,
    su.primary_activity_category_code,
    su.email_address, su.stats->>'employees' as employees, su.tag_paths,
    su.external_idents->>'legal_unit_tax_ident' as legal_unit_tax_ident
FROM public.statistical_unit su
WHERE su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = 'E69B00001'
ORDER BY su.valid_from, su.valid_to;

ROLLBACK TO scenario_69_b_formal_es_lifecycle;

--------------------------------------------------------------------------------
-- Scenario 69.C: Informal Establishment - Full Attribute Lifecycle
--------------------------------------------------------------------------------
SAVEPOINT scenario_69_c_informal_es_lifecycle;
\echo "Scenario 69.C: Informal Establishment - Full Attribute Lifecycle (ES-69C)"

-- Sub-Scenario 69.C.1: Initial Informal ES Import
\echo "Sub-Scenario 69.C.1: Initial Informal ES Import for ES-69C"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_69_c1_es', 'Test 69.C.1: ES-69C Initial', 'Test 69.C.1');
END $$;
INSERT INTO public.import_69_c1_es_upload(
    tax_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, email_address, employees, tag_path
) VALUES (
    'E69C00001', 'ES-69C Period 1', '2023-01-01', '2023-03-31', 'Addr 1 ES-69C', 'NO', '3001', '0301',
    '03.110', 'es69c_p1@example.com', '2', 'TestTag.ES.Informal'
);
CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_69_c1_es:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_69_c1_es';
\echo "Data table for import_69_c1_es:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_69_c1_es_data ORDER BY row_id;

\echo "Verification for ES-69C ('E69C00001') after Sub-Scenario 69.C.1 (all segments shown):"
\echo "Establishment:"
SELECT est.name, ei.ident, est.valid_from, est.valid_to
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' ORDER BY est.valid_from, est.valid_to;
\echo "Location:"
SELECT loc.address_part1, loc.postcode, r.code as region_code, loc.valid_from, loc.valid_to
FROM public.location loc
JOIN public.external_ident ei ON loc.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.region r ON loc.region_id = r.id
WHERE ei.ident = 'E69C00001' AND loc.type='physical' ORDER BY loc.valid_from, loc.valid_to;
\echo "Activity:"
SELECT ac.code as activity_code, act.type, act.valid_from, act.valid_to
FROM public.activity act
JOIN public.activity_category ac ON act.category_id = ac.id
JOIN public.external_ident ei ON act.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' AND act.type='primary' ORDER BY act.valid_from, act.valid_to;
\echo "Contact:"
SELECT con.email_address, con.valid_from, con.valid_to
FROM public.contact con
JOIN public.external_ident ei ON con.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' ORDER BY con.valid_from, con.valid_to;
\echo "Stat (Employees):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' AND sd.code = 'employees' ORDER BY sfu.valid_from, sfu.valid_to, sd.code;
\echo "Tag:"
SELECT est.name as est_name, est.valid_from AS est_valid_from, est.valid_to AS est_valid_to,
       (SELECT COALESCE(array_agg(t_sub.path ORDER BY t_sub.path), '{}')
        FROM public.tag_for_unit tfu_sub
        JOIN public.tag t_sub ON tfu_sub.tag_id = t_sub.id
        WHERE tfu_sub.establishment_id = est.id) as tag_paths
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001'
ORDER BY est.valid_from, est.valid_to;

-- Sub-Scenario 69.C.2: First Update (Change ES Name, Address, Activity)
\echo "Sub-Scenario 69.C.2: Update ES-69C (Name, Address, Activity)"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_69_c2_es', 'Test 69.C.2: ES-69C Update 1', 'Test 69.C.2');
END $$;
INSERT INTO public.import_69_c2_es_upload(
    tax_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, email_address, employees, tag_path
) VALUES (
    'E69C00001', 'ES-69C Period 2 Updated Name', '2023-04-01', '2023-06-30', 'Addr 2 ES-69C Updated', 'NO', '3002', '0301',
    '03.120', 'es69c_p1@example.com', '2', 'TestTag.ES.Informal'
);
\echo "Processing import jobs"
CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_69_c2_es:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_69_c2_es';
\echo "Data table for import_69_c2_es:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_69_c2_es_data ORDER BY row_id;

\echo "Verification for ES-69C ('E69C00001') after Sub-Scenario 69.C.2 (all segments shown):"
\echo "Establishment (expect new name in latest segment):"
SELECT est.name, ei.ident, est.valid_from, est.valid_to
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' ORDER BY est.valid_from, est.valid_to;
\echo "Location (expect new address):"
SELECT loc.address_part1, loc.postcode, r.code as region_code, loc.valid_from, loc.valid_to
FROM public.location loc
JOIN public.external_ident ei ON loc.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.region r ON loc.region_id = r.id
WHERE ei.ident = 'E69C00001' AND loc.type='physical' ORDER BY loc.valid_from, loc.valid_to;
\echo "Activity (expect new activity code):"
SELECT ac.code as activity_code, act.type, act.valid_from, act.valid_to
FROM public.activity act
JOIN public.activity_category ac ON act.category_id = ac.id
JOIN public.external_ident ei ON act.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' AND act.type='primary' ORDER BY act.valid_from, act.valid_to;
\echo "Contact (should be unchanged from C.1, possibly extended):"
SELECT con.email_address, con.valid_from, con.valid_to
FROM public.contact con
JOIN public.external_ident ei ON con.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' ORDER BY con.valid_from, con.valid_to;
\echo "Stat (Employees - should be unchanged from C.1, possibly extended):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' AND sd.code = 'employees' ORDER BY sfu.valid_from, sfu.valid_to, sd.code;
\echo "Tag (should be unchanged from C.1, possibly extended):"
SELECT est.name as est_name, est.valid_from AS est_valid_from, est.valid_to AS est_valid_to,
       (SELECT COALESCE(array_agg(t_sub.path ORDER BY t_sub.path), '{}')
        FROM public.tag_for_unit tfu_sub
        JOIN public.tag t_sub ON tfu_sub.tag_id = t_sub.id
        WHERE tfu_sub.establishment_id = est.id) as tag_paths
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001'
ORDER BY est.valid_from, est.valid_to;

-- Sub-Scenario 69.C.3: Second Update (Change Email, Employees, Tag)
\echo "Sub-Scenario 69.C.3: Update ES-69C (Email, Employees, Tag)"
DO $$
DECLARE v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
    VALUES (v_definition_id, 'import_69_c3_es', 'Test 69.C.3: ES-69C Update 2', 'Test 69.C.3');
END $$;
INSERT INTO public.import_69_c3_es_upload(
    tax_ident, name, valid_from, valid_to, physical_address_part1, physical_country_iso_2, physical_postcode, physical_region_code,
    primary_activity_category_code, email_address, employees, tag_path
) VALUES (
    'E69C00001', 'ES-69C Period 2 Updated Name', '2023-07-01', '2023-09-30', 'Addr 2 ES-69C Updated', 'NO', '3002', '0301',
    '03.120', 'es69c_p3_updated@example.com', '3', 'TestTag.ES.Informal.Updated'
);
CALL worker.process_tasks(p_queue => 'import');

\echo "Job status for import_69_c3_es:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_69_c3_es';
\echo "Data table for import_69_c3_es:"
SELECT row_id, state, errors, invalid_codes, merge_status, action, operation, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw FROM public.import_69_c3_es_data ORDER BY row_id;

\echo "Verification for ES-69C ('E69C00001') after Sub-Scenario 69.C.3 (all segments shown):"
\echo "Establishment (name unchanged from C.2 in latest segment):"
SELECT est.name, ei.ident, est.valid_from, est.valid_to
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' ORDER BY est.valid_from, est.valid_to;
\echo "Location (address unchanged from C.2, possibly extended):"
SELECT loc.address_part1, loc.postcode, r.code as region_code, loc.valid_from, loc.valid_to
FROM public.location loc
JOIN public.external_ident ei ON loc.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
LEFT JOIN public.region r ON loc.region_id = r.id
WHERE ei.ident = 'E69C00001' AND loc.type='physical' ORDER BY loc.valid_from, loc.valid_to;
\echo "Activity (activity code unchanged from C.2, possibly extended):"
SELECT ac.code as activity_code, act.type, act.valid_from, act.valid_to
FROM public.activity act
JOIN public.activity_category ac ON act.category_id = ac.id
JOIN public.external_ident ei ON act.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' AND act.type='primary' ORDER BY act.valid_from, act.valid_to;
\echo "Contact (expect new email):"
SELECT con.email_address, con.valid_from, con.valid_to
FROM public.contact con
JOIN public.external_ident ei ON con.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' ORDER BY con.valid_from, con.valid_to;
\echo "Stat (Employees - expect new value 3 in latest segment):"
SELECT sd.code as stat_code, sfu.value_int, sfu.valid_from, sfu.valid_to
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.external_ident ei ON sfu.establishment_id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001' AND sd.code = 'employees' ORDER BY sfu.valid_from, sfu.valid_to, sd.code;
\echo "Tag (expect new tag TestTag.ES.Informal.Updated alongside existing):"
SELECT est.name as est_name, est.valid_from AS est_valid_from, est.valid_to AS est_valid_to,
       (SELECT COALESCE(array_agg(t_sub.path ORDER BY t_sub.path), '{}')
        FROM public.tag_for_unit tfu_sub
        JOIN public.tag t_sub ON tfu_sub.tag_id = t_sub.id
        WHERE tfu_sub.establishment_id = est.id) as tag_paths
FROM public.establishment est
JOIN public.external_ident ei ON est.id = ei.establishment_id AND ei.type_id = (SELECT id FROM external_ident_type WHERE code='tax_ident')
WHERE ei.ident = 'E69C00001'
ORDER BY est.valid_from, est.valid_to;

\echo "Consolidated Statistical Unit view for ES-69C (E69C00001) across all periods:"
CALL worker.process_tasks(p_queue => 'analytics');
SELECT
    su.name, su.valid_from, su.valid_to,
    su.physical_address_part1, su.physical_postcode, su.physical_region_code,
    su.primary_activity_category_code,
    su.email_address, su.stats->>'employees' as employees, su.tag_paths
FROM public.statistical_unit su
WHERE su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = 'E69C00001'
ORDER BY su.valid_from, su.valid_to;

ROLLBACK TO scenario_69_c_informal_es_lifecycle;

\echo "Final counts after all test blocks for Test 69 (should be same as initial due to rollbacks)"
SELECT
    (SELECT COUNT(*) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(*) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(*) FROM public.enterprise) AS enterprise_count;

ROLLBACK TO main_test_69_start;
\echo "Test 69 completed and rolled back to main start."

ROLLBACK; -- Final rollback for the entire transaction

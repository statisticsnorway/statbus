SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

\echo "Test 68: Comprehensive Import Job System Test"
\echo "Setting up Statbus environment for test 68"

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

SAVEPOINT main_test_68_start;
\echo "Initial counts before any test block"
SELECT
    (SELECT COUNT(*) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(*) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(*) FROM public.enterprise) AS enterprise_count;

-- Scenario 1: Single LU
SAVEPOINT scenario_1_single_lu;
\echo "Scenario 1: Import a single Legal Unit"
DO $$
DECLARE
    v_definition_id INT;
    v_definition_slug TEXT := 'legal_unit_explicit_dates';
    v_job_slug TEXT := 'import_68_01_single_lu';
    v_job_description TEXT := 'Test 68-01: Single LU';
    v_job_note TEXT := 'Importing one LU.';
    v_job_edit_comment TEXT := 'Test 68';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition with slug ''%'' not found.', v_definition_slug;
    END IF;

    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, v_job_slug, v_job_description, v_job_note, v_job_edit_comment);
END $$;
INSERT INTO public.import_68_01_single_lu_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) VALUES
('2020-01-01','2020-12-31','680100001','Single LU One','2020-01-01',NULL,'Main St 1','1234','Oslo','0301','NO','01.110',NULL,'2100','AS');
CALL worker.process_tasks(p_queue => 'import');

\echo "Import job status for 68_01_single_lu:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_68_01_single_lu' ORDER BY slug;

\echo "Data table row status for import_68_01_single_lu:"
SELECT row_id, state, error, action, operation FROM public.import_68_01_single_lu_data;

\echo "Verification for Scenario 1: Single LU"
\echo "Legal Units (verify attributes, not specific IDs):"
SELECT
    COUNT(*) AS lu_count,
    lu.name,
    ei.ident AS tax_ident,
    lu.primary_for_enterprise,
    lu.valid_from, lu.valid_after, lu.valid_to,
    (SELECT COUNT(*) FROM public.enterprise WHERE id = lu.enterprise_id) as linked_enterprise_exists
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident = '680100001'
GROUP BY lu.name, ei.ident, lu.primary_for_enterprise, lu.valid_from, lu.valid_after, lu.valid_to, lu.enterprise_id
ORDER BY ei.ident, lu.valid_after, lu.valid_from, lu.valid_to;

\echo "Enterprises (verify one was created and LU is primary):"
SELECT
    COUNT(*) as enterprise_count,
    ent.short_name,
    (SELECT COUNT(*) FROM public.legal_unit lu_check
     JOIN public.external_ident ei_check ON ei_check.legal_unit_id = lu_check.id
     JOIN public.external_ident_type eit_check ON eit_check.id = ei_check.type_id AND eit_check.code = 'tax_ident'
     WHERE lu_check.enterprise_id = ent.id AND ei_check.ident = '680100001' AND lu_check.primary_for_enterprise = TRUE
    ) as is_primary_lu_linked
FROM public.enterprise ent
WHERE ent.id IN (
    SELECT lu.enterprise_id
    FROM public.legal_unit lu
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
    JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
    WHERE ei.ident = '680100001'
)
GROUP BY ent.id, ent.short_name;

CALL worker.process_tasks(p_queue => 'analytics');
\echo "Statistical Units (LU):"
SELECT COUNT(*) as su_lu_count, su.name, su.external_idents->>'tax_ident' AS tax_ident, su.valid_from, su.valid_to
FROM public.statistical_unit su
WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = '680100001'
GROUP BY su.name, su.external_idents->>'tax_ident', su.valid_from, su.valid_to
ORDER BY su.external_idents->>'tax_ident', su.valid_from, su.valid_to;
ROLLBACK TO scenario_1_single_lu;

-- Scenario 2: Single LU + 1 Formal ES
SAVEPOINT scenario_2_lu_plus_formal_es;
\echo "Scenario 2: Import a single LU and one formal Establishment linked to it"
DO $$
DECLARE
    v_definition_id INT;
    v_definition_slug TEXT := 'legal_unit_explicit_dates';
    v_job_slug TEXT := 'import_68_02_lu';
    v_job_description TEXT := 'Test 68-02: LU for Formal ES';
    v_job_note TEXT := 'Importing LU part.';
    v_job_edit_comment TEXT := 'Test 68';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition with slug ''%'' not found.', v_definition_slug;
    END IF;

    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, v_job_slug, v_job_description, v_job_note, v_job_edit_comment);
END $$;
INSERT INTO public.import_68_02_lu_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) VALUES
('2020-01-01','2020-12-31','680200001','LU for Formal ES','2020-01-01',NULL,'LU Address 1','1234','Oslo','0301','NO','02.200',NULL,'2100','AS');

DO $$
DECLARE
    v_definition_id INT;
    v_definition_slug TEXT := 'establishment_for_lu_explicit_dates';
    v_job_slug TEXT := 'import_68_02_es';
    v_job_description TEXT := 'Test 68-02: Formal ES';
    v_job_note TEXT := 'Importing ES part.';
    v_job_edit_comment TEXT := 'Test 68';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition with slug ''%'' not found.', v_definition_slug;
    END IF;

    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, v_job_slug, v_job_description, v_job_note, v_job_edit_comment);
END $$;
INSERT INTO public.import_68_02_es_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,legal_unit_tax_ident) VALUES
('2020-01-01','2020-12-31','E68020001','Formal ES One','2020-01-01',NULL,'ES Address 1','1234','Oslo','0301','NO','02.200',NULL,'680200001');
CALL worker.process_tasks(p_queue => 'import');

\echo "Import job statuses for 68_02:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug LIKE 'import_68_02%' ORDER BY slug;

\echo "Verification for Scenario 2: LU + Formal ES"
\echo "Legal Units:"
SELECT
    COUNT(*) AS lu_count,
    lu.name,
    ei.ident AS tax_ident,
    lu.valid_from, lu.valid_after, lu.valid_to,
    (SELECT COUNT(*) FROM public.enterprise WHERE id = lu.enterprise_id) as linked_enterprise_exists
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident = '680200001'
GROUP BY lu.name, ei.ident, lu.valid_from, lu.valid_after, lu.valid_to, lu.enterprise_id
ORDER BY ei.ident, lu.valid_after, lu.valid_from, lu.valid_to;
\echo "Establishments:"
SELECT
    COUNT(*) AS est_count,
    est.name,
    est_ei.ident AS est_tax_ident,
    est.primary_for_legal_unit,
    est.valid_from, est.valid_after, est.valid_to,
    (SELECT COUNT(*)
     FROM public.legal_unit lu_link
     JOIN public.external_ident ei_link ON ei_link.legal_unit_id = lu_link.id
     JOIN public.external_ident_type eit_link ON eit_link.id = ei_link.type_id AND eit_link.code = 'tax_ident'
     WHERE lu_link.id = est.legal_unit_id AND ei_link.ident = '680200001'
    ) as linked_to_correct_lu,
    (SELECT COUNT(*) FROM public.enterprise ent_link WHERE ent_link.id = est.enterprise_id) as linked_enterprise_exists -- Assuming ES inherits ENT from LU
FROM public.establishment est
JOIN public.external_ident est_ei ON est_ei.establishment_id = est.id
JOIN public.external_ident_type est_eit ON est_eit.id = est_ei.type_id AND est_eit.code = 'tax_ident' -- Changed to tax_ident
WHERE est_ei.ident = 'E68020001'
GROUP BY est.name, est_ei.ident, est.primary_for_legal_unit, est.valid_from, est.valid_after, est.valid_to, est.legal_unit_id, est.enterprise_id
ORDER BY est_ei.ident, est.valid_after, est.valid_from, est.valid_to;
\echo "Enterprises (verify one was created and LU is primary):"
SELECT
    COUNT(*) as enterprise_count,
    ent.short_name,
    (SELECT COUNT(*) FROM public.legal_unit lu_check
     JOIN public.external_ident ei_check ON ei_check.legal_unit_id = lu_check.id
     JOIN public.external_ident_type eit_check ON eit_check.id = ei_check.type_id AND eit_check.code = 'tax_ident'
     WHERE lu_check.enterprise_id = ent.id AND ei_check.ident = '680200001' AND lu_check.primary_for_enterprise = TRUE
    ) as is_primary_lu_linked
FROM public.enterprise ent
WHERE ent.id IN (
    SELECT lu.enterprise_id
    FROM public.legal_unit lu
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
    JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
    WHERE ei.ident = '680200001'
)
GROUP BY ent.id, ent.short_name;

CALL worker.process_tasks(p_queue => 'analytics');
\echo "Statistical Units (LU):"
SELECT COUNT(*) as su_lu_count, su.name, su.external_idents->>'tax_ident' AS tax_ident, su.valid_from, su.valid_to
FROM public.statistical_unit su
WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = '680200001'
GROUP BY su.name, su.external_idents->>'tax_ident', su.valid_from, su.valid_to
ORDER BY su.external_idents->>'tax_ident', su.valid_from, su.valid_to;
\echo "Statistical Units (ES):"
SELECT COUNT(*) as su_es_count, su.name, su.external_idents->>'establishment_tax_ident' AS est_tax_ident, su.valid_from, su.valid_to
FROM public.statistical_unit su
WHERE su.unit_type = 'establishment' AND su.external_idents->>'establishment_tax_ident' = 'E68020001'
GROUP BY su.name, su.external_idents->>'establishment_tax_ident', su.valid_from, su.valid_to
ORDER BY su.external_idents->>'establishment_tax_ident', su.valid_from, su.valid_to;
ROLLBACK TO scenario_2_lu_plus_formal_es;

-- Scenario 3: Single Informal ES
SAVEPOINT scenario_3_single_informal_es;
\echo "Scenario 3: Import a single informal Establishment"
DO $$
DECLARE
    v_definition_id INT;
    v_definition_slug TEXT := 'establishment_without_lu_explicit_dates';
    v_job_slug TEXT := 'import_68_03_informal_es';
    v_job_description TEXT := 'Test 68-03: Informal ES';
    v_job_note TEXT := 'Importing one informal ES.';
    v_job_edit_comment TEXT := 'Test 68';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition with slug ''%'' not found.', v_definition_slug;
    END IF;

    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, v_job_slug, v_job_description, v_job_note, v_job_edit_comment);
END $$;
INSERT INTO public.import_68_03_informal_es_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code) VALUES
('2020-01-01','2020-12-31','E68030001','Informal ES One','2020-01-01',NULL,'Informal St 1','1234','Oslo','0301','NO','03.100',NULL);
CALL worker.process_tasks(p_queue => 'import');
\echo "Import job status for 68_03_informal_es:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_68_03_informal_es' ORDER BY slug; -- Added error_details

\echo "Data table row status for import_68_03_informal_es:" -- Added for consistency
SELECT row_id, state, error, action, operation FROM public.import_68_03_informal_es_data ORDER BY row_id;

\echo "Verification for Scenario 3: Informal ES"
\echo "Establishments:"
SELECT
    COUNT(*) AS est_count,
    est.name,
    ei.ident AS tax_ident,
    est.legal_unit_id, -- Should be NULL for informal
    est.primary_for_enterprise,
    est.valid_from, est.valid_after, est.valid_to,
    (SELECT COUNT(*) FROM public.enterprise WHERE id = est.enterprise_id) as linked_enterprise_exists
FROM public.establishment est
JOIN public.external_ident ei ON ei.establishment_id = est.id
JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident = 'E68030001'
GROUP BY est.name, ei.ident, est.legal_unit_id, est.primary_for_enterprise, est.valid_from, est.valid_after, est.valid_to, est.enterprise_id
ORDER BY ei.ident, est.valid_after, est.valid_from, est.valid_to;
\echo "Enterprises (verify one was created and ES is primary):"
SELECT
    COUNT(*) as enterprise_count,
    ent.short_name,
    (SELECT COUNT(*) FROM public.establishment est_check
     JOIN public.external_ident ei_check ON ei_check.establishment_id = est_check.id
     JOIN public.external_ident_type eit_check ON eit_check.id = ei_check.type_id AND eit_check.code = 'tax_ident'
     WHERE est_check.enterprise_id = ent.id AND ei_check.ident = 'E68030001' AND est_check.primary_for_enterprise = TRUE
    ) as is_primary_es_linked
FROM public.enterprise ent
WHERE ent.id IN (
    SELECT est.enterprise_id
    FROM public.establishment est
    JOIN public.external_ident ei ON ei.establishment_id = est.id
    JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
    WHERE ei.ident = 'E68030001'
)
GROUP BY ent.id, ent.short_name;

CALL worker.process_tasks(p_queue => 'analytics');
\echo "Statistical Units (ES):"
SELECT COUNT(*) as su_es_count, su.name, su.external_idents->>'tax_ident' AS tax_ident, su.valid_from, su.valid_to
FROM public.statistical_unit su
WHERE su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = 'E68030001'
GROUP BY su.name, su.external_idents->>'tax_ident', su.valid_from, su.valid_to
ORDER BY su.external_idents->>'tax_ident', su.valid_from, su.valid_to;
ROLLBACK TO scenario_3_single_informal_es;

-- Scenario 4: Two LUs
SAVEPOINT scenario_4_two_lus;
\echo "Scenario 4: Import two distinct Legal Units"
DO $$
DECLARE
    v_definition_id INT;
    v_definition_slug TEXT := 'legal_unit_explicit_dates';
    v_job_slug TEXT := 'import_68_04_two_lus';
    v_job_description TEXT := 'Test 68-04: Two LUs';
    v_job_note TEXT := 'Importing two LUs.';
    v_job_edit_comment TEXT := 'Test 68';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition with slug ''%'' not found.', v_definition_slug;
    END IF;

    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, v_job_slug, v_job_description, v_job_note, v_job_edit_comment);
END $$;
INSERT INTO public.import_68_04_two_lus_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) VALUES
('2020-01-01','2020-12-31','680400001','First of Two LUs','2020-01-01',NULL,'First St 1','1234','Oslo','0301','NO','05.100',NULL,'2100','AS'),
('2020-01-01','2020-12-31','680400002','Second of Two LUs','2020-01-01',NULL,'Second St 1','5678','Bergen','4601','NO','06.100',NULL,'2100','AS');
CALL worker.process_tasks(p_queue => 'import');
\echo "Import job status for 68_04_two_lus:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_68_04_two_lus' ORDER BY slug; -- Added error_details

\echo "Data table row status for import_68_04_two_lus:" -- Added for consistency
SELECT row_id, state, error, action, operation FROM public.import_68_04_two_lus_data ORDER BY row_id;

\echo "Verification for Scenario 4: Two LUs"
\echo "Legal Units:"
SELECT
    lu.name,
    ei.ident AS tax_ident,
    lu.primary_for_enterprise,
    lu.valid_from, lu.valid_after, lu.valid_to,
    (SELECT COUNT(*) FROM public.enterprise WHERE id = lu.enterprise_id) as linked_enterprise_exists
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident LIKE '6804%'
ORDER BY ei.ident, lu.valid_after, lu.valid_from, lu.valid_to;
\echo "Enterprises (verify two were created, each linked to one LU as primary):"
SELECT
    ent.short_name,
    (SELECT COUNT(DISTINCT lu_check.id) FROM public.legal_unit lu_check
     JOIN public.external_ident ei_check ON ei_check.legal_unit_id = lu_check.id
     JOIN public.external_ident_type eit_check ON eit_check.id = ei_check.type_id AND eit_check.code = 'tax_ident'
     WHERE lu_check.enterprise_id = ent.id AND ei_check.ident LIKE '6804%' AND lu_check.primary_for_enterprise = TRUE
    ) as primary_lus_for_this_ent_in_batch -- Should be 1 for each enterprise
FROM public.enterprise ent
WHERE ent.id IN (
    SELECT lu.enterprise_id
    FROM public.legal_unit lu
    JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
    JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
    WHERE ei.ident LIKE '6804%'
)
ORDER BY (SELECT MIN(ei_order.ident) FROM public.legal_unit lu_order JOIN public.external_ident ei_order ON lu_order.id = ei_order.legal_unit_id WHERE lu_order.enterprise_id = ent.id); -- Order enterprises by their LU's tax_ident

CALL worker.process_tasks(p_queue => 'analytics');

\echo "Statistical Units (LU):"
SELECT su.name, su.external_idents->>'tax_ident' AS tax_ident, su.valid_from, su.valid_to
FROM public.statistical_unit su
WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' LIKE '6804%'
ORDER BY su.external_idents->>'tax_ident', su.valid_from, su.valid_to;

ROLLBACK TO scenario_4_two_lus;

-- Scenario 5: LU with three consecutive periods (P1=P2 core data, P3 different)
SAVEPOINT scenario_5_lu_three_periods;
\echo "Scenario 5: LU with three consecutive periods (P1 data = P2 data, P3 data different)"
DO $$
DECLARE
    v_definition_id INT;
    v_definition_slug TEXT := 'legal_unit_explicit_dates';
    v_job_slug TEXT := 'import_68_05_lu_periods';
    v_job_description TEXT := 'Test 68-05: LU Three Periods';
    v_job_note TEXT := 'Importing LU with period changes.';
    v_job_edit_comment TEXT := 'Test 68';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition with slug ''%'' not found.', v_definition_slug;
    END IF;

    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, v_job_slug, v_job_description, v_job_note, v_job_edit_comment);
END $$;
INSERT INTO public.import_68_05_lu_periods_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) VALUES
('2020-01-01','2020-03-31','680500001','LU Three Periods','2020-01-01',NULL,'Addr P1','1000','Oslo','0301','NO','10.100',NULL,'2100','AS'),
('2020-04-01','2020-06-30','680500001','LU Three Periods','2020-01-01',NULL,'Addr P1','1000','Oslo','0301','NO','10.100',NULL,'2100','AS'),
('2020-07-01','2020-09-30','680500001','LU Three Periods','2020-01-01',NULL,'Addr P3 Changed','1000','Oslo','0301','NO','10.100',NULL,'2100','AS');

--SET LOCAL client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--RESET client_min_messages;

\echo "Import job status for 68_05_lu_periods:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_68_05_lu_periods' ORDER BY slug;

\echo "Data table row status for import_68_05_lu_periods:"
SELECT row_id, state, error, action, operation FROM public.import_68_05_lu_periods_data ORDER BY row_id;

\echo "Verification for Scenario 5: LU Three Periods"
\echo "Legal Units (expect 2 slices: P1+P2 merged, P3 separate with invalid sector):"
SELECT lu.name, ei.ident AS tax_ident, sec.code AS sector_code, lu.invalid_codes->>'sector_code' as invalid_sector_code, lu.valid_from, lu.valid_after, lu.valid_to
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
LEFT JOIN public.sector sec ON lu.sector_id = sec.id
WHERE ei.ident = '680500001' ORDER BY ei.ident, lu.valid_after, lu.valid_from, lu.valid_to;

\echo "Physical Locations for LU 680500001 (expect 2 slices: P1+P2 merged, P3 separate):"
SELECT
    ei.ident AS tax_ident,
    loc.type,
    loc.address_part1,
    loc.valid_from,
    loc.valid_after,
    loc.valid_to
FROM public.location loc
-- Correctly join to find the legal_unit_id associated with tax_ident '680500001'
JOIN public.external_ident ei ON loc.legal_unit_id = ei.legal_unit_id
JOIN public.external_ident_type eit ON ei.type_id = eit.id
WHERE ei.ident = '680500001' AND eit.code = 'tax_ident' AND loc.type = 'physical'
ORDER BY ei.ident, loc.type, loc.valid_after, loc.valid_from, loc.valid_to;

CALL worker.process_tasks(p_queue => 'analytics');

\echo "Statistical Units (LU - expect 2 slices due to address change in P3, reflected via location table):"
SELECT su.name, su.external_idents->>'tax_ident' AS tax_ident, su.physical_address_part1, su.sector_code, su.valid_from, su.valid_to
FROM public.statistical_unit su
WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = '680500001' ORDER BY su.external_idents->>'tax_ident', su.valid_from, su.valid_to;
ROLLBACK TO scenario_5_lu_three_periods;

-- Scenario 6: LU + Formal ES, three consecutive periods
SAVEPOINT scenario_6_lu_es_three_periods;
\echo "Scenario 6: LU + Formal ES, three consecutive periods (core data changes in P3 for both)"
DO $$
DECLARE
    v_definition_id INT;
    v_definition_slug TEXT := 'legal_unit_explicit_dates';
    v_job_slug TEXT := 'import_68_06_lu_periods';
    v_job_description TEXT := 'Test 68-06: LU for ES Periods';
    v_job_note TEXT := 'Importing LU part.';
    v_job_edit_comment TEXT := 'Test 68';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition with slug ''%'' not found.', v_definition_slug;
    END IF;

    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, v_job_slug, v_job_description, v_job_note, v_job_edit_comment);
END $$;
INSERT INTO public.import_68_06_lu_periods_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) VALUES
('2021-01-01','2021-03-31','680600001','LU for ES Periods','2021-01-01',NULL,'LU Addr P1','2000','Oslo','0301','NO','11.100',NULL,'2100','AS'),
('2021-04-01','2021-06-30','680600001','LU for ES Periods','2021-01-01',NULL,'LU Addr P1','2000','Oslo','0301','NO','11.100',NULL,'2100','AS'),
('2021-07-01','2021-09-30','680600001','LU for ES Periods','2021-01-01',NULL,'LU Addr P3 Changed','2000','Oslo','0301','NO','11.100',NULL,'2100','AS');

--SET LOCAL client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--RESET client_min_messages;

DO $$
DECLARE
    v_definition_id INT;
    v_definition_slug TEXT := 'establishment_for_lu_explicit_dates';
    v_job_slug TEXT := 'import_68_06_es_periods';
    v_job_description TEXT := 'Test 68-06: ES for LU Periods';
    v_job_note TEXT := 'Importing ES part.';
    v_job_edit_comment TEXT := 'Test 68';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition with slug ''%'' not found.', v_definition_slug;
    END IF;

    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, v_job_slug, v_job_description, v_job_note, v_job_edit_comment);
END $$;
INSERT INTO public.import_68_06_es_periods_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,legal_unit_tax_ident) VALUES
('2021-01-01','2021-03-31','E68060001','ES for LU Periods','2021-01-01',NULL,'ES Addr P1','2000','Oslo','0301','NO','11.100',NULL,'680600001'),
('2021-04-01','2021-06-30','E68060001','ES for LU Periods','2021-01-01',NULL,'ES Addr P1','2000','Oslo','0301','NO','11.100',NULL,'680600001'),
('2021-07-01','2021-09-30','E68060001','ES for LU Periods','2021-01-01',NULL,'ES Addr P3 Changed','2000','Oslo','0301','NO','11.100',NULL,'680600001');

--SET LOCAL client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--RESET client_min_messages;

\echo "Import job statuses for 68_06:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug LIKE 'import_68_06%' ORDER BY slug; -- Added error_details

\echo "Data table row status for import_68_06_lu_periods:" -- Added for consistency
SELECT row_id, state, error, action, operation FROM public.import_68_06_lu_periods_data ORDER BY row_id;
\echo "Data table row status for import_68_06_es_periods:" -- Added for consistency
SELECT row_id, state, error, action, operation FROM public.import_68_06_es_periods_data ORDER BY row_id;

\echo "Verification for Scenario 6: LU + ES Three Periods"
\echo "Legal Units (expect 1 slice in public.legal_unit, as address change is in location table):"
SELECT lu.name, ei.ident AS tax_ident, lu.valid_from, lu.valid_after, lu.valid_to
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident = '680600001' ORDER BY ei.ident, lu.valid_after, lu.valid_from, lu.valid_to;
\echo "Establishments (expect 1 slice in public.establishment, showing linked LU's tax_ident):"
SELECT 
    est.name, 
    est_ei.ident AS est_tax_ident, 
    lu_ei.ident AS legal_unit_tax_ident, 
    est.valid_from, 
    est.valid_after, 
    est.valid_to
FROM public.establishment est
JOIN public.external_ident est_ei ON est_ei.establishment_id = est.id
JOIN public.external_ident_type est_eit ON est_eit.id = est_ei.type_id AND est_eit.code = 'tax_ident'
LEFT JOIN public.legal_unit lu ON est.legal_unit_id = lu.id
LEFT JOIN public.external_ident lu_ei ON lu_ei.legal_unit_id = lu.id
LEFT JOIN public.external_ident_type lu_eit ON lu_eit.id = lu_ei.type_id AND lu_eit.code = 'tax_ident'
WHERE est_ei.ident = 'E68060001' 
ORDER BY est_ei.ident, est.valid_after, est.valid_from, est.valid_to;

CALL worker.process_tasks(p_queue => 'analytics');

\echo "Statistical Units (LU - expect 2 slices due to address change):"
SELECT su.name, su.external_idents->>'tax_ident' AS tax_ident, su.physical_address_part1, su.valid_from, su.valid_to
FROM public.statistical_unit su
WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = '680600001' ORDER BY su.external_idents->>'tax_ident', su.valid_from, su.valid_to;
\echo "Statistical Units (ES - expect 3 slices due to address change):"
SELECT su.name, su.external_idents->>'tax_ident' AS est_tax_ident, su.physical_address_part1, su.valid_from, su.valid_to
FROM public.statistical_unit su
WHERE su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = 'E68060001' ORDER BY su.external_idents->>'tax_ident', su.valid_from, su.valid_to;
ROLLBACK TO scenario_6_lu_es_three_periods;

-- Scenario 7: Informal ES with three consecutive periods
SAVEPOINT scenario_7_informal_es_three_periods;
\echo "Scenario 7: Informal ES with three consecutive periods (P1 data = P2 data, P3 data different)"
DO $$
DECLARE
    v_definition_id INT;
    v_definition_slug TEXT := 'establishment_without_lu_explicit_dates';
    v_job_slug TEXT := 'import_68_07_informal_es_periods';
    v_job_description TEXT := 'Test 68-07: Informal ES Three Periods';
    v_job_note TEXT := 'Importing informal ES with period changes.';
    v_job_edit_comment TEXT := 'Test 68';
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = v_definition_slug;
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition with slug ''%'' not found.', v_definition_slug;
    END IF;

    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, v_job_slug, v_job_description, v_job_note, v_job_edit_comment);
END $$;
INSERT INTO public.import_68_07_informal_es_periods_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code) VALUES
('2022-01-01','2022-03-31','E68070001','Informal ES Three Periods','2022-01-01',NULL,'Inf Addr P1','3000','Oslo','0301','NO','10.110',NULL),
('2022-04-01','2022-06-30','E68070001','Informal ES Three Periods','2022-01-01',NULL,'Inf Addr P1','3000','Oslo','0301','NO','10.110',NULL),
('2022-07-01','2022-09-30','E68070001','Informal ES Three Periods','2022-01-01',NULL,'Inf Addr P3 Changed','3000','Oslo','0301','NO','10.110',NULL);

--SET LOCAL client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--RESET client_min_messages;

\echo "Import job status for 68_07_informal_es_periods:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error, error as error_details FROM public.import_job WHERE slug = 'import_68_07_informal_es_periods' ORDER BY slug; -- Added error_details

\echo "Data table row status for import_68_07_informal_es_periods:" -- Added for consistency
SELECT row_id, state, error, action, operation FROM public.import_68_07_informal_es_periods_data ORDER BY row_id;

\echo "Verification for Scenario 7: Informal ES Three Periods"
\echo "Establishments (expect 1 slice in public.establishment, as address/activity change does not slice establishment directly):"
SELECT
    est.name,
    ei.ident AS tax_ident,
    (SELECT COUNT(*) FROM public.enterprise WHERE id = est.enterprise_id) as linked_enterprise_exists,
    est.valid_from,
    est.valid_after,
    est.valid_to
FROM public.establishment est
JOIN public.external_ident ei ON ei.establishment_id = est.id
JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident' -- Assuming informal ES uses 'tax_ident'
WHERE ei.ident = 'E68070001' ORDER BY ei.ident, est.valid_after, est.valid_from, est.valid_to;

\echo "Physical Locations for ES E68070001 (expect 2 slices due to address change):"
SELECT
    ei.ident AS tax_ident,
    loc.type,
    loc.address_part1,
    loc.valid_from,
    loc.valid_after,
    loc.valid_to
FROM public.location loc
JOIN public.external_ident ei ON loc.establishment_id = ei.establishment_id
JOIN public.external_ident_type eit ON ei.type_id = eit.id
WHERE ei.ident = 'E68070001' AND eit.code = 'tax_ident' AND loc.type = 'physical'
ORDER BY ei.ident, loc.type, loc.valid_after, loc.valid_from, loc.valid_to;

CALL worker.process_tasks(p_queue => 'analytics');

\echo "Statistical Units (ES - expect 2 slices due to location change):"
SELECT su.name, su.external_idents->>'tax_ident' AS tax_ident, su.physical_address_part1, su.valid_from, su.valid_to
FROM public.statistical_unit su
WHERE su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = 'E68070001' ORDER BY su.external_idents->>'tax_ident', su.valid_from, su.valid_to;
ROLLBACK TO scenario_7_informal_es_three_periods;

\echo "Final counts after all test blocks (should be same as initial due to rollbacks)"
SELECT
    (SELECT COUNT(*) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(*) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(*) FROM public.enterprise) AS enterprise_count;

ROLLBACK TO main_test_68_start;
\echo "Test 68 completed and rolled back to main start."

ROLLBACK; -- Final rollback for the entire transaction

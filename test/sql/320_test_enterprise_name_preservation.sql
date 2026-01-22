-- Test: Enterprise Name Preservation
-- 
-- Verifies that enterprise attributes (name, address, etc.) come from the PRIMARY 
-- legal unit or establishment, not just any unit that happens to have a later valid_from.
--
-- The fix uses a WHERE filter: primary_for_enterprise = true
-- (not ORDER BY sorting)

BEGIN;

\i test/setup.sql

-- Reset sequences for stable IDs in this test
ALTER TABLE public.legal_unit ALTER COLUMN id RESTART WITH 1;
ALTER TABLE public.establishment ALTER COLUMN id RESTART WITH 1;
ALTER TABLE public.enterprise ALTER COLUMN id RESTART WITH 1;

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

\echo 'Test: Enterprise Name Preservation During Legal Unit Linking'

-- Get Import Definition ID for Legal Units
\set import_definition_slug '''legal_unit_source_dates'''
SELECT id AS import_def_id FROM public.import_definition WHERE slug = :import_definition_slug \gset
\if :{?import_def_id}
\else
    \warn 'FAIL: Could not find import definition with slug :' :import_definition_slug '. This test requires it to exist.'
    \quit
\endif

-- Define test constants
\set user_email_literal '''test.admin@statbus.org'''
\set default_edit_comment '''Test 320 Enterprise Name Preservation'''

-- ============================================================================
-- Scenario 1: Link newer legal unit to existing enterprise
-- Enterprise name should stay with the PRIMARY legal unit
-- ============================================================================
\echo ''
\echo 'Scenario 1: Create enterprise with primary LU, then link a newer LU'
SAVEPOINT scenario_1;

-- Step 1: Create initial legal unit (becomes primary for new enterprise)
\echo 'Step 1: Creating primary legal unit "Main Company Ltd"'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test320_main_company', 'Main Company Creation', 'Test 320 Main', :default_edit_comment);

INSERT INTO public.test320_main_company_upload (
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, 
    data_source_code, birth_date, physical_address_part1, physical_postcode, 
    physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code
) VALUES (
    'MAIN001', 'Main Company Ltd', '2023-01-01', '2023-12-31', '2100', 'AS', 
    'mi', '2023-01-01', 'Main St 1', '1000', 'Oslo', '0301', 'NO', '01.110'
);

CALL worker.process_tasks(p_queue => 'import');

-- Get enterprise ID
SELECT lu.enterprise_id AS main_enterprise_id
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'MAIN001' LIMIT 1 \gset

-- Step 2: Create subsidiary with later valid_from
\echo 'Step 2: Creating subsidiary "Subsidiary Company AS" with later valid_from'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test320_subsidiary', 'Subsidiary Company Creation', 'Test 320 Sub', :default_edit_comment);

INSERT INTO public.test320_subsidiary_upload (
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, 
    data_source_code, birth_date, physical_address_part1, physical_postcode, 
    physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code
) VALUES (
    'SUB001', 'Subsidiary Company AS', '2023-06-01', '2023-12-31', '3100', 'AS', 
    'mi', '2023-06-01', 'Sub St 2', '5000', 'Bergen', '4601', 'NO', '02.100'
);

CALL worker.process_tasks(p_queue => 'import');

-- Get subsidiary legal unit ID
SELECT lu.id AS sub_legal_unit_id
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'SUB001' LIMIT 1 \gset

-- Step 3: Link subsidiary to main enterprise
\echo 'Step 3: Linking subsidiary to main enterprise'
SELECT public.connect_legal_unit_to_enterprise(
    :sub_legal_unit_id, 
    :main_enterprise_id, 
    '2023-06-01'::date, 
    'infinity'::date
) AS connection_result;

CALL worker.process_tasks(p_queue => 'analytics');

-- Step 4: Verify enterprise name is preserved
\echo 'Step 4: Verify enterprise name stays "Main Company Ltd" (from primary LU)'
SELECT 
    ten.enterprise_id,
    ten.name AS enterprise_name,
    ten.valid_from,
    ten.valid_until
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :main_enterprise_id
ORDER BY ten.valid_from;

-- Show legal units and their primary status
\echo 'Legal units in enterprise (primary_for_enterprise status):'
SELECT 
    lu.name AS legal_unit_name,
    ei.ident AS tax_ident,
    lu.primary_for_enterprise,
    lu.valid_from
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE lu.enterprise_id = :main_enterprise_id
ORDER BY lu.valid_from;

ROLLBACK TO scenario_1;
\echo 'Scenario 1 complete.'

-- ============================================================================
-- Scenario 2: Informal establishment gets formal legal unit
-- Legal unit name should take priority over establishment name
-- ============================================================================
\echo ''
\echo 'Scenario 2: Enterprise with informal ES, then connect LU - LU name takes priority'
SAVEPOINT scenario_2;

-- Get import definition for informal establishments
\set es_import_definition_slug '''establishment_without_lu_source_dates'''
SELECT id AS es_import_def_id FROM public.import_definition WHERE slug = :es_import_definition_slug \gset
\if :{?es_import_def_id}
\else
    \warn 'FAIL: Could not find import definition with slug :' :es_import_definition_slug '. This test requires it to exist.'
    \quit
\endif

-- Step 1: Create informal establishment
\echo 'Step 1: Creating informal establishment "Street Vendor Shop"'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:es_import_def_id, 'test320_informal_es', 'Informal ES', 'Test 320 Informal', :default_edit_comment);

INSERT INTO public.test320_informal_es_upload (
    tax_ident, name, valid_from, valid_to, birth_date, 
    physical_address_part1, physical_postcode, physical_postplace, 
    physical_region_code, physical_country_iso_2, primary_activity_category_code,
    data_source_code
) VALUES (
    'INFORMAL001', 'Street Vendor Shop', '2023-01-01', '2023-12-31', '2023-01-01',
    'Market Square 1', '1000', 'Oslo', '0301', 'NO', '47.810', 'mi'
);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

-- Get enterprise ID
SELECT est.enterprise_id AS informal_enterprise_id
FROM public.establishment est
JOIN public.external_ident ei ON ei.establishment_id = est.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'INFORMAL001' LIMIT 1 \gset

\echo 'Enterprise name before LU connection (from ES):'
SELECT ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :informal_enterprise_id;

-- Step 2: Create formal legal unit
\echo 'Step 2: Creating formal legal unit "Registered Business Ltd"'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test320_formal_lu', 'Formal LU', 'Test 320 Formal', :default_edit_comment);

INSERT INTO public.test320_formal_lu_upload (
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, 
    data_source_code, birth_date, physical_address_part1, physical_postcode, 
    physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code
) VALUES (
    'FORMAL001', 'Registered Business Ltd', '2023-01-01', '2023-12-31', '2100', 'AS', 
    'mi', '2023-01-01', 'Business Park 1', '1000', 'Oslo', '0301', 'NO', '47.810'
);

CALL worker.process_tasks(p_queue => 'import');

-- Get legal unit ID
SELECT lu.id AS formal_lu_id
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'FORMAL001' LIMIT 1 \gset

-- Step 3: Connect legal unit to enterprise
\echo 'Step 3: Connecting legal unit to informal enterprise'
SELECT public.connect_legal_unit_to_enterprise(
    :formal_lu_id, 
    :informal_enterprise_id, 
    '2023-01-01'::date, 
    'infinity'::date
) AS connection_result;

CALL worker.process_tasks(p_queue => 'analytics');

\echo 'Enterprise name after LU connection (should be from LU):'
SELECT ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :informal_enterprise_id;

ROLLBACK TO scenario_2;
\echo 'Scenario 2 complete.'

-- ============================================================================
-- Scenario 3: Complex Enterprise Merging with Background Noise
-- Tests: (lu1, lu2*->en1) (lu3*->en2), connect lu1->en2, connect lu2->en2, set lu1*
-- Plus unrelated units to expose join bugs
-- ============================================================================
\echo ''
\echo '============================================================================'
\echo 'Scenario 3: Complex Enterprise Merging with Background Noise'
\echo '============================================================================'
SAVEPOINT scenario_3;

-- First, create "background noise" - unrelated units that should NOT affect results
-- This exposes bugs in JOINs that might accidentally pick up wrong units

\echo 'Creating background noise: Unrelated formal LU with ES'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test320_noise_lu', 'Noise LU', 'Background noise', :default_edit_comment);

INSERT INTO public.test320_noise_lu_upload (
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, 
    data_source_code, birth_date, physical_address_part1, physical_postcode, 
    physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code
) VALUES (
    'NOISE_LU001', 'Unrelated Formal Corp', '2023-01-01', '2023-12-31', '2100', 'AS', 
    'mi', '2023-01-01', 'Noise St 99', '9999', 'Hammerfest', '5601', 'NO', '01.110'
);

CALL worker.process_tasks(p_queue => 'import');

\echo 'Creating background noise: Unrelated informal ES (no LU)'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:es_import_def_id, 'test320_noise_es', 'Noise ES', 'Background noise', :default_edit_comment);

INSERT INTO public.test320_noise_es_upload (
    tax_ident, name, valid_from, valid_to, birth_date, 
    physical_address_part1, physical_postcode, physical_postplace, 
    physical_region_code, physical_country_iso_2, primary_activity_category_code,
    data_source_code
) VALUES (
    'NOISE_ES001', 'Unrelated Street Vendor', '2023-01-01', '2023-12-31', '2023-01-01',
    'Remote Market 1', '9990', 'Vardø', '5601', 'NO', '47.810', 'mi'
);

CALL worker.process_tasks(p_queue => 'import');

\echo 'Creating background noise: Another LU without any ES'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test320_noise_lu_no_es', 'Noise LU no ES', 'Background noise', :default_edit_comment);

INSERT INTO public.test320_noise_lu_no_es_upload (
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, 
    data_source_code, birth_date, physical_address_part1, physical_postcode, 
    physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code
) VALUES (
    'NOISE_LU002', 'Holding Company Only', '2023-01-01', '2023-12-31', '6400', 'AS', 
    'mi', '2023-01-01', 'Holding St 1', '1000', 'Oslo', '0301', 'NO', '64.200'
);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo ''
\echo 'Background noise created. Now setting up main test scenario.'
\echo ''

-- Now create the main test scenario:
-- Enterprise 1: lu1 "Alpha Corp", lu2 "Beta Corp"* (primary)
-- Enterprise 2: lu3 "Gamma Corp"* (primary)

\echo 'Step 1: Creating lu1 "Alpha Corp" -> en1'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test320_alpha', 'Alpha Corp', 'Scenario 3', :default_edit_comment);

INSERT INTO public.test320_alpha_upload (
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, 
    data_source_code, birth_date, physical_address_part1, physical_postcode, 
    physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code
) VALUES (
    'ALPHA001', 'Alpha Corp', '2023-01-01', '2023-12-31', '2100', 'AS', 
    'mi', '2023-01-01', 'Alpha St 1', '1000', 'Oslo', '0301', 'NO', '62.010'
);

CALL worker.process_tasks(p_queue => 'import');

-- Get lu1 and en1 IDs
SELECT lu.id AS lu1_id, lu.enterprise_id AS en1_id
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'ALPHA001' LIMIT 1 \gset

\echo 'Step 2: Creating lu2 "Beta Corp" -> separate enterprise initially'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test320_beta', 'Beta Corp', 'Scenario 3', :default_edit_comment);

INSERT INTO public.test320_beta_upload (
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, 
    data_source_code, birth_date, physical_address_part1, physical_postcode, 
    physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code
) VALUES (
    'BETA001', 'Beta Corp', '2023-01-01', '2023-12-31', '2100', 'AS', 
    'mi', '2023-01-01', 'Beta St 2', '5000', 'Bergen', '4601', 'NO', '62.020'
);

CALL worker.process_tasks(p_queue => 'import');

-- Get lu2 ID
SELECT lu.id AS lu2_id
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'BETA001' LIMIT 1 \gset

\echo 'Step 3: Connect lu2 to en1, then set lu2 as primary for en1'
-- Connect lu2 to en1
SELECT public.connect_legal_unit_to_enterprise(:lu2_id, :en1_id, '2023-01-01'::date, 'infinity'::date) AS connect_lu2_to_en1;

-- Set lu2 as primary (so en1 name becomes "Beta Corp")
SELECT public.set_primary_legal_unit_for_enterprise(:lu2_id, '2023-01-01'::date, 'infinity'::date) AS set_lu2_primary;

CALL worker.process_tasks(p_queue => 'analytics');

\echo 'After setup - en1 should have name "Beta Corp" (from primary lu2):'
SELECT ten.enterprise_id, ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :en1_id;

\echo 'LUs in en1 (lu2 should be primary):'
SELECT ei.ident AS tax_ident, lu.name, lu.primary_for_enterprise
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE lu.enterprise_id = :en1_id
ORDER BY lu.name;

\echo 'Step 4: Creating lu3 "Gamma Corp" -> en2 (separate enterprise)'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test320_gamma', 'Gamma Corp', 'Scenario 3', :default_edit_comment);

INSERT INTO public.test320_gamma_upload (
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, 
    data_source_code, birth_date, physical_address_part1, physical_postcode, 
    physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code
) VALUES (
    'GAMMA001', 'Gamma Corp', '2023-01-01', '2023-12-31', '3500', 'AS', 
    'mi', '2023-01-01', 'Gamma St 3', '7000', 'Trondheim', '5001', 'NO', '35.110'
);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

-- Get lu3 and en2 IDs
SELECT lu.id AS lu3_id, lu.enterprise_id AS en2_id
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'GAMMA001' LIMIT 1 \gset

\echo ''
\echo 'Initial state established:'
\echo '  en1: lu1 "Alpha Corp", lu2 "Beta Corp"* (primary) -> enterprise name "Beta Corp"'
\echo '  en2: lu3 "Gamma Corp"* (primary) -> enterprise name "Gamma Corp"'
\echo ''

\echo 'Current enterprise names:'
SELECT ten.enterprise_id, ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id IN (:en1_id, :en2_id)
ORDER BY ten.enterprise_id;

-- ============================================================================
-- Now the critical test sequence
-- ============================================================================

\echo ''
\echo '--- TEST SEQUENCE START ---'
\echo ''

\echo 'Step 5: Connect lu1 (non-primary) from en1 to en2'
\echo 'Expected: en2 name stays "Gamma Corp" (lu3 is still primary for en2)'
SELECT public.connect_legal_unit_to_enterprise(:lu1_id, :en2_id, '2023-01-01'::date, 'infinity'::date) AS connect_lu1_to_en2;
CALL worker.process_tasks(p_queue => 'analytics');

\echo 'After moving lu1 to en2:'
\echo 'en1 enterprise name (should still be "Beta Corp"):'
SELECT ten.enterprise_id, ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :en1_id;

\echo 'en2 enterprise name (should still be "Gamma Corp" - lu3 is primary):'
SELECT ten.enterprise_id, ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :en2_id;

\echo 'LUs in en2 (lu3 should be primary):'
SELECT ei.ident AS tax_ident, lu.name, lu.primary_for_enterprise
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE lu.enterprise_id = :en2_id
ORDER BY lu.name;

\echo ''
\echo 'Step 6: Connect lu2 (primary of en1) to en2'
\echo 'Expected: en1 should be DELETED (no LUs left), en2 name stays "Gamma Corp"'
SELECT public.connect_legal_unit_to_enterprise(:lu2_id, :en2_id, '2023-01-01'::date, 'infinity'::date) AS connect_lu2_to_en2;
CALL worker.process_tasks(p_queue => 'analytics');

\echo 'After moving lu2 to en2:'
\echo 'en1 should be deleted (expecting 0 rows):'
SELECT ten.enterprise_id, ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :en1_id;

\echo 'en1 enterprise should not exist (expecting 0 rows):'
SELECT id FROM public.enterprise WHERE id = :en1_id;

\echo 'en2 enterprise name (should still be "Gamma Corp"):'
SELECT ten.enterprise_id, ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :en2_id;

\echo 'All LUs now in en2 (lu3 still primary):'
SELECT ei.ident AS tax_ident, lu.name, lu.primary_for_enterprise
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE lu.enterprise_id = :en2_id
ORDER BY lu.name;

\echo ''
\echo 'Step 7: Set lu1 as primary for en2'
\echo 'Expected: en2 name changes to "Alpha Corp"'
SELECT public.set_primary_legal_unit_for_enterprise(:lu1_id, '2023-01-01'::date, 'infinity'::date) AS set_lu1_primary;
CALL worker.process_tasks(p_queue => 'analytics');

\echo 'After setting lu1 as primary:'
\echo 'en2 enterprise name (should now be "Alpha Corp"):'
SELECT ten.enterprise_id, ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :en2_id;

\echo 'Final LU state in en2 (lu1 should be primary now):'
SELECT ei.ident AS tax_ident, lu.name, lu.primary_for_enterprise
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE lu.enterprise_id = :en2_id
ORDER BY lu.name;

\echo ''
\echo '--- VERIFICATION: Background noise should be unaffected ---'
\echo ''

\echo 'Noise LU enterprise should exist and have correct name:'
SELECT ten.name AS enterprise_name
FROM public.timeline_enterprise ten
JOIN public.legal_unit lu ON lu.enterprise_id = ten.enterprise_id
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'NOISE_LU001';

\echo 'Noise ES (informal) enterprise should exist and have correct name:'
SELECT ten.name AS enterprise_name
FROM public.timeline_enterprise ten
JOIN public.establishment es ON es.enterprise_id = ten.enterprise_id
JOIN public.external_ident ei ON ei.establishment_id = es.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'NOISE_ES001';

\echo 'Noise LU (no ES) enterprise should exist and have correct name:'
SELECT ten.name AS enterprise_name
FROM public.timeline_enterprise ten
JOIN public.legal_unit lu ON lu.enterprise_id = ten.enterprise_id
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'NOISE_LU002';

\echo ''
\echo 'Scenario 3 Summary:'
\echo '  1. Created background noise (unrelated LU with ES, informal ES, LU without ES)'
\echo '  2. Set up en1 with lu1 + lu2* (primary), en2 with lu3* (primary)'
\echo '  3. Moved lu1 to en2 -> en2 name stayed "Gamma Corp" (correct)'
\echo '  4. Moved lu2 to en2 -> en1 deleted, en2 name stayed "Gamma Corp" (correct)'
\echo '  5. Set lu1 as primary -> en2 name changed to "Alpha Corp" (correct)'
\echo '  6. Background noise unaffected throughout (correct)'

ROLLBACK TO scenario_3;
\echo 'Scenario 3 complete.'

-- ============================================================================
-- Scenario 4: Primary establishment handling with mixed formal/informal units
-- Tests that ES primary_for_enterprise is respected when no primary LU exists
-- ============================================================================
\echo ''
\echo '============================================================================'
\echo 'Scenario 4: Informal ES becomes formal - primary ES handling'
\echo '============================================================================'
SAVEPOINT scenario_4;

\echo 'Step 1: Create informal ES "Market Stall" -> en1'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:es_import_def_id, 'test320_market_stall', 'Market Stall', 'Scenario 4', :default_edit_comment);

INSERT INTO public.test320_market_stall_upload (
    tax_ident, name, valid_from, valid_to, birth_date, 
    physical_address_part1, physical_postcode, physical_postplace, 
    physical_region_code, physical_country_iso_2, primary_activity_category_code,
    data_source_code
) VALUES (
    'STALL001', 'Market Stall', '2023-01-01', '2023-12-31', '2023-01-01',
    'Town Square 1', '1000', 'Oslo', '0301', 'NO', '47.810', 'mi'
);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

-- Get ES and enterprise IDs
SELECT es.id AS es1_id, es.enterprise_id AS es1_en_id
FROM public.establishment es
JOIN public.external_ident ei ON ei.establishment_id = es.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'STALL001' LIMIT 1 \gset

\echo 'Initial enterprise name (from informal ES):'
SELECT ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :es1_en_id;

\echo 'Step 2: Create second informal ES "Food Cart" -> separate enterprise'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:es_import_def_id, 'test320_food_cart', 'Food Cart', 'Scenario 4', :default_edit_comment);

INSERT INTO public.test320_food_cart_upload (
    tax_ident, name, valid_from, valid_to, birth_date, 
    physical_address_part1, physical_postcode, physical_postplace, 
    physical_region_code, physical_country_iso_2, primary_activity_category_code,
    data_source_code
) VALUES (
    'CART001', 'Food Cart', '2023-01-01', '2023-12-31', '2023-01-01',
    'Station Plaza 1', '1000', 'Oslo', '0301', 'NO', '56.102', 'mi'
);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

-- Get ES2 ID
SELECT es.id AS es2_id, es.enterprise_id AS es2_en_id
FROM public.establishment es
JOIN public.external_ident ei ON ei.establishment_id = es.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'CART001' LIMIT 1 \gset

\echo 'Step 3: Create formal LU "Registered Vendor Ltd" and connect to es1 enterprise'
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
VALUES (:import_def_id, 'test320_vendor_lu', 'Vendor LU', 'Scenario 4', :default_edit_comment);

INSERT INTO public.test320_vendor_lu_upload (
    tax_ident, name, valid_from, valid_to, sector_code, legal_form_code, 
    data_source_code, birth_date, physical_address_part1, physical_postcode, 
    physical_postplace, physical_region_code, physical_country_iso_2, primary_activity_category_code
) VALUES (
    'VENDOR001', 'Registered Vendor Ltd', '2023-01-01', '2023-12-31', '2100', 'AS', 
    'mi', '2023-01-01', 'Vendor St 1', '1000', 'Oslo', '0301', 'NO', '47.810'
);

CALL worker.process_tasks(p_queue => 'import');

-- Get LU ID
SELECT lu.id AS vendor_lu_id
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE ei.ident = 'VENDOR001' LIMIT 1 \gset

\echo 'Connect LU to es1 enterprise (LU name should take priority):'
SELECT public.connect_legal_unit_to_enterprise(:vendor_lu_id, :es1_en_id, '2023-01-01'::date, 'infinity'::date) AS connect_result;
CALL worker.process_tasks(p_queue => 'analytics');

\echo 'Enterprise name after LU connection (should be "Registered Vendor Ltd"):'
SELECT ten.name AS enterprise_name
FROM public.timeline_enterprise ten
WHERE ten.enterprise_id = :es1_en_id;

\echo 'Units in enterprise:'
SELECT 'LU' AS type, ei.ident, lu.name, lu.primary_for_enterprise
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE lu.enterprise_id = :es1_en_id
UNION ALL
SELECT 'ES' AS type, ei.ident, es.name, es.primary_for_enterprise
FROM public.establishment es
JOIN public.external_ident ei ON ei.establishment_id = es.id AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
WHERE es.enterprise_id = :es1_en_id
ORDER BY type, name;

ROLLBACK TO scenario_4;
\echo 'Scenario 4 complete.'

ROLLBACK;

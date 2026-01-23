SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

\echo "Test 113: Hierarchical External Identifiers - Basic Functionality"
\echo "Testing hierarchical external identifier constraints, validation, and queries"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

SELECT acs.code FROM public.settings AS s JOIN activity_category_standard AS acs ON s.activity_category_standard_id = acs.id;

SAVEPOINT main_test_113_start;
\echo "Initial counts before any test block for Test 113"
SELECT
    (SELECT COUNT(*) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(*) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(*) FROM public.enterprise) AS enterprise_count;

-- ============================================================================
-- Test 113.1: Hierarchical External Identifiers - Basic Setup and Constraints
-- ============================================================================
\echo "=============================================================="
\echo "Test 113.1: Hierarchical External Identifiers - Basic Setup"
\echo "=============================================================="
SAVEPOINT scenario_113_1_hierarchical_setup;

-- Setup: Create hierarchical identifier types
\echo "Setting up hierarchical identifier types"
INSERT INTO public.external_ident_type (code, name, shape, labels, description, priority, archived)
VALUES ('test_surveyor_hierarchical', 'Test Surveyor Hierarchical', 'hierarchical', 'region.city.seq',
        'Region/City/Seq hierarchical composite key', 50, false);

INSERT INTO public.external_ident_type (code, name, shape, labels, description, priority, archived)
VALUES ('region_district', 'Regional District Code', 'hierarchical', 'region.district',
        'Simple 2-level regional district identifier', 51, false);

-- Verify the hierarchical setup
\echo "Verifying hierarchical setup:"
SELECT eit.code, eit.shape, eit.labels, eit.priority
FROM public.external_ident_type eit
WHERE eit.code IN ('test_surveyor_hierarchical', 'region_district')
ORDER BY eit.priority;

ROLLBACK TO scenario_113_1_hierarchical_setup;

-- ============================================================================
-- Test 113.2: Hierarchical External Identifiers - Constraint Validation (Error Cases)
-- ============================================================================
\echo "=============================================================="
\echo "Test 113.2: Hierarchical Constraint Validation - Error Cases"
\echo "=============================================================="
SAVEPOINT scenario_113_2_hierarchical_constraints;

-- Setup: Create a hierarchical identifier type (Uganda-style: region.city.seq)
\echo "Setting up hierarchical identifier type for constraint testing"
INSERT INTO public.external_ident_type (code, name, description, priority, shape, labels)
VALUES ('test_surveyor', 'Test Surveyor Hierarchical', 'Region/City/Seq hierarchical identifier', 50, 'hierarchical', 'region.city.seq');

-- Verify the hierarchical setup
\echo "Verifying hierarchical setup:"
SELECT code, shape, labels, priority
FROM public.external_ident_type
WHERE code = 'test_surveyor';

-- Test 113.2.1: Invalid hierarchical identifier depth mismatch (should fail due to constraint)
\echo "Test 113.2.1: Attempting to insert hierarchical identifier with depth mismatch (should fail):"
DO $$
DECLARE
    v_user_id INT;
    v_ent_id INT;
    v_lu_id INT;
    v_surveyor_type_id INT;
BEGIN
    SELECT id INTO v_user_id FROM public.user WHERE email = 'test.admin@statbus.org';
    SELECT id INTO v_surveyor_type_id FROM public.external_ident_type WHERE code = 'test_surveyor';
    
    -- Create a legal unit
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('ENT HierTest', v_user_id, now()) RETURNING id INTO v_ent_id;
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES (v_ent_id, 'LU Hierarchical', (SELECT id FROM public.status WHERE code = 'active'), true, v_user_id, now(), '2023-01-01') RETURNING id INTO v_lu_id;
    
    -- Try to insert hierarchical identifier with wrong depth (2 levels vs required 3) - should fail
    INSERT INTO public.external_ident (legal_unit_id, type_id, idents, labels, shape, edit_by_user_id, edit_at)
    VALUES (v_lu_id, v_surveyor_type_id, 'north.kampala', 'region.city', 'hierarchical', v_user_id, now());
    
    RAISE EXCEPTION 'ERROR: Depth mismatch should have been prevented!';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%hierarchical_depth_valid%' THEN
        RAISE NOTICE 'Test 113.2.1: Correctly caught hierarchical depth constraint violation';
    ELSE
        RAISE NOTICE 'Test 113.2.1: Hierarchical identifier validation error: %', SQLERRM;
    END IF;
END $$;

-- Test 113.2.2: Valid hierarchical identifier (should succeed)
\echo "Test 113.2.2: Inserting valid hierarchical identifier:"
DO $$
DECLARE
    v_user_id INT;
    v_ent_id INT;
    v_lu_id INT;
    v_surveyor_type_id INT;
BEGIN
    SELECT id INTO v_user_id FROM public.user WHERE email = 'test.admin@statbus.org';
    SELECT id INTO v_surveyor_type_id FROM public.external_ident_type WHERE code = 'test_surveyor';
    
    -- Create a legal unit
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('ENT HierValid', v_user_id, now()) RETURNING id INTO v_ent_id;
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES (v_ent_id, 'LU Valid Hierarchical', (SELECT id FROM public.status WHERE code = 'active'), true, v_user_id, now(), '2023-01-01') RETURNING id INTO v_lu_id;
    
    -- Insert complete hierarchical identifier
    INSERT INTO public.external_ident (legal_unit_id, type_id, idents, labels, shape, edit_by_user_id, edit_at)
    VALUES (v_lu_id, v_surveyor_type_id, 'north.kampala.001', 'region.city.seq', 'hierarchical', v_user_id, now());
    
    RAISE NOTICE 'Test 113.2.2: Valid hierarchical identifier inserted successfully';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Test 113.2.2: Unexpected error: %', SQLERRM;
END $$;

-- Test 113.2.3: Test shape/labels consistency constraint
\echo "Test 113.2.3: Testing shape/labels consistency constraint:"
DO $$
BEGIN
    -- Try to create regular identifier type with labels (should fail)
    INSERT INTO public.external_ident_type (code, name, description, priority, shape, labels)
    VALUES ('test_invalid', 'Test Invalid', 'Should fail', 60, 'regular', 'some.labels');
    
    RAISE EXCEPTION 'ERROR: Regular identifier with labels should have been prevented!';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%shape_labels_consistency%' OR SQLERRM LIKE '%violates check constraint%' THEN
        RAISE NOTICE 'Test 113.2.3a: Correctly caught regular+labels constraint violation';
    ELSE
        RAISE NOTICE 'Test 113.2.3a: Unexpected error: %', SQLERRM;
    END IF;
END $$;

DO $$
BEGIN
    -- Try to create hierarchical identifier type without labels (should fail)
    INSERT INTO public.external_ident_type (code, name, description, priority, shape, labels)
    VALUES ('test_invalid2', 'Test Invalid 2', 'Should fail', 61, 'hierarchical', NULL);
    
    RAISE EXCEPTION 'ERROR: Hierarchical identifier without labels should have been prevented!';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%shape_labels_consistency%' OR SQLERRM LIKE '%violates check constraint%' THEN
        RAISE NOTICE 'Test 113.2.3b: Correctly caught hierarchical+no labels constraint violation';
    ELSE
        RAISE NOTICE 'Test 113.2.3b: Unexpected error: %', SQLERRM;
    END IF;
END $$;

ROLLBACK TO scenario_113_2_hierarchical_constraints;

-- ============================================================================
-- Test 113.3: Hierarchical External Identifiers - Happy Path Testing
-- ============================================================================
\echo "=============================================================="
\echo "Test 113.3: Hierarchical External Identifiers - Happy Path"
\echo "=============================================================="
SAVEPOINT scenario_113_3_hierarchical_happy_path;

-- Setup: Create hierarchical identifier types
\echo "Setting up hierarchical identifier types"
INSERT INTO public.external_ident_type (code, name, shape, labels, description, priority, archived)
VALUES ('test_hierarchical_surveyor', 'Test Hierarchical Surveyor', 'hierarchical', 'region.city.seq',
        'Region/City/Seq hierarchical composite key', 50, false);

INSERT INTO public.external_ident_type (code, name, shape, labels, description, priority, archived)
VALUES ('region_district', 'Regional District Code', 'hierarchical', 'region.district',
        'Simple 2-level regional district identifier for success test', 51, false);

-- Verify the hierarchical setup
\echo "Verifying hierarchical setup:"
SELECT eit.code, eit.shape, eit.labels, eit.priority
FROM public.external_ident_type eit
WHERE eit.code IN ('test_hierarchical_surveyor', 'region_district')
ORDER BY eit.priority;

-- Test: Create legal units with hierarchical identifiers
\echo "Creating test legal units with hierarchical identifiers"
DO $$
DECLARE
    v_user_id INT;
    v_ent_id INT;
    v_lu_id INT;
    v_hier_type_id INT;
BEGIN
    SELECT id INTO v_user_id FROM public.user WHERE email = 'test.admin@statbus.org';
    SELECT id INTO v_hier_type_id FROM public.external_ident_type WHERE code = 'test_hierarchical_surveyor';
    
    -- LU1: NORTH.KAMPALA.001
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('ENT NK 001', v_user_id, now()) RETURNING id INTO v_ent_id;
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES (v_ent_id, 'LU North Kampala 001', (SELECT id FROM public.status WHERE code = 'active'), true, v_user_id, now(), '2023-01-01') RETURNING id INTO v_lu_id;
    INSERT INTO public.external_ident (legal_unit_id, type_id, idents, edit_by_user_id, edit_at)
    VALUES (v_lu_id, v_hier_type_id, 'NORTH.KAMPALA.001'::ltree, v_user_id, now());
    
    -- LU2: NORTH.KAMPALA.002 (same region/city, different seq - VALID)
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('ENT NK 002', v_user_id, now()) RETURNING id INTO v_ent_id;
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES (v_ent_id, 'LU North Kampala 002', (SELECT id FROM public.status WHERE code = 'active'), true, v_user_id, now(), '2023-01-01') RETURNING id INTO v_lu_id;
    INSERT INTO public.external_ident (legal_unit_id, type_id, idents, edit_by_user_id, edit_at)
    VALUES (v_lu_id, v_hier_type_id, 'NORTH.KAMPALA.002'::ltree, v_user_id, now());
    
    -- LU3: SOUTH.ENTEBBE.001 (different region/city, same seq - VALID)
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('ENT SE 001', v_user_id, now()) RETURNING id INTO v_ent_id;
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES (v_ent_id, 'LU South Entebbe 001', (SELECT id FROM public.status WHERE code = 'active'), true, v_user_id, now(), '2023-01-01') RETURNING id INTO v_lu_id;
    INSERT INTO public.external_ident (legal_unit_id, type_id, idents, edit_by_user_id, edit_at)
    VALUES (v_lu_id, v_hier_type_id, 'SOUTH.ENTEBBE.001'::ltree, v_user_id, now());
    
END $$;

-- Verify hierarchical identifiers were stored correctly
\echo "Verifying hierarchical identifiers stored correctly:"
SELECT 
    ei.idents,
    ei.labels,
    eit.code as type_code,
    eit.shape,
    nlevel(ei.idents) as actual_depth,
    nlevel(ei.labels) as expected_depth,
    lu.name as legal_unit_name
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id
JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id
WHERE eit.code = 'test_hierarchical_surveyor'
ORDER BY lu.name;

-- Test hierarchical queries: find all units in NORTH region
\echo "Testing hierarchical queries - all units in NORTH region:"
SELECT 
    ei.idents,
    lu.name as legal_unit_name
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id
JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id
WHERE eit.code = 'test_hierarchical_surveyor'
  AND ei.idents ~ 'NORTH.*'::lquery
ORDER BY ei.idents;

-- Test hierarchical queries: find all units in NORTH.KAMPALA district
\echo "Testing hierarchical queries - all units in NORTH.KAMPALA district:"
SELECT 
    ei.idents,
    lu.name as legal_unit_name
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id
JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id
WHERE eit.code = 'test_hierarchical_surveyor'
  AND ei.idents ~ 'NORTH.KAMPALA.*'::lquery
ORDER BY ei.idents;

-- Verify uniqueness: each complete hierarchical path is unique
\echo "Verifying uniqueness: each hierarchical identifier is unique:"
SELECT 
    ei.idents as hierarchical_key,
    COUNT(*) as occurrences,
    array_agg(DISTINCT lu.name) as legal_units
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id
JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id
WHERE eit.code = 'test_hierarchical_surveyor'
GROUP BY ei.idents
ORDER BY ei.idents;

-- Test successful insertion of different hierarchical identifier type
\echo "Testing successful insertion of 2-level hierarchical identifier:"
DO $$
DECLARE
    v_user_id INT;
    v_ent_id INT;
    v_lu_id INT;
    v_region_district_type_id INT;
BEGIN
    SELECT id INTO v_user_id FROM public.user WHERE email = 'test.admin@statbus.org';
    SELECT id INTO v_region_district_type_id FROM public.external_ident_type WHERE code = 'region_district';
    
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('ENT Happy Path', v_user_id, now()) RETURNING id INTO v_ent_id;
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES (v_ent_id, 'Test Happy Path Unit', (SELECT id FROM public.status WHERE code = 'active'), true, v_user_id, now(), '2023-01-01') RETURNING id INTO v_lu_id;
    
    -- Test successful hierarchical identifier insertion
    INSERT INTO public.external_ident (legal_unit_id, type_id, idents, edit_by_user_id, edit_at)
    VALUES (v_lu_id, v_region_district_type_id, 'WEST.MBARARA'::ltree, v_user_id, now());
    
    RAISE NOTICE 'Successfully inserted 2-level hierarchical identifier: region_district = WEST.MBARARA';
END $$;

-- Verify it was created correctly
\echo "Verify successful 2-level hierarchical identifier creation:"
SELECT 
    eit.code,
    eit.shape,
    eit.labels,
    ei.idents,
    nlevel(ei.idents) as actual_depth,
    nlevel(ei.labels) as expected_depth,
    lu.name
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id  
JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id
WHERE eit.code = 'region_district';

-- Test hierarchical ancestor/descendant queries
\echo "Testing hierarchical ancestor queries - find ancestors of NORTH.KAMPALA.001:"
SELECT 
    subltree(ei.idents, 0, 1) as region_level,
    subltree(ei.idents, 0, 2) as district_level,
    ei.idents as full_path,
    lu.name
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id
JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id
WHERE eit.code = 'test_hierarchical_surveyor'
  AND ei.idents = 'NORTH.KAMPALA.001'::ltree;

-- Test ltree operations: find all sequences (level 3) in the NORTH region
\echo "Testing ltree level extraction - all sequences in NORTH region:"
SELECT 
    subpath(ei.idents, 2, 1) as sequence_number,
    ei.idents as full_path,
    lu.name
FROM public.external_ident ei
JOIN public.external_ident_type eit ON eit.id = ei.type_id
JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id
WHERE eit.code = 'test_hierarchical_surveyor'
  AND ei.idents ~ 'NORTH.*'::lquery
ORDER BY ei.idents;

ROLLBACK TO scenario_113_3_hierarchical_happy_path;

\echo "Final counts after all test blocks for Test 113 (should be same as initial due to rollbacks)"
SELECT
    (SELECT COUNT(*) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(*) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(*) FROM public.enterprise) AS enterprise_count;

ROLLBACK TO main_test_113_start;
\echo "Test 113 completed and rolled back to main start."

ROLLBACK; -- Final rollback for the entire transaction
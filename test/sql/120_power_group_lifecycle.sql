BEGIN;

\i test/setup.sql

\echo "=== Test 120: Power Group Lifecycle ==="
\echo "Tests deep chains, boundary conditions, dissolution, migration, import rounds, PG reuse"

-- Reset power_group sequence for deterministic output
ALTER SEQUENCE public.power_group_ident_seq RESTART WITH 1;

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

-- Load base configuration (regions, activity categories, status codes, etc.)
\i samples/norway/getting-started.sql

-- Seed test relationship types
-- parent_company: structurally 1:1 (a subsidiary has at most one parent) → TRUE
-- co_ownership: structurally 1:N (multiple co-owners per entity) → FALSE
INSERT INTO public.legal_rel_type (code, name, description, primary_influencer_only, enabled, custom)
SELECT 'parent_company', 'Parent Company', 'Parent-subsidiary relationship (structurally 1:1 per subsidiary)', TRUE, true, false
WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type WHERE code = 'parent_company');

INSERT INTO public.legal_rel_type (code, name, description, primary_influencer_only, enabled, custom)
SELECT 'co_ownership', 'Co-ownership', 'Shared ownership (multiple co-owners per entity)', FALSE, true, false
WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type WHERE code = 'co_ownership');

-- ============================================================================
-- PHASE 2: Direct Scenarios (isolated by SAVEPOINT)
-- ============================================================================

SAVEPOINT phase2_start;

\echo "=== Phase 2: Create Legal Units for Direct Scenarios ==="

-- Create 12 enterprises (one per LU, since each is primary_for_enterprise)
INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT 'LC' || n, (SELECT id FROM auth.user LIMIT 1), 'Lifecycle test enterprise ' || n
FROM generate_series(1, 12) AS n;

-- Create 12 legal units for Phase 2 scenarios
INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Apex Corp',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC1'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Root of Group A';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Apex Manufacturing',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC2'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Subsidiary of Apex';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Apex Logistics',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC3'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Subsidiary of Apex Manufacturing';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Apex Research',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC4'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Subsidiary of Apex Logistics (4-level deep)';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Beacon Inc',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC5'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Root of Group B';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Beacon Services',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC6'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Subsidiary of Beacon (50%)';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Beacon Tech',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC7'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Subsidiary of Beacon (co_ownership type, not primary_influencer_only)';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Crossroads Ltd',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC8'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Moves between groups';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Delta Holdings',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC9'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Root of Group D (to be dissolved)';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Delta Subsidiary',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC10'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Subsidiary of Delta';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Echo Standalone',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC11'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Never in any group';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'Foxtrot Corp',
    (SELECT id FROM public.enterprise WHERE short_name = 'LC12'), true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'For self-reference test';

\echo "Phase 2 legal units created:"
SELECT name FROM public.legal_unit
WHERE name IN ('Apex Corp', 'Apex Manufacturing', 'Apex Logistics', 'Apex Research',
               'Beacon Inc', 'Beacon Services', 'Beacon Tech', 'Crossroads Ltd',
               'Delta Holdings', 'Delta Subsidiary', 'Echo Standalone', 'Foxtrot Corp')
ORDER BY name;

-- ============================================================================
\echo "=== 2a: Deep Chain (4 levels) ==="
-- ============================================================================
-- Apex Corp → Apex Manufacturing (60%) → Apex Logistics (75%) → Apex Research (100%)

INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Apex Corp'),
    (SELECT id FROM public.legal_unit WHERE name = 'Apex Manufacturing'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    60.00, (SELECT id FROM auth.user LIMIT 1), 'Apex owns 60% of Manufacturing';

INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Apex Manufacturing'),
    (SELECT id FROM public.legal_unit WHERE name = 'Apex Logistics'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    75.00, (SELECT id FROM auth.user LIMIT 1), 'Manufacturing owns 75% of Logistics';

INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Apex Logistics'),
    (SELECT id FROM public.legal_unit WHERE name = 'Apex Research'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    100.00, (SELECT id FROM auth.user LIMIT 1), 'Logistics owns 100% of Research';

SELECT worker.derive_power_groups();

\echo "2a: Hierarchy shows 4 power levels"
SELECT lu.name, h.power_level
FROM public.legal_unit_power_hierarchy AS h
JOIN public.legal_unit AS lu ON lu.id = h.legal_unit_id AND lu.valid_range && h.valid_range
WHERE lu.name LIKE 'Apex%'
ORDER BY h.power_level, lu.name;

\echo "2a: power_group_def depth and reach"
SELECT lu.name AS root_legal_unit, pgd.depth, pgd.reach
FROM public.power_group_def AS pgd
JOIN public.legal_unit AS lu ON lu.id = pgd.root_legal_unit_id
WHERE lu.name = 'Apex Corp';

\echo "2a: power_group_membership includes all 4 Apex units"
SELECT pgm.power_group_ident, lu.name, pgm.power_level
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
WHERE lu.name LIKE 'Apex%'
ORDER BY pgm.power_level, lu.name;

-- ============================================================================
\echo "=== 2b: Primary Influencer vs Non-Primary ==="
-- ============================================================================
-- Beacon → Beacon Services (parent_company, primary_influencer_only=TRUE) — forms PG
-- Beacon → Beacon Tech (co_ownership, primary_influencer_only=FALSE) — NOT in PG

INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Beacon Inc'),
    (SELECT id FROM public.legal_unit WHERE name = 'Beacon Services'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    50.00, (SELECT id FROM auth.user LIMIT 1), 'Beacon is parent of Services (parent_company=primary_influencer_only)';

INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Beacon Inc'),
    (SELECT id FROM public.legal_unit WHERE name = 'Beacon Tech'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'co_ownership'),
    49.00, (SELECT id FROM auth.user LIMIT 1), 'Beacon co-owns Tech (co_ownership=NOT primary_influencer_only)';

SELECT worker.derive_power_groups();

\echo "2b: Beacon group has Beacon Inc + Beacon Services only (NOT Beacon Tech)"
SELECT pgm.power_group_ident, lu.name
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
WHERE lu.name LIKE 'Beacon%'
ORDER BY lu.name;

\echo "2b: Beacon Tech relationship has NULL power_group_id"
SELECT influenced.name, lr.percentage, lr.power_group_id IS NULL AS no_power_group
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influenced ON lr.influenced_id = influenced.id
WHERE influenced.name = 'Beacon Tech';

\echo "2b: Echo Standalone is NOT in any power group"
SELECT COUNT(*) AS echo_memberships
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
WHERE lu.name = 'Echo Standalone';

-- ============================================================================
\echo "=== 2c: Dissolution ==="
-- ============================================================================
-- Delta → Delta Subsidiary (parent_company, primary_influencer_only=TRUE) — creates group,
-- then type changes to co_ownership (primary_influencer_only=FALSE)

INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Delta Holdings'),
    (SELECT id FROM public.legal_unit WHERE name = 'Delta Subsidiary'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    80.00, (SELECT id FROM auth.user LIMIT 1), 'Delta owns 80% of Subsidiary';

SELECT worker.derive_power_groups();

\echo "2c: Delta power group exists before dissolution"
SELECT pgm.power_group_ident, lu.name
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
WHERE lu.name LIKE 'Delta%'
ORDER BY lu.name;

-- Change type to co_ownership (primary_influencer_only=FALSE) — dissolves PG
UPDATE public.legal_relationship
SET type_id = (SELECT id FROM public.legal_rel_type WHERE code = 'co_ownership'),
    percentage = 30.00, edit_comment = 'Delta relationship downgraded to co_ownership type'
WHERE influencing_id = (SELECT id FROM public.legal_unit WHERE name = 'Delta Holdings')
  AND influenced_id = (SELECT id FROM public.legal_unit WHERE name = 'Delta Subsidiary');

SELECT worker.derive_power_groups();

\echo "2c: After dissolution — Delta membership empty"
SELECT pgm.power_group_ident, lu.name
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
WHERE lu.name LIKE 'Delta%'
ORDER BY lu.name;

\echo "2c: Delta relationship power_group_id cleared"
SELECT influencer.name, influenced.name, lr.percentage, lr.power_group_id IS NULL AS cleared
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influencer ON lr.influencing_id = influencer.id
JOIN public.legal_unit AS influenced ON lr.influenced_id = influenced.id
WHERE influencer.name = 'Delta Holdings';

-- ============================================================================
\echo "=== 2d: Unit Migration Between Power Groups ==="
-- ============================================================================
-- Crossroads initially owned by Beacon, then moved to Apex

INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Beacon Inc'),
    (SELECT id FROM public.legal_unit WHERE name = 'Crossroads Ltd'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    60.00, (SELECT id FROM auth.user LIMIT 1), 'Beacon owns 60% of Crossroads';

SELECT worker.derive_power_groups();

\echo "2d: Crossroads initially in Beacon group"
SELECT pgm.power_group_ident, lu.name
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
WHERE lu.name IN ('Beacon Inc', 'Beacon Services', 'Crossroads Ltd')
ORDER BY pgm.power_group_ident, lu.name;

-- Move Crossroads from Beacon to Apex
DELETE FROM public.legal_relationship
WHERE influencing_id = (SELECT id FROM public.legal_unit WHERE name = 'Beacon Inc')
  AND influenced_id = (SELECT id FROM public.legal_unit WHERE name = 'Crossroads Ltd');

INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Apex Corp'),
    (SELECT id FROM public.legal_unit WHERE name = 'Crossroads Ltd'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    70.00, (SELECT id FROM auth.user LIMIT 1), 'Apex acquires 70% of Crossroads';

SELECT worker.derive_power_groups();

\echo "2d: Crossroads moved to Apex group"
SELECT pgm.power_group_ident, lu.name
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
WHERE lu.name IN ('Apex Corp', 'Apex Manufacturing', 'Apex Logistics', 'Apex Research', 'Crossroads Ltd')
ORDER BY pgm.power_group_ident, pgm.power_level, lu.name;

\echo "2d: Beacon group now has only Beacon Inc + Beacon Services"
SELECT pgm.power_group_ident, lu.name
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
WHERE lu.name LIKE 'Beacon%'
ORDER BY lu.name;

-- ============================================================================
\echo "=== 2e: Cycle and Self-Reference Prevention ==="
-- ============================================================================

\echo "2e: Attempt cycle: Apex Research → Apex Corp (4-level cycle)"
DO $$
BEGIN
    INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
    SELECT '2020-01-01'::date,
        (SELECT id FROM public.legal_unit WHERE name = 'Apex Research'),
        (SELECT id FROM public.legal_unit WHERE name = 'Apex Corp'),
        (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
        30.00, (SELECT id FROM auth.user LIMIT 1), 'SHOULD FAIL - cycle';
    RAISE EXCEPTION 'TEST FAILURE: Circular ownership was allowed!';
EXCEPTION
    WHEN raise_exception THEN
        IF SQLERRM LIKE 'Circular ownership detected%' THEN
            RAISE NOTICE 'PASS: Circular ownership correctly prevented';
        ELSE
            RAISE;
        END IF;
    WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Circular ownership prevented with: %', SQLERRM;
END;
$$;

\echo "2e: Attempt self-reference: Foxtrot → Foxtrot"
DO $$
DECLARE
    _foxtrot_id integer;
BEGIN
    SELECT id INTO _foxtrot_id FROM public.legal_unit WHERE name = 'Foxtrot Corp' LIMIT 1;
    INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
    VALUES ('2020-01-01'::date, _foxtrot_id, _foxtrot_id,
        (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
        100.00, (SELECT id FROM auth.user LIMIT 1), 'SHOULD FAIL - self-reference');
    RAISE EXCEPTION 'TEST FAILURE: Self-reference was allowed!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASS: Self-reference prevented (CHECK constraint)';
    WHEN OTHERS THEN
        IF SQLERRM LIKE 'Circular ownership detected%' THEN
            RAISE NOTICE 'PASS: Self-reference prevented (cycle detection)';
        ELSE
            RAISE NOTICE 'PASS: Self-reference prevented: %', SQLERRM;
        END IF;
END;
$$;

\echo "2e: No invalid relationships created"
SELECT COUNT(*) AS invalid_rels FROM public.legal_relationship WHERE edit_comment LIKE '%SHOULD FAIL%';

-- ============================================================================
\echo "=== Phase 2 Summary ==="
-- ============================================================================

\echo "All power groups after Phase 2:"
SELECT pg.ident FROM public.power_group AS pg ORDER BY pg.ident;

\echo "Power group membership counts after Phase 2:"
SELECT pgm.power_group_ident, COUNT(*) AS member_count
FROM public.power_group_membership AS pgm
GROUP BY pgm.power_group_ident
ORDER BY pgm.power_group_ident;

-- ============================================================================
-- ROLLBACK Phase 2 for clean import tests
-- ============================================================================
ROLLBACK TO SAVEPOINT phase2_start;

-- Note: power_group_ident_seq is NOT reset here because nextval() is
-- non-transactional (survives rollback). Phase 3 idents will be higher.

-- ============================================================================
-- PHASE 3: Import Round 1
-- ============================================================================
\echo "=== Phase 3: Import Round 1 ==="

-- Create 8 enterprises for import test LUs
INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT 'IP' || n, (SELECT id FROM auth.user LIMIT 1), 'Import test enterprise ' || n
FROM generate_series(1, 8) AS n;

-- Create 8 legal units via temp table helper
CREATE TEMP TABLE _import_lu_data (tax_ident text, lu_name text, ent_short text);
INSERT INTO _import_lu_data VALUES
    ('300000001', 'Import Alpha Corp',    'IP1'),
    ('300000002', 'Import Alpha Sub 1',   'IP2'),
    ('300000003', 'Import Alpha Sub 2',   'IP3'),
    ('300000004', 'Import Beta Corp',     'IP4'),
    ('300000005', 'Import Beta Sub 1',    'IP5'),
    ('300000006', 'Import Beta Sub 2',    'IP6'),
    ('300000007', 'Import Gamma Corp',    'IP7'),
    ('300000008', 'Import Gamma Sub 1',   'IP8');

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, d.lu_name, e.id, true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Import test LU'
FROM _import_lu_data AS d
JOIN public.enterprise AS e ON e.short_name = d.ent_short
ORDER BY d.tax_ident;

-- Create external_idents (tax_ident) for each LU — required for import resolution
INSERT INTO public.external_ident (type_id, shape, ident, legal_unit_id, edit_by_user_id, edit_comment)
SELECT
    (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident'),
    'regular'::external_ident_shape,
    d.tax_ident,
    lu.id,
    (SELECT id FROM auth.user LIMIT 1),
    'Import test tax_ident'
FROM _import_lu_data AS d
JOIN public.legal_unit AS lu ON lu.name = d.lu_name
ORDER BY d.tax_ident;

\echo "Phase 3 legal units with tax_idents:"
SELECT ei.ident AS tax_ident, lu.name
FROM public.legal_unit AS lu
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident LIKE '30000000%'
ORDER BY ei.ident;

-- Create import job for Round 1 relationships
DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_relationship_source_dates';
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition "legal_relationship_source_dates" not found.';
    END IF;
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'import_120_round1', 'Test 120: Relationships Round 1', 'Round 1 parent_company relationships', 'Test 120 Round 1');
END $$;

-- Upload Round 1 relationship data (4 relationships, 2 clusters)
INSERT INTO public.import_120_round1_upload(valid_from, valid_to, influencing_tax_ident, influenced_tax_ident, rel_type_code, percentage) VALUES
    ('2023-01-01', 'infinity', '300000001', '300000002', 'parent_company', '80'),
    ('2023-01-01', 'infinity', '300000001', '300000003', 'parent_company', '60'),
    ('2023-01-01', 'infinity', '300000004', '300000005', 'parent_company', '55'),
    ('2023-01-01', 'infinity', '300000004', '300000006', 'parent_company', '70');

-- Process the import
CALL worker.process_tasks(p_queue => 'import');

\echo "3: Import Round 1 job status:"
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug = 'import_120_round1';

\echo "3: Import Round 1 data rows:"
SELECT row_id, state, action, operation
FROM public.import_120_round1_data
ORDER BY row_id;

\echo "3: Power groups created after Round 1:"
SELECT pg.ident, pg.name FROM public.power_group AS pg ORDER BY pg.ident;

\echo "3: Power group count after Round 1:"
SELECT COUNT(*) AS power_group_count FROM public.power_group;

\echo "3: Power group membership after Round 1:"
SELECT pgm.power_group_ident, ei.ident AS tax_ident, lu.name
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident LIKE '30000000%'
ORDER BY pgm.power_group_ident, ei.ident;

\echo "3: Membership counts per group after Round 1:"
SELECT pgm.power_group_ident, COUNT(*) AS member_count
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident LIKE '30000000%'
GROUP BY pgm.power_group_ident
ORDER BY pgm.power_group_ident;

\echo "3: Relationships with power_group_id after Round 1:"
SELECT
    ei_ing.ident AS influencing,
    ei_ed.ident AS influenced,
    lr.percentage,
    pg.ident AS power_group_ident
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS lu_ing ON lu_ing.id = lr.influencing_id
JOIN public.external_ident AS ei_ing ON ei_ing.legal_unit_id = lu_ing.id
JOIN public.external_ident_type AS eit_ing ON eit_ing.id = ei_ing.type_id AND eit_ing.code = 'tax_ident'
JOIN public.legal_unit AS lu_ed ON lu_ed.id = lr.influenced_id
JOIN public.external_ident AS ei_ed ON ei_ed.legal_unit_id = lu_ed.id
JOIN public.external_ident_type AS eit_ed ON eit_ed.id = ei_ed.type_id AND eit_ed.code = 'tax_ident'
LEFT JOIN public.power_group AS pg ON pg.id = lr.power_group_id
WHERE ei_ing.ident LIKE '30000000%'
ORDER BY ei_ing.ident, ei_ed.ident, lr.percentage;

-- Save Round 1 PG idents for reuse verification in Phase 4
CREATE TEMP TABLE _round1_pgs AS
SELECT id, ident FROM public.power_group ORDER BY ident;

-- ============================================================================
-- PHASE 4: Import Round 2 (update existing PGs)
-- ============================================================================
\echo "=== Phase 4: Import Round 2 ==="

-- Need to clean up import temp tables before next import
CALL test.remove_pg_temp_for_tx_user_switch(p_keep_tables => ARRAY['_import_lu_data', '_round1_pgs']);

-- Create import job for Round 2 relationships
DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_relationship_source_dates';
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition "legal_relationship_source_dates" not found.';
    END IF;
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'import_120_round2', 'Test 120: Relationships Round 2', 'Round 2 with changes', 'Test 120 Round 2');
END $$;

-- Upload Round 2 relationship data:
--   300000001→300000002: unchanged (80%, parent_company)
--   300000001→300000003: changed to co_ownership type (not primary_influencer_only)
--   300000004→300000005: unchanged (55%, parent_company)
--   300000004→300000006: unchanged (70%, parent_company)
--   300000007→300000008: NEW group (51%, parent_company)
-- Note: same valid_from as Round 1 so import matches existing rows for update
INSERT INTO public.import_120_round2_upload(valid_from, valid_to, influencing_tax_ident, influenced_tax_ident, rel_type_code, percentage) VALUES
    ('2023-01-01', 'infinity', '300000001', '300000002', 'parent_company', '80'),
    ('2023-01-01', 'infinity', '300000001', '300000003', 'co_ownership', '30'),
    ('2023-01-01', 'infinity', '300000004', '300000005', 'parent_company', '55'),
    ('2023-01-01', 'infinity', '300000004', '300000006', 'parent_company', '70'),
    ('2023-01-01', 'infinity', '300000007', '300000008', 'parent_company', '51');

-- Process the import
CALL worker.process_tasks(p_queue => 'import');

\echo "4: Import Round 2 job status:"
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug = 'import_120_round2';

\echo "4: Import Round 2 data rows:"
SELECT row_id, state, action, operation
FROM public.import_120_round2_data
ORDER BY row_id;

\echo "4: Power group count after Round 2 (expect 3):"
SELECT COUNT(*) AS power_group_count FROM public.power_group;

\echo "4: PG reuse — Round 1 idents still exist:"
SELECT r1.ident AS round1_ident,
       (SELECT pg.ident FROM public.power_group AS pg WHERE pg.id = r1.id) AS still_exists
FROM _round1_pgs AS r1
ORDER BY r1.ident;

\echo "4: All power groups after Round 2:"
SELECT pg.ident FROM public.power_group AS pg ORDER BY pg.ident;

\echo "4: Power group membership after Round 2:"
SELECT pgm.power_group_ident, ei.ident AS tax_ident, lu.name
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident LIKE '30000000%'
ORDER BY pgm.power_group_ident, ei.ident;

\echo "4: Membership counts per group after Round 2:"
SELECT pgm.power_group_ident, COUNT(*) AS member_count
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident LIKE '30000000%'
GROUP BY pgm.power_group_ident
ORDER BY pgm.power_group_ident;

\echo "4: Current relationships (valid now) with power_group_id:"
SELECT
    ei_ing.ident AS influencing,
    ei_ed.ident AS influenced,
    lr.percentage,
    pg.ident AS power_group_ident,
    lr.valid_from
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS lu_ing ON lu_ing.id = lr.influencing_id
JOIN public.external_ident AS ei_ing ON ei_ing.legal_unit_id = lu_ing.id
JOIN public.external_ident_type AS eit_ing ON eit_ing.id = ei_ing.type_id AND eit_ing.code = 'tax_ident'
JOIN public.legal_unit AS lu_ed ON lu_ed.id = lr.influenced_id
JOIN public.external_ident AS ei_ed ON ei_ed.legal_unit_id = lu_ed.id
JOIN public.external_ident_type AS eit_ed ON eit_ed.id = ei_ed.type_id AND eit_ed.code = 'tax_ident'
LEFT JOIN public.power_group AS pg ON pg.id = lr.power_group_id
WHERE ei_ing.ident LIKE '30000000%'
  AND lr.valid_range @> CURRENT_DATE
ORDER BY ei_ing.ident, ei_ed.ident, lr.percentage;

-- ============================================================================
-- PHASE 5: Pipeline Integration
-- ============================================================================
\echo "=== Phase 5: Pipeline Integration ==="

-- Process analytics tasks (triggered by import changes)
CALL worker.process_tasks(p_queue => 'analytics');

\echo "5: Power group entries in statistical_unit:"
SELECT su.unit_type, COUNT(*) AS count
FROM public.statistical_unit AS su
WHERE su.unit_type = 'power_group'
GROUP BY su.unit_type;

\echo "5: Statistical unit power group details:"
SELECT su.name, su.unit_type, su.valid_from, su.valid_to
FROM public.statistical_unit AS su
WHERE su.unit_type = 'power_group'
ORDER BY su.name;

\echo "=== Test 120: Power Group Lifecycle Complete ==="

\i test/rollback_unless_persist_is_specified.sql

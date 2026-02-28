BEGIN;

\i test/setup.sql

\echo "=== Power Group Fundamentals Test ==="
\echo "Testing the core power group schema and relationships"

-- Reset the power_group sequence to ensure consistent test results
ALTER SEQUENCE public.power_group_ident_seq RESTART WITH 1;

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

-- Load base configuration (regions, activity categories, status codes, etc.)
\i samples/norway/getting-started.sql

-- Seed test relationship types that clearly demonstrate primary_influencer_only semantics
-- parent_company: structurally 1:1 (a subsidiary has at most one parent) → TRUE
-- co_ownership: structurally 1:N (multiple co-owners per entity) → FALSE
INSERT INTO public.legal_rel_type (code, name, description, primary_influencer_only, enabled, custom)
SELECT 'parent_company', 'Parent Company', 'Parent-subsidiary relationship (structurally 1:1 per subsidiary)', TRUE, true, false
WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type WHERE code = 'parent_company');

INSERT INTO public.legal_rel_type (code, name, description, primary_influencer_only, enabled, custom)
SELECT 'co_ownership', 'Co-ownership', 'Shared ownership (multiple co-owners per entity)', FALSE, true, false
WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type WHERE code = 'co_ownership');

-- ============================================================================
\echo "=== Section 1: Verify Schema Structure ==="
-- ============================================================================

\echo "Check legal_rel_type table exists with seed data"
SELECT code, name, description, primary_influencer_only FROM public.legal_rel_type ORDER BY code;

\echo "Check power_group_type table exists (renamed from enterprise_group_type)"
SELECT code, name FROM public.power_group_type ORDER BY code;

\echo "Check legal_reorg_type table exists (renamed from reorg_type)"
SELECT code, name FROM public.legal_reorg_type ORDER BY code LIMIT 5;

\echo "Check legal_relationship table structure"
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'legal_relationship'
ORDER BY ordinal_position;

\echo "Check power_group table structure (TIMELESS - no valid_range, no active)"
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'power_group'
ORDER BY ordinal_position;

\echo "Verify power_group does NOT have temporal or obsolete columns"
SELECT column_name 
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'power_group' 
  AND column_name IN ('valid_range', 'valid_from', 'valid_to', 'active', 'role_id', 'root_legal_unit_id')
ORDER BY column_name;

\echo "Verify legal_relationship HAS power_group_id"
SELECT column_name 
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'legal_relationship' 
  AND column_name = 'power_group_id'
ORDER BY column_name;

\echo "Verify legal_unit does NOT have power_group_id (moved to legal_relationship)"
SELECT column_name 
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'legal_unit' 
  AND column_name = 'power_group_id'
ORDER BY column_name;

-- ============================================================================
\echo "=== Section 2: Create Test Legal Units ==="
-- ============================================================================

\echo "Create enterprises for our test legal units"
INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT 'E' || n, (SELECT id FROM auth.user LIMIT 1), 'Test enterprise ' || n
FROM generate_series(1, 5) AS n;

\echo "Create legal units with hierarchical ownership structure"
-- Parent company (will be root of power group)
INSERT INTO public.legal_unit (
    valid_from, name, enterprise_id, primary_for_enterprise, 
    status_id, edit_by_user_id, edit_comment
)
SELECT 
    '2020-01-01'::date,
    'Alpha Holdings Corp',
    (SELECT id FROM public.enterprise WHERE short_name = 'E1'),
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Parent holding company';

-- Subsidiary 1 (directly owned by Alpha Holdings)
INSERT INTO public.legal_unit (
    valid_from, name, enterprise_id, primary_for_enterprise, 
    status_id, edit_by_user_id, edit_comment
)
SELECT 
    '2020-01-01'::date,
    'Beta Manufacturing Ltd',
    (SELECT id FROM public.enterprise WHERE short_name = 'E2'),
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Manufacturing subsidiary';

-- Subsidiary 2 (directly owned by Alpha Holdings)
INSERT INTO public.legal_unit (
    valid_from, name, enterprise_id, primary_for_enterprise, 
    status_id, edit_by_user_id, edit_comment
)
SELECT 
    '2020-01-01'::date,
    'Gamma Services Inc',
    (SELECT id FROM public.enterprise WHERE short_name = 'E3'),
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Services subsidiary';

-- Sub-subsidiary (owned by Beta Manufacturing - creating depth)
INSERT INTO public.legal_unit (
    valid_from, name, enterprise_id, primary_for_enterprise, 
    status_id, edit_by_user_id, edit_comment
)
SELECT 
    '2020-01-01'::date,
    'Delta Components GmbH',
    (SELECT id FROM public.enterprise WHERE short_name = 'E4'),
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Components sub-subsidiary';

-- Independent company (not in any power group)
INSERT INTO public.legal_unit (
    valid_from, name, enterprise_id, primary_for_enterprise, 
    status_id, edit_by_user_id, edit_comment
)
SELECT 
    '2020-01-01'::date,
    'Epsilon Independent LLC',
    (SELECT id FROM public.enterprise WHERE short_name = 'E5'),
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Independent company - no power group';

\echo "Verify legal units created"
SELECT name, valid_from 
FROM public.legal_unit 
WHERE name LIKE '%Holdings%' OR name LIKE '%Manufacturing%' 
   OR name LIKE '%Services%' OR name LIKE '%Components%' OR name LIKE '%Independent%'
ORDER BY name;

-- ============================================================================
\echo "=== Section 3: Create Parent-Company Relationships ==="
-- ============================================================================

\echo "Get relationship type codes"
SELECT code, name FROM public.legal_rel_type ORDER BY code;

\echo "Create parent_company: Alpha Holdings is parent of Beta Manufacturing (60%)"
INSERT INTO public.legal_relationship (
    valid_from, 
    influencing_id, 
    influenced_id, 
    type_id,
    percentage,
    edit_by_user_id,
    edit_comment
)
SELECT 
    '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Alpha Holdings Corp' LIMIT 1),
    (SELECT id FROM public.legal_unit WHERE name = 'Beta Manufacturing Ltd' LIMIT 1),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    60.00,
    (SELECT id FROM auth.user LIMIT 1),
    'Alpha is parent company of Beta';

\echo "Create parent_company: Alpha Holdings is parent of Gamma Services (51%)"
INSERT INTO public.legal_relationship (
    valid_from, 
    influencing_id, 
    influenced_id, 
    type_id,
    percentage,
    edit_by_user_id,
    edit_comment
)
SELECT 
    '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Alpha Holdings Corp' LIMIT 1),
    (SELECT id FROM public.legal_unit WHERE name = 'Gamma Services Inc' LIMIT 1),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    51.00,
    (SELECT id FROM auth.user LIMIT 1),
    'Alpha is parent company of Gamma';

\echo "Create parent_company: Beta Manufacturing is parent of Delta Components (75%)"
INSERT INTO public.legal_relationship (
    valid_from, 
    influencing_id, 
    influenced_id, 
    type_id,
    percentage,
    edit_by_user_id,
    edit_comment
)
SELECT 
    '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Beta Manufacturing Ltd' LIMIT 1),
    (SELECT id FROM public.legal_unit WHERE name = 'Delta Components GmbH' LIMIT 1),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    75.00,
    (SELECT id FROM auth.user LIMIT 1),
    'Beta is parent company of Delta';

\echo "Verify parent-company relationships created"
SELECT 
    influencer.name AS influencing_name,
    influenced.name AS influenced_name,
    rt.code AS relationship,
    lr.percentage,
    lr.valid_from
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influencer ON lr.influencing_id = influencer.id
JOIN public.legal_unit AS influenced ON lr.influenced_id = influenced.id
JOIN public.legal_rel_type AS rt ON lr.type_id = rt.id
ORDER BY influencer.name, influenced.name;

-- ============================================================================
\echo "=== Section 4: Test Cycle Prevention ==="
-- ============================================================================

\echo "Attempt to create circular parent_company (should fail)"
\echo "Trying: Delta is parent of Alpha (which would create Alpha -> Beta -> Delta -> Alpha cycle)"

DO $$
BEGIN
    INSERT INTO public.legal_relationship (
        valid_from, 
        influencing_id, 
        influenced_id, 
        type_id,
        percentage,
        edit_by_user_id,
        edit_comment
    )
    SELECT 
        '2020-01-01'::date,
        (SELECT id FROM public.legal_unit WHERE name = 'Delta Components GmbH' LIMIT 1),
        (SELECT id FROM public.legal_unit WHERE name = 'Alpha Holdings Corp' LIMIT 1),
        (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
        30.00,
        (SELECT id FROM auth.user LIMIT 1),
        'Delta is parent of Alpha - SHOULD FAIL';
    
    RAISE EXCEPTION 'TEST FAILURE: Circular ownership was allowed - cycle prevention did not work!';
EXCEPTION
    WHEN raise_exception THEN
        IF SQLERRM LIKE 'Circular ownership detected%' THEN
            RAISE NOTICE 'SUCCESS: Circular ownership correctly prevented';
        ELSE
            RAISE;
        END IF;
    WHEN OTHERS THEN
        RAISE NOTICE 'SUCCESS: Circular ownership prevented with error: %', SQLERRM;
END;
$$;

\echo "Verify no circular relationship was created"
SELECT COUNT(*) AS circular_relationships 
FROM public.legal_relationship 
WHERE edit_comment LIKE '%SHOULD FAIL%';

-- ============================================================================
\echo "=== Section 5: Test Self-Reference Prevention ==="
-- ============================================================================

\echo "Attempt self-reference (should fail due to CHECK constraint)"
DO $$
DECLARE
    _alpha_id integer;
BEGIN
    SELECT id INTO _alpha_id FROM public.legal_unit WHERE name = 'Alpha Holdings Corp' LIMIT 1;
    
    INSERT INTO public.legal_relationship (
        valid_from, 
        influencing_id, 
        influenced_id, 
        type_id,
        percentage,
        edit_by_user_id,
        edit_comment
    )
    VALUES (
        '2020-01-01'::date,
        _alpha_id,
        _alpha_id,  -- Same as influencing - should fail
        (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
        100.00,
        (SELECT id FROM auth.user LIMIT 1),
        'Self-reference - SHOULD FAIL'
    );
    
    RAISE EXCEPTION 'ERROR: Self-reference was allowed - this should have failed!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'SUCCESS: Self-reference correctly prevented with CHECK constraint';
    WHEN OTHERS THEN
        IF SQLERRM LIKE 'Circular ownership detected%' THEN
            RAISE NOTICE 'SUCCESS: Self-reference prevented - cycle detection caught it';
        ELSE
            RAISE NOTICE 'SUCCESS: Self-reference prevented with other error';
        END IF;
END;
$$;

-- ============================================================================
\echo "=== Section 6: Test Hierarchy View ==="
-- ============================================================================

\echo "Check hierarchy view shows correct power levels"
SELECT 
    lu.name,
    h.power_level,
    root_lu.name AS root_legal_unit
FROM public.legal_unit_power_hierarchy AS h
JOIN public.legal_unit AS lu ON lu.id = h.legal_unit_id AND lu.valid_range && h.valid_range
JOIN public.legal_unit AS root_lu ON root_lu.id = h.root_legal_unit_id
WHERE lu.name LIKE '%Holdings%' OR lu.name LIKE '%Manufacturing%' 
   OR lu.name LIKE '%Services%' OR lu.name LIKE '%Components%'
ORDER BY h.power_level, lu.name;

\echo "Check power_group_def view shows correct metrics"
SELECT 
    lu.name AS root_legal_unit,
    pgd.depth,
    pgd.width,
    pgd.reach
FROM public.power_group_def AS pgd
JOIN public.legal_unit AS lu ON lu.id = pgd.root_legal_unit_id
ORDER BY lu.name;

-- ============================================================================
\echo "=== Section 7: Test Power Group Creation (TIMELESS) ==="
-- ============================================================================

\echo "Create a power group manually (normally done by worker)"
INSERT INTO public.power_group (
    name,
    type_id,
    edit_by_user_id,
    edit_comment
)
SELECT 
    'Alpha Holdings Group',
    (SELECT id FROM public.power_group_type WHERE code = 'dcn' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Alpha Holdings power group';

\echo "Verify power group created with auto-generated ident"
SELECT 
    ident,
    ident ~ '^PG[0-9A-Z]+$' AS valid_ident_format,
    name
FROM public.power_group;

\echo "Assign power_group_id to relationships in this cluster"
UPDATE public.legal_relationship AS lr
SET power_group_id = (SELECT id FROM public.power_group WHERE name = 'Alpha Holdings Group')
WHERE lr.influencing_id IN (
    SELECT id FROM public.legal_unit 
    WHERE name IN ('Alpha Holdings Corp', 'Beta Manufacturing Ltd')
);

\echo "Verify relationships have power_group_id assigned"
SELECT 
    influencer.name AS influencing_name,
    influenced.name AS influenced_name,
    pg.ident AS power_group_ident,
    lr.percentage
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influencer ON lr.influencing_id = influencer.id
JOIN public.legal_unit AS influenced ON lr.influenced_id = influenced.id
LEFT JOIN public.power_group AS pg ON lr.power_group_id = pg.id
ORDER BY influencer.name, influenced.name;

-- ============================================================================
\echo "=== Section 8: Test Temporal Aspects ==="
-- ============================================================================

\echo "Add a new parent_company relationship starting later (2023)"
INSERT INTO public.legal_relationship (
    valid_from, 
    influencing_id, 
    influenced_id, 
    type_id,
    percentage,
    reorg_type_id,
    edit_by_user_id,
    edit_comment
)
SELECT 
    '2023-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Alpha Holdings Corp' LIMIT 1),
    (SELECT id FROM public.legal_unit WHERE name = 'Epsilon Independent LLC' LIMIT 1),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    55.00,
    (SELECT id FROM public.legal_reorg_type WHERE code = 'acq' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Alpha becomes parent company of Epsilon in 2023';

\echo "Verify temporal relationships - before acquisition (2022)"
SELECT 
    influencer.name AS influencing_name,
    influenced.name AS influenced_name,
    lr.percentage,
    lr.valid_from,
    lr.valid_to
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influencer ON lr.influencing_id = influencer.id
JOIN public.legal_unit AS influenced ON lr.influenced_id = influenced.id
WHERE lr.valid_range @> '2022-06-01'::date
ORDER BY influencer.name, influenced.name;

\echo "Verify temporal relationships - after acquisition (2024)"
SELECT 
    influencer.name AS influencing_name,
    influenced.name AS influenced_name,
    lr.percentage,
    lr.valid_from,
    lr.valid_to
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influencer ON lr.influencing_id = influencer.id
JOIN public.legal_unit AS influenced ON lr.influenced_id = influenced.id
WHERE lr.valid_range @> '2024-06-01'::date
ORDER BY influencer.name, influenced.name;

-- ============================================================================
\echo "=== Section 9: Summary Statistics ==="
-- ============================================================================

\echo "Count of relationships by type"
SELECT 
    rt.code AS relationship_type,
    COUNT(*) AS count
FROM public.legal_relationship AS lr
JOIN public.legal_rel_type AS rt ON lr.type_id = rt.id
GROUP BY rt.code
ORDER BY rt.code;

\echo "Relationships with power_group assignment"
SELECT 
    pg.ident AS power_group,
    COUNT(*) AS relationship_count
FROM public.legal_relationship AS lr
LEFT JOIN public.power_group AS pg ON lr.power_group_id = pg.id
GROUP BY pg.ident
ORDER BY pg.ident NULLS LAST;

\echo "Legal units by power level (from hierarchy view)"
SELECT 
    h.power_level,
    COUNT(*) AS count,
    string_agg(lu.name, ', ' ORDER BY lu.name) AS names
FROM public.legal_unit_power_hierarchy AS h
JOIN public.legal_unit AS lu ON lu.id = h.legal_unit_id
GROUP BY h.power_level
ORDER BY h.power_level;

\echo "=== Power Group Fundamentals Test Complete ==="

ROLLBACK;

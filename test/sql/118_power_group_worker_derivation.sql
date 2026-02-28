BEGIN;

\i test/setup.sql

\echo "=== Power Group Worker Derivation Test ==="
\echo "Testing automated derivation of power groups from parent_company relationships"

-- Reset the power_group sequence to ensure consistent test results
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
\echo "=== Section 1: Verify Worker Infrastructure ==="
-- ============================================================================

\echo "Check derive_power_groups command is registered"
SELECT command, queue, description 
FROM worker.command_registry 
WHERE command = 'derive_power_groups';

\echo "Check views exist"
SELECT table_schema, table_name, table_type
FROM information_schema.tables
WHERE table_name IN ('legal_unit_power_hierarchy', 'power_group_def', 'legal_relationship_cluster', 'power_group_active', 'power_group_membership')
ORDER BY table_name;

\echo "Check enqueue function exists"
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'worker' AND routine_name = 'enqueue_derive_power_groups';

-- ============================================================================
\echo "=== Section 2: Create Test Legal Units ==="
-- ============================================================================

\echo "Create enterprises for our test legal units"
INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT 'PW' || n, (SELECT id FROM auth.user LIMIT 1), 'Power test enterprise ' || n
FROM generate_series(1, 6) AS n;

\echo "Create legal units with hierarchical parent-subsidiary structure"
-- Parent company (will be root of power group)
INSERT INTO public.legal_unit (
    valid_from, name, enterprise_id, primary_for_enterprise, 
    status_id, edit_by_user_id, edit_comment
)
SELECT 
    '2020-01-01'::date,
    'PowerTest Holdings Corp',
    (SELECT id FROM public.enterprise WHERE short_name = 'PW1'),
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Parent holding company';

-- Subsidiary 1 (directly owned by Holdings)
INSERT INTO public.legal_unit (
    valid_from, name, enterprise_id, primary_for_enterprise, 
    status_id, edit_by_user_id, edit_comment
)
SELECT 
    '2020-01-01'::date,
    'PowerTest Manufacturing Ltd',
    (SELECT id FROM public.enterprise WHERE short_name = 'PW2'),
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Manufacturing subsidiary';

-- Subsidiary 2 (directly owned by Holdings)
INSERT INTO public.legal_unit (
    valid_from, name, enterprise_id, primary_for_enterprise, 
    status_id, edit_by_user_id, edit_comment
)
SELECT 
    '2020-01-01'::date,
    'PowerTest Services Inc',
    (SELECT id FROM public.enterprise WHERE short_name = 'PW3'),
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Services subsidiary';

-- Sub-subsidiary (owned by Manufacturing - creating depth)
INSERT INTO public.legal_unit (
    valid_from, name, enterprise_id, primary_for_enterprise, 
    status_id, edit_by_user_id, edit_comment
)
SELECT 
    '2020-01-01'::date,
    'PowerTest Components GmbH',
    (SELECT id FROM public.enterprise WHERE short_name = 'PW4'),
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
    'PowerTest Independent LLC',
    (SELECT id FROM public.enterprise WHERE short_name = 'PW5'),
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Independent company - no power group';

\echo "Verify legal units created"
SELECT name 
FROM public.legal_unit 
WHERE name LIKE 'PowerTest%'
ORDER BY name;

-- ============================================================================
\echo "=== Section 3: Create Ownership Relationships (triggers worker task) ==="
-- ============================================================================

\echo "Check pending tasks before creating relationships"
SELECT command, state, COUNT(*) 
FROM worker.tasks 
WHERE command = 'derive_power_groups'
GROUP BY command, state;

\echo "Create parent_company: Holdings is parent of Manufacturing (60%)"
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
    (SELECT id FROM public.legal_unit WHERE name = 'PowerTest Holdings Corp' LIMIT 1),
    (SELECT id FROM public.legal_unit WHERE name = 'PowerTest Manufacturing Ltd' LIMIT 1),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    60.00,
    (SELECT id FROM auth.user LIMIT 1),
    'Holdings owns 60% of Manufacturing';

\echo "Create parent_company: Holdings is parent of Services (51%)"
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
    (SELECT id FROM public.legal_unit WHERE name = 'PowerTest Holdings Corp' LIMIT 1),
    (SELECT id FROM public.legal_unit WHERE name = 'PowerTest Services Inc' LIMIT 1),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    51.00,
    (SELECT id FROM auth.user LIMIT 1),
    'Holdings owns 51% of Services';

\echo "Create parent_company: Manufacturing is parent of Components (75%)"
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
    (SELECT id FROM public.legal_unit WHERE name = 'PowerTest Manufacturing Ltd' LIMIT 1),
    (SELECT id FROM public.legal_unit WHERE name = 'PowerTest Components GmbH' LIMIT 1),
    (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
    75.00,
    (SELECT id FROM auth.user LIMIT 1),
    'Manufacturing owns 75% of Components';

\echo "Check pending tasks after creating relationships (should have 1 pending)"
SELECT command, state, COUNT(*) 
FROM worker.tasks 
WHERE command = 'derive_power_groups'
GROUP BY command, state;

-- ============================================================================
\echo "=== Section 4: Test Hierarchy View ==="
-- ============================================================================

\echo "Check legal_unit_power_hierarchy view (before worker runs)"
SELECT 
    lu.name,
    h.power_level,
    root_lu.name AS root_legal_unit,
    array_length(h.path, 1) AS path_length
FROM public.legal_unit_power_hierarchy AS h
JOIN public.legal_unit AS lu ON lu.id = h.legal_unit_id AND lu.valid_range && h.valid_range
JOIN public.legal_unit AS root_lu ON root_lu.id = h.root_legal_unit_id AND root_lu.valid_range && h.valid_range
WHERE lu.name LIKE 'PowerTest%'
ORDER BY h.power_level, lu.name;

\echo "Check power_group_def view (computes what power groups should exist)"
SELECT 
    lu.name AS root_legal_unit,
    pgd.depth,
    pgd.width,
    pgd.reach
FROM public.power_group_def AS pgd
JOIN public.legal_unit AS lu ON lu.id = pgd.root_legal_unit_id
WHERE lu.name LIKE 'PowerTest%';

-- ============================================================================
\echo "=== Section 5: Run Worker Derivation ==="
-- ============================================================================

\echo "Relationships BEFORE worker derivation (power_group_id should be NULL)"
SELECT 
    influencer.name AS influencing_name,
    influenced.name AS influenced_name,
    lr.power_group_id IS NOT NULL AS has_power_group,
    lr.percentage
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influencer ON lr.influencing_id = influencer.id
JOIN public.legal_unit AS influenced ON lr.influenced_id = influenced.id
WHERE influencer.name LIKE 'PowerTest%' OR influenced.name LIKE 'PowerTest%'
ORDER BY influencer.name, influenced.name;

\echo "Power groups BEFORE worker derivation (should be empty)"
SELECT pg.ident, pg.name
FROM public.power_group AS pg
WHERE pg.name LIKE 'PowerTest%' OR pg.ident IS NOT NULL;

\echo "Run derive_power_groups function"
SELECT worker.derive_power_groups();

\echo "Power groups AFTER worker derivation"
SELECT pg.ident, pg.ident ~ '^PG[0-9A-Z]+$' AS valid_ident_format, pg.name
FROM public.power_group AS pg;

\echo "Relationships AFTER worker derivation (should have power_group_id)"
SELECT 
    influencer.name AS influencing_name,
    influenced.name AS influenced_name,
    pg.ident AS power_group_ident,
    lr.percentage
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influencer ON lr.influencing_id = influencer.id
JOIN public.legal_unit AS influenced ON lr.influenced_id = influenced.id
LEFT JOIN public.power_group AS pg ON lr.power_group_id = pg.id
WHERE influencer.name LIKE 'PowerTest%' OR influenced.name LIKE 'PowerTest%'
ORDER BY influencer.name, influenced.name;

-- ============================================================================
\echo "=== Section 6: Verify Hierarchy via Views ==="
-- ============================================================================

\echo "Check legal_unit_power_hierarchy after derivation"
SELECT 
    lu.name,
    h.power_level,
    root_lu.name AS root_legal_unit
FROM public.legal_unit_power_hierarchy AS h
JOIN public.legal_unit AS lu ON lu.id = h.legal_unit_id
JOIN public.legal_unit AS root_lu ON root_lu.id = h.root_legal_unit_id
WHERE lu.name LIKE 'PowerTest%'
ORDER BY h.power_level, lu.name;

\echo "Holdings should be level 1 (root)"
SELECT lu.name, h.power_level 
FROM public.legal_unit_power_hierarchy AS h
JOIN public.legal_unit AS lu ON lu.id = h.legal_unit_id
WHERE lu.name = 'PowerTest Holdings Corp';

\echo "Manufacturing and Services should be level 2 (direct subsidiaries)"
SELECT lu.name, h.power_level 
FROM public.legal_unit_power_hierarchy AS h
JOIN public.legal_unit AS lu ON lu.id = h.legal_unit_id
WHERE lu.name IN ('PowerTest Manufacturing Ltd', 'PowerTest Services Inc')
ORDER BY lu.name;

\echo "Components should be level 3 (sub-subsidiary)"
SELECT lu.name, h.power_level 
FROM public.legal_unit_power_hierarchy AS h
JOIN public.legal_unit AS lu ON lu.id = h.legal_unit_id
WHERE lu.name = 'PowerTest Components GmbH';

\echo "Independent should NOT be in hierarchy"
SELECT lu.name, h.power_level 
FROM public.legal_unit AS lu
LEFT JOIN public.legal_unit_power_hierarchy AS h ON lu.id = h.legal_unit_id
WHERE lu.name = 'PowerTest Independent LLC';

-- ============================================================================
\echo "=== Section 7: Verify Power Group Metrics via View ==="
-- ============================================================================

\echo "Verify depth, width, reach from power_group_def view"
SELECT 
    lu.name AS root_legal_unit,
    pgd.depth,
    pgd.depth = 2 AS correct_depth,  -- Holdings -> Manufacturing -> Components = 2 levels
    pgd.width,
    pgd.width = 2 AS correct_width,  -- Holdings has 2 direct children
    pgd.reach,
    pgd.reach = 3 AS correct_reach   -- Manufacturing, Services, Components = 3 total
FROM public.power_group_def AS pgd
JOIN public.legal_unit AS lu ON lu.id = pgd.root_legal_unit_id
WHERE lu.name = 'PowerTest Holdings Corp';

-- ============================================================================
\echo "=== Section 8: Test Non-Controlling Ownership ==="
-- ============================================================================

\echo "Create a second hierarchy root (new company owning Independent with <50%)"
INSERT INTO public.legal_unit (
    valid_from, name, enterprise_id, primary_for_enterprise, 
    status_id, edit_by_user_id, edit_comment
)
SELECT 
    '2020-01-01'::date,
    'PowerTest MinorInvestor Corp',
    (SELECT id FROM public.enterprise WHERE short_name = 'PW6'),
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1),
    'Minor investor company';

\echo "Create non-primary-influencer relationship: MinorInvestor co-owns Independent"
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
    (SELECT id FROM public.legal_unit WHERE name = 'PowerTest MinorInvestor Corp' LIMIT 1),
    (SELECT id FROM public.legal_unit WHERE name = 'PowerTest Independent LLC' LIMIT 1),
    (SELECT id FROM public.legal_rel_type WHERE code = 'co_ownership'),
    30.00,  -- co_ownership type has primary_influencer_only = FALSE, so not in power group
    (SELECT id FROM auth.user LIMIT 1),
    'MinorInvestor co-owns Independent (not primary_influencer_only)';

\echo "Re-run derive_power_groups"
SELECT worker.derive_power_groups();

\echo "Non-primary-influencer relationship should have NULL power_group_id"
SELECT 
    influencer.name AS influencing_name,
    influenced.name AS influenced_name,
    lr.power_group_id IS NULL AS no_power_group,
    lr.percentage
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influencer ON lr.influencing_id = influencer.id
JOIN public.legal_unit AS influenced ON lr.influenced_id = influenced.id
WHERE influencer.name = 'PowerTest MinorInvestor Corp';

\echo "Independent and MinorInvestor should NOT be in power hierarchy"
SELECT lu.name, h.power_level 
FROM public.legal_unit AS lu
LEFT JOIN public.legal_unit_power_hierarchy AS h ON lu.id = h.legal_unit_id
WHERE lu.name IN ('PowerTest Independent LLC', 'PowerTest MinorInvestor Corp')
ORDER BY lu.name;

-- ============================================================================
\echo "=== Section 9: Test Idempotency ==="
-- ============================================================================

\echo "Run derive_power_groups again (should not change anything)"
SELECT worker.derive_power_groups();

\echo "Verify power groups unchanged"
SELECT pg.ident, pg.ident ~ '^PG[0-9A-Z]+$' AS valid_ident_format
FROM public.power_group AS pg;

\echo "Verify relationships unchanged"
SELECT 
    influencer.name AS influencing_name,
    influenced.name AS influenced_name,
    pg.ident AS power_group_ident
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influencer ON lr.influencing_id = influencer.id
JOIN public.legal_unit AS influenced ON lr.influenced_id = influenced.id
LEFT JOIN public.power_group AS pg ON lr.power_group_id = pg.id
WHERE influencer.name LIKE 'PowerTest%'
ORDER BY influencer.name, influenced.name;

-- ============================================================================
\echo "=== Section 10: Test power_group_active View ==="
-- ============================================================================

\echo "Check currently active power groups"
SELECT ident, name
FROM public.power_group_active
ORDER BY ident;

-- ============================================================================
\echo "=== Section 11: Summary ==="
-- ============================================================================

\echo "All power groups (timeless registry)"
SELECT pg.ident, pg.ident ~ '^PG[0-9A-Z]+$' AS valid_ident_format, pg.name
FROM public.power_group AS pg
ORDER BY pg.ident;

\echo "All relationships with power group assignment"
SELECT 
    pg.ident AS power_group,
    COUNT(*) AS relationship_count
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS influencer ON lr.influencing_id = influencer.id
LEFT JOIN public.power_group AS pg ON lr.power_group_id = pg.id
WHERE influencer.name LIKE 'PowerTest%'
GROUP BY pg.ident
ORDER BY pg.ident NULLS LAST;

\echo "Legal units by power level (from hierarchy view)"
SELECT 
    h.power_level,
    COUNT(*) AS count,
    string_agg(lu.name, ', ' ORDER BY lu.name) AS names
FROM public.legal_unit_power_hierarchy AS h
JOIN public.legal_unit AS lu ON lu.id = h.legal_unit_id
WHERE lu.name LIKE 'PowerTest%'
GROUP BY h.power_level
ORDER BY h.power_level;

\echo "=== Power Group Worker Derivation Test Complete ==="

ROLLBACK;

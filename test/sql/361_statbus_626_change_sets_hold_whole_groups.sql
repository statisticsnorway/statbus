BEGIN;

\i test/setup.sql

-- STATBUS-626: a change set holds every unit of the enterprise groups in it.
--
-- public.get_temporally_closed_change_sets splits units into change sets of
-- whole enterprise groups. A group is an enterprise with its legal units, the
-- establishments of those legal units, and the establishments attached to the
-- enterprise directly (informal establishments). A legal unit that belongs to
-- two enterprises at different times bridges them into one group. The function
-- has four paths: full or filtered by unit id ranges, each with and without
-- bridges. Every path must give the same groups.
--
-- The fixture:
--   E1: legal units A and B; B has establishment b1. A moves to E2 in 2023,
--       so A bridges E1 and E2 into one group.
--   E2: legal unit A from 2023, legal unit D with establishment d1.
--   E3: legal unit C with establishments c1 and c2.
--   E4: no legal unit, informal establishment i1.
--   E5: no units at all.

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

SELECT id AS user_id FROM auth.user LIMIT 1 \gset
SELECT id AS active_id FROM public.status WHERE code = 'active' LIMIT 1 \gset

INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT format('E626-%s', n), :user_id, 'STATBUS-626 test enterprise'
FROM generate_series(1, 5) AS n;

CREATE TEMP TABLE unit_name (kind TEXT, name TEXT, id INT) ON COMMIT DROP;
INSERT INTO unit_name (kind, name, id)
SELECT 'enterprise', short_name, id FROM public.enterprise WHERE short_name LIKE 'E626-%';

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, v.lu, en.id, v.is_primary, :active_id, :user_id, 'STATBUS-626 test legal unit'
FROM (VALUES ('LU626-A', 'E626-1', false), ('LU626-B', 'E626-1', true),
             ('LU626-D', 'E626-2', true), ('LU626-C', 'E626-3', true)) AS v(lu, en, is_primary)
JOIN public.enterprise AS en ON en.short_name = v.en;
INSERT INTO unit_name (kind, name, id)
SELECT DISTINCT 'legal_unit', name, id FROM public.legal_unit WHERE name LIKE 'LU626-%';

INSERT INTO public.establishment (valid_from, name, legal_unit_id, primary_for_legal_unit, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, v.es, lu.id, v.is_primary, :active_id, :user_id, 'STATBUS-626 test establishment'
FROM (VALUES ('ES626-b1', 'LU626-B', true), ('ES626-d1', 'LU626-D', true),
             ('ES626-c1', 'LU626-C', true), ('ES626-c2', 'LU626-C', false)) AS v(es, lu, is_primary)
JOIN public.legal_unit AS lu ON lu.name = v.lu;
INSERT INTO public.establishment (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'ES626-i1', en.id, true, :active_id, :user_id, 'STATBUS-626 informal establishment'
FROM public.enterprise AS en WHERE en.short_name = 'E626-4';
INSERT INTO unit_name (kind, name, id)
SELECT DISTINCT 'establishment', name, id FROM public.establishment WHERE name LIKE 'ES626-%';

-- The units of the fixture, so the other demo units stay out of the comparison.
CREATE TEMP TABLE fixture_enterprise ON COMMIT DROP AS
SELECT id FROM unit_name WHERE kind = 'enterprise';

-- Each group of the fixture, the units named, from the change sets the function returns.
CREATE FUNCTION pg_temp.fixture_groups(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL)
RETURNS TABLE (enterprises TEXT, legal_units TEXT, establishments TEXT)
LANGUAGE sql AS $$
    -- Target size 1 puts each group in a change set of its own.
    WITH change_set AS (
        SELECT * FROM public.get_temporally_closed_change_sets(
            p_target_change_set_size => 1,
            p_establishment_id_ranges => p_establishment_id_ranges,
            p_legal_unit_id_ranges => p_legal_unit_id_ranges,
            p_enterprise_id_ranges => p_enterprise_id_ranges)
        WHERE enterprise_ids && (SELECT array_agg(id) FROM fixture_enterprise)
    )
    SELECT
        (SELECT string_agg(n.name, ',' ORDER BY n.name) FROM unit_name AS n WHERE n.kind = 'enterprise' AND n.id = ANY (cs.enterprise_ids)),
        (SELECT string_agg(n.name, ',' ORDER BY n.name) FROM unit_name AS n WHERE n.kind = 'legal_unit' AND n.id = ANY (cs.legal_unit_ids)),
        (SELECT string_agg(n.name, ',' ORDER BY n.name) FROM unit_name AS n WHERE n.kind = 'establishment' AND n.id = ANY (cs.establishment_ids))
    FROM change_set AS cs
    ORDER BY 1;
$$;

SELECT int4multirange(int4range(id, id + 1)) AS e3_range FROM unit_name WHERE name = 'E626-3' \gset
SELECT int4multirange(int4range(id, id + 1)) AS a_range FROM unit_name WHERE name = 'LU626-A' \gset
SELECT int4multirange(int4range(id, id + 1)) AS i1_range FROM unit_name WHERE name = 'ES626-i1' \gset

\echo "626.c1 full, no bridge: one group per enterprise, informal establishment with its enterprise, E5 alone"
SELECT * FROM pg_temp.fixture_groups();

\echo "626.c2 filtered, no bridge: E3 by its id, E4 by its informal establishment"
SELECT * FROM pg_temp.fixture_groups(p_enterprise_id_ranges => :'e3_range');
SELECT * FROM pg_temp.fixture_groups(p_establishment_id_ranges => :'i1_range');

-- Legal unit A moves to E2 from 2023: A now bridges E1 and E2.
UPDATE public.legal_unit__for_portion_of_valid
   SET enterprise_id = (SELECT id FROM unit_name WHERE name = 'E626-2'),
       valid_from = '2023-01-01', valid_to = 'infinity'
 WHERE id = (SELECT id FROM unit_name WHERE name = 'LU626-A');

SELECT lu.name, en.short_name AS enterprise, lu.valid_from, lu.valid_to
FROM public.legal_unit AS lu JOIN public.enterprise AS en ON en.id = lu.enterprise_id
WHERE lu.name = 'LU626-A' ORDER BY lu.valid_from;

\echo "626.c3 full, with the bridge: E1 and E2 one group with all their units"
SELECT * FROM pg_temp.fixture_groups();

\echo "626.c4 filtered, with the bridge: the group of legal unit A, and E3 alone"
SELECT * FROM pg_temp.fixture_groups(p_legal_unit_id_ranges => :'a_range');
SELECT * FROM pg_temp.fixture_groups(p_enterprise_id_ranges => :'e3_range');

ROLLBACK;

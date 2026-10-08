-- STATBUS-476: public.reset reparents activity categories within their own
-- standard.
--
-- reset (scope getting-started/all) deletes the custom activity_category
-- overrides and points their non-custom children at the system row of the
-- same path. Its replacement join matched the path in every standard, and
-- isic_v4 and nace_v2.1 share paths, so a child could be pointed at the other
-- standard's row. public.lookup_parent_and_derive_code (BEFORE UPDATE)
-- re-derives parent_id and overwrote that choice, which MASKED the defect.
-- The test therefore forces the situation: it disables that trigger inside
-- the (rolled back) transaction, so what is asserted is what reset itself
-- writes, not the trigger's correction.
--
-- Invariants checked:
--   1. A manufactured two-standards-same-path case: a nace_v2.1 custom
--      override with a child, where isic_v4 has a system row at the same path
--      and nace_v2.1 has its own system row. After reset the child points at
--      the nace_v2.1 system row.
--   2. The getting-started data set (as test 305 loads it): after reset no
--      parent link crosses standards, and changed_children_count is 726.
BEGIN;

\i test/setup.sql

\echo "Test 139: reset reparents activity categories within their own standard (STATBUS-476)"

CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.settings(activity_category_standard_id, country_id, region_version_id)
SELECT (SELECT id FROM public.activity_category_standard WHERE code = 'nace_v2.1')
     , (SELECT id FROM public.country WHERE iso_2 = 'NO')
     , (SELECT id FROM public.region_version WHERE code = 'initial');
RESET ROLE;

\echo "139.1: the same path in two standards, a nace_v2.1 custom override with a child"
-- A.01.1 exists as a system row in both isic_v4 and nace_v2.1. Override it
-- in nace_v2.1 and give the override a child.
INSERT INTO public.activity_category_enabled_custom(path, name) VALUES ('A.01.1', 'custom A.01.1');
SELECT acs.code AS standard, ac.path, ac.custom, ac.enabled
  FROM public.activity_category AS ac
  JOIN public.activity_category_standard AS acs ON acs.id = ac.standard_id
 WHERE ac.path::text = 'A.01.1'
 ORDER BY 1, 3;

ALTER TABLE public.activity_category DISABLE TRIGGER lookup_parent_and_derive_code_before_insert_update;
UPDATE public.activity_category AS child
   SET parent_id = (SELECT o.id FROM public.activity_category AS o
                      JOIN public.activity_category_standard AS s ON s.id = o.standard_id
                     WHERE s.code = 'nace_v2.1' AND o.path::text = 'A.01.1' AND o.custom)
  FROM public.activity_category_standard AS s
 WHERE s.id = child.standard_id AND s.code = 'nace_v2.1' AND child.path::text = 'A.01.1.1' AND NOT child.custom;

SELECT (public.reset(true, 'getting-started')->'activity_category'->>'deleted_count')::int > 0 AS overrides_deleted;

SELECT cs.code AS child_standard, c.path AS child, ps.code AS parent_standard, p.path AS parent, p.custom AS parent_custom
  FROM public.activity_category AS c
  JOIN public.activity_category_standard AS cs ON cs.id = c.standard_id
  JOIN public.activity_category AS p ON p.id = c.parent_id
  JOIN public.activity_category_standard AS ps ON ps.id = p.standard_id
 WHERE cs.code = 'nace_v2.1' AND c.path::text = 'A.01.1.1';
ALTER TABLE public.activity_category ENABLE TRIGGER lookup_parent_and_derive_code_before_insert_update;

ROLLBACK;

BEGIN;
\o /dev/null
\i test/setup.sql
\o

\echo "139.2: the getting-started data set: reset keeps every parent link within its standard"
CALL test.set_user_from_email('test.admin@statbus.org');
\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\o
\set ECHO all
RESET ROLE;

ALTER TABLE public.activity_category DISABLE TRIGGER lookup_parent_and_derive_code_before_insert_update;
SELECT public.reset(true, 'getting-started')->'activity_category' AS reset_activity_category;
SELECT cs.code AS child_standard, ps.code AS parent_standard, count(*) AS links
  FROM public.activity_category AS c
  JOIN public.activity_category_standard AS cs ON cs.id = c.standard_id
  JOIN public.activity_category AS p ON p.id = c.parent_id
  JOIN public.activity_category_standard AS ps ON ps.id = p.standard_id
 GROUP BY 1, 2
 ORDER BY 1, 2;
ALTER TABLE public.activity_category ENABLE TRIGGER lookup_parent_and_derive_code_before_insert_update;

ROLLBACK;

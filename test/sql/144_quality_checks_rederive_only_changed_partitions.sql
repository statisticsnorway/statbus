BEGIN;

\i test/setup.sql

-- 0pn35h: the quality checks rederive only the changed units. worker.derive_quality spawns one
-- concurrent derive_quality_partition per hash partition: every partition on a full recalculation,
-- only the partitions holding a changed unit (public.statistical_unit_facet_dirty_hash_slots) on an
-- edit. A partial cycle must leave public.quality_finding exactly as a full rederive would.
--
-- Fixture: six legal units with one establishment each, valid from 2020, located in the demo
-- installation's country with a region and with primary activity A. LU-EDIT gets secondary activity A
-- (secondary equals primary) by an edit after the first cycle; LU-FIX loses its region by an edit.

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

SELECT id AS user_id FROM auth.user LIMIT 1 \gset
SELECT id AS active_id FROM public.status WHERE code = 'active' LIMIT 1 \gset
SELECT id AS un_id FROM public.country WHERE iso_2 = 'UN' \gset
SELECT id AS region_id FROM public.region ORDER BY path LIMIT 1 \gset
SELECT id AS activity_a_id FROM public.activity_category WHERE enabled ORDER BY path LIMIT 1 \gset

INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT 'EN-' || n, :user_id, '0pn35h test enterprise'
FROM unnest(ARRAY['LU-EDIT', 'LU-FIX', 'LU-3', 'LU-4', 'LU-5', 'LU-6']) AS n;

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, substr(en.short_name, 4), en.id, true, :active_id, :user_id, '0pn35h test legal unit'
FROM public.enterprise AS en WHERE en.short_name LIKE 'EN-LU-%';

INSERT INTO public.establishment (valid_from, name, legal_unit_id, primary_for_legal_unit, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, lu.name || '-es', lu.id, true, :active_id, :user_id, '0pn35h test establishment'
FROM public.legal_unit AS lu WHERE lu.name LIKE 'LU-%';

INSERT INTO public.location (valid_from, valid_to, type, address_part1, region_id, country_id, legal_unit_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'infinity'::date, 'physical', 'Street 1', :region_id, :un_id, lu.id, :user_id, '0pn35h test location'
FROM public.legal_unit AS lu WHERE lu.name LIKE 'LU-%';
INSERT INTO public.location (valid_from, valid_to, type, address_part1, region_id, country_id, establishment_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'infinity'::date, 'physical', 'Street 2', :region_id, :un_id, es.id, :user_id, '0pn35h test location'
FROM public.establishment AS es WHERE es.name LIKE 'LU-%';

INSERT INTO public.activity (valid_from, valid_to, type, category_id, legal_unit_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'infinity'::date, 'primary', :activity_a_id, lu.id, :user_id, '0pn35h test activity'
FROM public.legal_unit AS lu WHERE lu.name LIKE 'LU-%';
INSERT INTO public.activity (valid_from, valid_to, type, category_id, establishment_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'infinity'::date, 'primary', :activity_a_id, es.id, :user_id, '0pn35h test activity'
FROM public.establishment AS es WHERE es.name LIKE 'LU-%';

CALL worker.process_tasks(p_queue => 'analytics');

CREATE TEMP VIEW fixture_unit AS
SELECT 'legal_unit'::public.statistical_unit_type AS unit_type, lu.id AS unit_id, lu.name
FROM public.legal_unit AS lu WHERE lu.name LIKE 'LU-%'
UNION ALL
SELECT 'establishment', es.id, es.name
FROM public.establishment AS es WHERE es.name LIKE 'LU-%';

\echo
\echo "144.1 the first cycle derives the new units' partitions: the fixture has no finding"
SELECT t.info->>'full' AS full_recalculation, (t.info->>'child_count')::int > 0 AS has_children
FROM worker.tasks AS t WHERE t.command = 'derive_quality' ORDER BY t.id DESC LIMIT 1;
SELECT count(*) AS fixture_findings
FROM public.quality_finding AS f JOIN fixture_unit AS u USING (unit_type, unit_id);

-- The edits: LU-EDIT's secondary activity equals its primary, LU-FIX's location loses its region.
INSERT INTO public.activity (valid_from, valid_to, type, category_id, legal_unit_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, 'infinity'::date, 'secondary', :activity_a_id, lu.id, :user_id, '0pn35h edit'
FROM public.legal_unit AS lu WHERE lu.name = 'LU-EDIT';
UPDATE public.location__for_portion_of_valid SET region_id = NULL, region_version_id = NULL, edit_comment = '0pn35h edit'
WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'LU-FIX') AND type = 'physical';

CREATE TEMP VIEW edited_partition AS
SELECT DISTINCT int4range(p.part * p.size, LEAST(p.part * p.size + p.size, 16384)) AS hash_partition
FROM (SELECT public.hash_slot(u.unit_type, u.unit_id) / (16384 / public.get_partition_count_target()) AS part,
             16384 / public.get_partition_count_target() AS size
      FROM (SELECT 'legal_unit'::public.statistical_unit_type AS unit_type, lu.id AS unit_id FROM public.legal_unit AS lu WHERE lu.name IN ('LU-EDIT', 'LU-FIX')
            UNION ALL SELECT 'establishment', es.id FROM public.establishment AS es WHERE es.name IN ('LU-EDIT-es', 'LU-FIX-es')
            UNION ALL SELECT 'enterprise', en.id FROM public.enterprise AS en WHERE en.short_name IN ('EN-LU-EDIT', 'EN-LU-FIX')) AS u) AS p;

CALL worker.process_tasks(p_queue => 'analytics');

\echo
\echo "144.2 the edit's cycle rederives, concurrently, exactly the partitions of the edited legal units, their establishments and enterprises"
SELECT t.info->>'full' AS full_recalculation,
       t.child_mode,
       (SELECT DISTINCT c.state FROM worker.tasks AS c WHERE c.parent_id = t.id) AS children_state,
       (SELECT array_agg((c.payload->>'hash_partition')::int4range ORDER BY 1) FROM worker.tasks AS c WHERE c.parent_id = t.id)
         = (SELECT array_agg(e.hash_partition ORDER BY 1) FROM edited_partition AS e) AS edited_partitions_only
FROM worker.tasks AS t WHERE t.command = 'derive_quality' ORDER BY t.id DESC LIMIT 1;

\echo
\echo "144.3 the edit's findings: LU-EDIT's secondary equals primary, LU-FIX's missing region"
SELECT f.rule, u.unit_type, u.name
FROM public.quality_finding AS f JOIN fixture_unit AS u USING (unit_type, unit_id)
ORDER BY f.rule, u.unit_type, u.name;

\echo
\echo "144.4 a full rederive leaves every finding as the partial cycle left it"
CREATE TEMP TABLE after_partial AS
SELECT rule, stat_definition_id, unit_type, unit_id, valid_range, existence_from, existence_until, detail
FROM public.quality_finding;
SELECT public.quality_finding_derive() IS NOT NULL AS rederived;
SELECT (SELECT count(*) FROM (
          SELECT rule, stat_definition_id, unit_type, unit_id, valid_range, existence_from, existence_until, detail FROM after_partial
          EXCEPT ALL
          SELECT rule, stat_definition_id, unit_type, unit_id, valid_range, existence_from, existence_until, detail FROM public.quality_finding) AS x) AS only_partial,
       (SELECT count(*) FROM (
          SELECT rule, stat_definition_id, unit_type, unit_id, valid_range, existence_from, existence_until, detail FROM public.quality_finding
          EXCEPT ALL
          SELECT rule, stat_definition_id, unit_type, unit_id, valid_range, existence_from, existence_until, detail FROM after_partial) AS x) AS only_full;

\echo
\echo "144.5 the step's info counts the findings per check of the partitions it rederived"
SELECT t.info->'secondary_activity_equals_primary' AS secondary_equals_primary,
       t.info->'missing_region' AS missing_region
FROM worker.tasks AS t WHERE t.command = 'derive_quality' AND NOT (t.info->>'full')::boolean
ORDER BY t.id DESC LIMIT 1;

-- A rule about a legal unit can turn on an edit of its establishment only: establishment activity
-- differs compares the legal unit with its primary establishment.
SELECT id AS activity_b_id FROM public.activity_category WHERE enabled ORDER BY path OFFSET 1 LIMIT 1 \gset
UPDATE public.activity__for_portion_of_valid SET category_id = :activity_b_id, edit_comment = '0pn35h establishment edit'
WHERE establishment_id = (SELECT id FROM public.establishment WHERE name = 'LU-3-es') AND type = 'primary';
CALL worker.process_tasks(p_queue => 'analytics');

\echo
\echo "144.6 an edit of LU-3's establishment alone lists LU-3: its primary establishment has another activity"
SELECT f.rule, u.unit_type, u.name
FROM public.quality_finding AS f JOIN fixture_unit AS u USING (unit_type, unit_id)
WHERE u.name LIKE 'LU-3%'
ORDER BY f.rule, u.unit_type, u.name;

-- A per-variable rule follows its variable without any unit edit: LU-4 has employees 5 and its
-- establishment 9 (establishments above the legal unit).
SELECT id AS employees_id FROM public.stat_definition WHERE code = 'employees' \gset
INSERT INTO public.stat_for_unit (stat_definition_id, valid_from, legal_unit_id, value_int, edit_by_user_id, edit_comment)
SELECT :employees_id, '2020-01-01'::date, lu.id, 5, :user_id, '0pn35h own value'
FROM public.legal_unit AS lu WHERE lu.name = 'LU-4';
INSERT INTO public.stat_for_unit (stat_definition_id, valid_from, establishment_id, value_int, edit_by_user_id, edit_comment)
SELECT :employees_id, '2020-01-01'::date, es.id, 9, :user_id, '0pn35h establishment value'
FROM public.establishment AS es WHERE es.name = 'LU-4-es';
CALL worker.process_tasks(p_queue => 'analytics');
SET client_min_messages TO WARNING;
UPDATE public.stat_definition SET enabled = false WHERE code = 'employees';
RESET client_min_messages;
CALL worker.process_tasks(p_queue => 'analytics');

\echo
\echo "144.7 disabling employees, with no unit edited, rederives nothing: LU-4's employees finding stays until bxt67q schedules it"
SELECT count(*) AS employees_findings FROM public.quality_finding WHERE stat_definition_id = :employees_id;

SET client_min_messages TO WARNING;
UPDATE public.stat_definition SET enabled = true WHERE code = 'employees';
RESET client_min_messages;
CALL worker.process_tasks(p_queue => 'analytics');

\echo
\echo "144.8 enabling it again lists LU-4 for employees: establishments above the legal unit"
SELECT f.rule, sd.code AS stat_code, u.name
FROM public.quality_finding AS f
JOIN fixture_unit AS u USING (unit_type, unit_id)
JOIN public.stat_definition AS sd ON sd.id = f.stat_definition_id
ORDER BY f.rule, u.name;

ROLLBACK;

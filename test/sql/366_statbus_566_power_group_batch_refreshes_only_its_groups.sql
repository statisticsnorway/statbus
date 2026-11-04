-- STATBUS-566: a power-group refresh batch refreshes exactly its power groups.
--
-- worker.derive_statistical_unit enqueues power groups in their own
-- statistical_unit_refresh_batch tasks, whose payload carries only
-- power_group_ids. The batch passes its establishment, legal-unit and
-- enterprise id ranges to timepoints_refresh and timesegments_refresh, and
-- public.timepoints_calculate reads a NULL range as "every unit of that type"
-- and the empty range '{}' as "none". A power-group batch must therefore name
-- the other unit types as empty, so that it computes the timepoints of its own
-- power groups and nothing else. On a Norway-sized database the difference is
-- one minute per batch (6.2M unit timepoints recomputed) against milliseconds.
--
-- Fixture: two legal units linked by a parent_company relationship (one power
-- group) and a third, independent legal unit. After a full derive, the
-- independent unit's timepoints are deleted, and a power-group-only batch runs.
-- The batch must leave the independent unit untouched (its timepoints stay
-- absent) and must produce the power group's timepoints.
--
-- This test pins the CORRECT values: on the pre-fix code the batch recomputes
-- every unit, the independent unit's timepoints reappear, and the diff against
-- this expected file is the regression.

BEGIN;

\i test/setup.sql

\echo "Test 366 (STATBUS-566): a power-group batch refreshes only its power groups"

ALTER SEQUENCE public.power_group_ident_seq RESTART WITH 1;

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\o
\set ECHO all

INSERT INTO public.legal_rel_type (code, name, description, primary_influencer_only, enabled, custom)
SELECT 'parent_company', 'Parent Company', 'Parent-subsidiary relationship', TRUE, true, false
WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type WHERE code = 'parent_company');

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT id, 'import_366_power_group', 'Test 366', 'Job context for process_power_group_link', 'Test 366'
FROM public.import_definition WHERE slug = 'legal_relationship_source_dates';
SELECT id AS test_job_id FROM public.import_job WHERE slug = 'import_366_power_group' \gset

INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT 'T366_' || n, (SELECT id FROM auth.user LIMIT 1), 'Test 366 enterprise ' || n
FROM generate_series(1, 3) AS n;

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, v.name, (SELECT id FROM public.enterprise WHERE short_name = v.en), true,
       (SELECT id FROM public.status WHERE code = 'active' LIMIT 1), (SELECT id FROM auth.user LIMIT 1), 'Test 366'
FROM (VALUES ('T366 Parent', 'T366_1'), ('T366 Subsidiary', 'T366_2'), ('T366 Independent', 'T366_3')) AS v(name, en);

INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2021-06-01'::date,
       (SELECT id FROM public.legal_unit WHERE name = 'T366 Parent'),
       (SELECT id FROM public.legal_unit WHERE name = 'T366 Subsidiary'),
       (SELECT id FROM public.legal_rel_type WHERE code = 'parent_company'),
       60.00, (SELECT id FROM auth.user LIMIT 1), 'Parent owns 60% of Subsidiary';

CALL import.process_power_group_link(:test_job_id, NULL, 'process_power_group_link');
CALL worker.process_tasks(p_queue => 'analytics');

SELECT id AS independent_lu_id FROM public.legal_unit WHERE name = 'T366 Independent' \gset
SELECT id AS power_group_id FROM public.power_group LIMIT 1 \gset

\echo
\echo "366.0 after the full derive: one power group, and the independent legal unit has timepoints"
SELECT (SELECT count(*) FROM public.power_group) AS power_groups,
       (SELECT count(*) FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = :independent_lu_id) > 0
         AS independent_has_timepoints,
       (SELECT count(*) FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = :power_group_id) > 0
         AS power_group_has_timepoints;

-- Mark the state the batch must not touch: remove the independent unit's
-- timepoints and the power group's timepoints. A batch that refreshes only the
-- power group restores the latter and leaves the former absent.
DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = :independent_lu_id;
DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = :power_group_id;

CALL worker.statistical_unit_refresh_batch(
    jsonb_build_object('batch_seq', 1, 'power_group_ids', jsonb_build_array(:power_group_id)), NULL);

\echo
\echo "366.1 the power-group batch produced the power group's timepoints"
SELECT tp.timepoint
FROM public.timepoints AS tp
WHERE tp.unit_type = 'power_group' AND tp.unit_id = :power_group_id
ORDER BY tp.timepoint;

\echo
\echo "366.2 the power-group batch left the independent legal unit untouched"
SELECT count(*) AS independent_timepoints_after_power_group_batch
FROM public.timepoints AS tp
WHERE tp.unit_type = 'legal_unit' AND tp.unit_id = :independent_lu_id;

ROLLBACK;

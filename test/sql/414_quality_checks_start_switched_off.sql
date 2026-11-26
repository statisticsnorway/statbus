\i test/setup.sql

\set ON_ERROR_STOP on

-- 1tx1ed: a check starts switched off and the installation records the checks switched on
-- (public.quality_check_switched_on). An installation upgrading from the switched-off table keeps
-- exactly the checks it showed: every check of quality_check is switched on unless it was in
-- quality_check_switched_off. Exercise the migration's shipped down and up files on a database that
-- has an extra summed variable and some checks switched off.

CALL test.set_user_from_email('test.admin@statbus.org');

\echo -- Return to the schema before the migration: switched-off checks are stored, absence means on.
\o /dev/null
\set ECHO none
\i migrations/20261126202817_quality_checks_start_switched_off_except_a_starting_set.down.sql
\set ECHO all
\o

SET client_min_messages TO WARNING;
INSERT INTO public.stat_definition (code, type, frequency, name, priority)
VALUES ('members', 'int', 'yearly', 'Members', 30);
RESET client_min_messages;
SELECT id AS members_id FROM public.stat_definition WHERE code = 'members' \gset
SELECT id AS employees_id FROM public.stat_definition WHERE code = 'employees' \gset

-- An installation that had switched off three checks (the down migration recorded the template's
-- starting set; this state replaces it).
DELETE FROM public.quality_check_switched_off WHERE true; -- every row: the state below replaces it
INSERT INTO public.quality_check_switched_off (rule, stat_definition_id)
VALUES ('missing_region', NULL),
       ('establishment_activity_differs', NULL),
       ('legal_unit_above_establishments', :members_id);

CREATE TEMP TABLE visible_before AS
SELECT qc.rule, qc.stat_definition_id FROM public.quality_check AS qc WHERE qc.on_dashboard;

\echo -- Before the upgrade: the checks this installation shows.
SELECT qc.rule, sd.code AS stat_code, qc.on_dashboard
FROM public.quality_check AS qc
LEFT JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
ORDER BY qc.priority;

\o /dev/null
\set ECHO none
\i migrations/20261126202817_quality_checks_start_switched_off_except_a_starting_set.up.sql
\set ECHO all
\o

\echo -- After the upgrade: the same checks show, read from the switched-on table.
SELECT qc.rule, sd.code AS stat_code, qc.on_dashboard
FROM public.quality_check AS qc
LEFT JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
ORDER BY qc.priority;

SELECT (SELECT count(*) FROM visible_before) AS visible_before,
       (SELECT count(*) FROM public.quality_check AS qc WHERE qc.on_dashboard) AS visible_after,
       NOT EXISTS (
           (SELECT rule, stat_definition_id FROM visible_before
            EXCEPT SELECT rule, stat_definition_id FROM public.quality_check WHERE on_dashboard)
           UNION ALL
           (SELECT rule, stat_definition_id FROM public.quality_check WHERE on_dashboard
            EXCEPT SELECT rule, stat_definition_id FROM visible_before)
       ) AS same_checks_visible;

\echo -- The switched-on rows are those visible checks, and the switched-off table is gone.
SELECT qs.rule, sd.code AS stat_code
FROM public.quality_check_switched_on AS qs
LEFT JOIN public.stat_definition AS sd ON sd.id = qs.stat_definition_id
ORDER BY qs.rule, sd.priority;
SELECT to_regclass('public.quality_check_switched_off') AS switched_off_table;

\echo -- A variable added after the upgrade brings its checks switched off.
SET client_min_messages TO WARNING;
INSERT INTO public.stat_definition (code, type, frequency, name, priority)
VALUES ('turnover_eur', 'float', 'yearly', 'Turnover EUR', 40);
RESET client_min_messages;
SELECT qc.rule, sd.code AS stat_code, qc.on_dashboard
FROM public.quality_check AS qc
JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
WHERE sd.code = 'turnover_eur'
ORDER BY qc.priority;

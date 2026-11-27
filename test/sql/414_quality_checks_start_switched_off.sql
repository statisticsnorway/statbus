\i test/setup.sql

\set ON_ERROR_STOP on

-- 1tx1ed, h9mhxe: a check starts switched off and the installation records the checks switched on.
-- Before h9mhxe the switched-on checks were rows of public.quality_check_switched_on; from it they are
-- public.quality_check.switched_on. An installation upgrading keeps exactly the checks it showed.
-- Exercise the migration's shipped down and up files on a database that has an extra summed variable
-- and a switched-on set other than the starting set.

CALL test.set_user_from_email('test.admin@statbus.org');

SET client_min_messages TO WARNING;
INSERT INTO public.stat_definition (code, type, frequency, name, priority)
VALUES ('members', 'int', 'yearly', 'Members', 30);
-- s465ff: the comparison checks apply to a variable whose legal unit total takes the larger level.
UPDATE public.stat_definition SET lu_es_rollup = 'max' WHERE code IN ('employees', 'members');
RESET client_min_messages;
SELECT id AS members_id FROM public.stat_definition WHERE code = 'members' \gset

\echo -- Return to the schema before the migration: switched-on checks are rows of quality_check_switched_on.
\o /dev/null
\set ECHO none
\i migrations/20261127162620_quality_row_checks_on_statistical_unit_and_relation_checks_in_their_own_tables.down.sql
\set ECHO all
\o

-- An installation that switched off missing region and switched on two other checks.
SET client_min_messages TO WARNING;
DELETE FROM public.quality_check_switched_on WHERE rule = 'missing_region';
INSERT INTO public.quality_check_switched_on (rule, stat_definition_id)
VALUES ('establishment_activity_differs', NULL),
       ('legal_unit_above_establishments', :members_id);
RESET client_min_messages;

CREATE TEMP TABLE visible_before AS
SELECT qc.rule, qc.stat_definition_id FROM public.quality_check AS qc WHERE qc.on_dashboard;

\echo -- Before the upgrade: the checks this installation shows.
SELECT qc.rule, sd.code AS stat_code, qc.on_dashboard
FROM public.quality_check AS qc
LEFT JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
ORDER BY qc.priority;

\o /dev/null
\set ECHO none
\i migrations/20261127162620_quality_row_checks_on_statistical_unit_and_relation_checks_in_their_own_tables.up.sql
\set ECHO all
\o

\echo -- After the upgrade: the same checks show, read from quality_check.switched_on.
SELECT qc.id, qc.rule, sd.code AS stat_code, qc.switched_on
FROM public.quality_check AS qc
LEFT JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
WHERE public.in_use(qc)
ORDER BY qc.priority;

SELECT (SELECT count(*) FROM visible_before) AS visible_before,
       (SELECT count(*) FROM public.quality_check AS qc WHERE qc.switched_on AND public.in_use(qc)) AS visible_after,
       NOT EXISTS (
           (SELECT rule, stat_definition_id FROM visible_before
            EXCEPT SELECT rule, stat_definition_id FROM public.quality_check AS qc WHERE qc.switched_on AND public.in_use(qc))
           UNION ALL
           (SELECT rule, stat_definition_id FROM public.quality_check AS qc WHERE qc.switched_on AND public.in_use(qc)
            EXCEPT SELECT rule, stat_definition_id FROM visible_before)
       ) AS same_checks_visible;

\echo -- The switched-on table is gone.
SELECT to_regclass('public.quality_check_switched_on') AS switched_on_table;

\echo -- A variable added after the upgrade brings its checks switched off.
SET client_min_messages TO WARNING;
INSERT INTO public.stat_definition (code, type, frequency, name, priority, lu_es_rollup)
VALUES ('turnover_eur', 'float', 'yearly', 'Turnover EUR', 40, 'max');
RESET client_min_messages;
SELECT qc.rule, sd.code AS stat_code, qc.switched_on
FROM public.quality_check AS qc
JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
WHERE sd.code = 'turnover_eur'
ORDER BY qc.priority;


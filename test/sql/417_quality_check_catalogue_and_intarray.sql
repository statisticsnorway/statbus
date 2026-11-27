-- test-isolation: database-per-test
-- The plan read here depends on the table's statistics; a database of its own gives every run
-- the same empty register and the same plan.
BEGIN;

\i test/setup.sql

\set ON_ERROR_STOP on

-- me96tn (h9mhxe): intarray is installed by the migrate runner, and with it integer[] && integer[]
-- resolves to intarray's operator. The Data source filter is served by
-- idx_statistical_unit_data_source_ids only when that index is built with gin__int_ops.
SELECT extname FROM pg_extension WHERE extname = 'intarray';

SET LOCAL enable_seqscan = off;
\echo -- The Data source filter (the SQL PostgREST makes of data_source_ids=ov.{1}) reads the index.
EXPLAIN (COSTS OFF) SELECT unit_id FROM public.statistical_unit WHERE data_source_ids && '{1}'::integer[];
RESET enable_seqscan;

-- me96tn: the check catalogue gives each check an integer id: fixed ids for the checks that are
-- not per variable, and one id per summed variable for each per-variable rule.
\echo -- The catalogue: row checks 1, 2, 3, 7; relation check 4; one check per summed variable per rule.
SELECT qc.id, qc.rule, sd.code AS variable, qc.kind, qc.priority
FROM public.quality_check_catalogue AS qc
LEFT JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
ORDER BY qc.priority;

CALL test.set_user_from_email('test.admin@statbus.org');
SET client_min_messages TO WARNING;

\echo -- A new summed variable gets an id for each per-variable rule; a text variable gets none.
INSERT INTO public.stat_definition (code, type, frequency, name, priority)
VALUES ('assets', 'int', 'yearly', 'Assets', 30),
       ('note', 'string', 'yearly', 'Note', 40);
SELECT qc.id, qc.rule, sd.code AS variable, qc.kind, qc.priority
FROM public.quality_check_catalogue AS qc
JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
WHERE sd.code IN ('assets', 'note')
ORDER BY qc.priority;

\echo -- Editing a variable keeps the ids of its checks and moves their priority with it.
UPDATE public.stat_definition SET priority = 35 WHERE code = 'assets';
SELECT qc.id, qc.rule, sd.code AS variable, qc.priority
FROM public.quality_check_catalogue AS qc
JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
WHERE sd.code = 'assets'
ORDER BY qc.priority;

\echo -- Deleting the variable removes its checks; the other checks keep their ids.
DELETE FROM public.stat_definition WHERE code IN ('assets', 'note');
SELECT qc.id, qc.rule, sd.code AS variable
FROM public.quality_check_catalogue AS qc
LEFT JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
ORDER BY qc.priority;

\echo -- A variable added after that gets new ids: the id of a removed check is not reused.
INSERT INTO public.stat_definition (code, type, frequency, name, priority)
VALUES ('assets', 'float', 'yearly', 'Assets', 30);
SELECT qc.id, qc.rule, sd.code AS variable
FROM public.quality_check_catalogue AS qc
JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
WHERE sd.code = 'assets'
ORDER BY qc.priority;

\echo -- The relation tables exist, empty, readable by a regular user.
CALL test.set_user_from_email('test.regular@statbus.org');
SELECT (SELECT count(*) FROM public.quality_establishment_activity_differs) AS activity_differs,
       (SELECT count(*) FROM public.quality_legal_unit_establishment_stat) AS establishment_stat,
       (SELECT count(*) FROM public.quality_check_catalogue) AS catalogue;

ROLLBACK;

-- STATBUS-600: monthly register intake closes units that left the register.
--
-- A monthly intake runs one full-file job per unit type (insert_or_update, the
-- job's valid_from is the 1st of the month) and then one deletion job per unit
-- type. A deletion row carries the unit's identifier, death_date = the date the
-- register deleted the unit, and its own valid_from = the 1st of the month that
-- contains the day before the death, so the record it writes starts before the
-- unit dies (the date_consistency step requires death_date > valid_from).
--
-- The state this test asserts:
--   * An unchanged unit in the next month's full file keeps one record; a
--     changed unit gets a new record from the job's valid_from.
--   * A deletion closes the unit on its exact death date, whether that date
--     falls in the job's month or in the previous month, and keeps the unit's
--     name and activity.
--   * The enterprise of a closed legal unit stops existing on the same day.
--   * Closing an establishment leaves its legal unit alive and linked.
--   * Closing a legal unit leaves its establishments as they are: the register
--     reports each establishment's deletion separately, as a row in the
--     establishment deletion job (895406732 has no such row here).
--   * Units over time counts each death in the month it happened.
SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

-- History reaches the current date; this intake happens in December 2026.
SELECT set_config('app.current_date', '2026-12-15', false);

\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\o
\set ECHO all

\echo "October and November full files (one job per month and unit type)"
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, default_valid_from, default_valid_to)
SELECT d.id, j.slug, j.slug, 'Test 395', j.valid_from, 'infinity'
FROM (VALUES
    ('legal_unit_job_provided',           'import_395_lu_2026_10', DATE '2026-10-01'),
    ('establishment_for_lu_job_provided', 'import_395_es_2026_10', DATE '2026-10-01'),
    ('legal_unit_job_provided',           'import_395_lu_2026_11', DATE '2026-11-01'),
    ('establishment_for_lu_job_provided', 'import_395_es_2026_11', DATE '2026-11-01')
) AS j(definition_slug, slug, valid_from)
JOIN public.import_definition AS d ON d.slug = j.definition_slug;

INSERT INTO public.import_395_lu_2026_10_upload
    (tax_ident, name, birth_date, physical_region_code, physical_country_iso_2, primary_activity_category_code, sector_code, legal_form_code)
VALUES
    ('921835809', 'KRAN AS',  '2013-01-01', '1121', 'NO', '49.410', '2100', 'AS'),
    ('823573673', 'LØFT AS',  '2010-01-01', '1121', 'NO', '49.410', '2100', 'AS'),
    ('917669791', 'STILL AS', '2015-01-01', '1121', 'NO', '49.410', '2100', 'AS');
INSERT INTO public.import_395_es_2026_10_upload
    (tax_ident, legal_unit_tax_ident, name, birth_date, physical_region_code, physical_country_iso_2, primary_activity_category_code)
VALUES
    ('895406732', '921835809', 'KRAN AS AVD',  '2013-01-01', '1121', 'NO', '49.410'),
    ('973117149', '917669791', 'STILL AS AVD', '2015-01-01', '1121', 'NO', '49.410');
CALL worker.process_tasks(p_queue => 'import');

-- November: 921835809 unchanged, 823573673 renamed, 917669791 unchanged.
INSERT INTO public.import_395_lu_2026_11_upload
    (tax_ident, name, birth_date, physical_region_code, physical_country_iso_2, primary_activity_category_code, sector_code, legal_form_code)
VALUES
    ('921835809', 'KRAN AS',         '2013-01-01', '1121', 'NO', '49.410', '2100', 'AS'),
    ('823573673', 'LØFT OG KRAN AS', '2010-01-01', '1121', 'NO', '49.410', '2100', 'AS'),
    ('917669791', 'STILL AS',        '2015-01-01', '1121', 'NO', '49.410', '2100', 'AS');
INSERT INTO public.import_395_es_2026_11_upload
    (tax_ident, legal_unit_tax_ident, name, birth_date, physical_region_code, physical_country_iso_2, primary_activity_category_code)
VALUES
    ('895406732', '921835809', 'KRAN AS AVD',  '2013-01-01', '1121', 'NO', '49.410'),
    ('973117149', '917669791', 'STILL AS AVD', '2015-01-01', '1121', 'NO', '49.410');
CALL worker.process_tasks(p_queue => 'import');

\echo "Deletion jobs: identifier, death date, and a valid_from of the 1st of the month before the death"
INSERT INTO public.import_job (definition_id, slug, description, edit_comment)
SELECT d.id, j.slug, j.slug, 'Test 395'
FROM (VALUES
    ('legal_unit_source_dates',           'import_395_lu_deleted_2026_11'),
    ('establishment_for_lu_source_dates', 'import_395_es_deleted_2026_11')
) AS j(definition_slug, slug)
JOIN public.import_definition AS d ON d.slug = j.definition_slug;

-- 921835809 died on 2026-11-07 (in the job's month), 823573673 on 2026-10-25
-- (the previous month). The establishment 973117149 died on 2026-11-20; its
-- legal unit 917669791 stays alive.
INSERT INTO public.import_395_lu_deleted_2026_11_upload (tax_ident, death_date, valid_from, valid_to)
SELECT tax_ident, death_date, date_trunc('month', death_date - 1)::date, 'infinity'
FROM (VALUES ('921835809', DATE '2026-11-07'), ('823573673', DATE '2026-10-25')) AS t(tax_ident, death_date);
INSERT INTO public.import_395_es_deleted_2026_11_upload (tax_ident, death_date, valid_from, valid_to)
SELECT tax_ident, death_date, date_trunc('month', death_date - 1)::date, 'infinity'
FROM (VALUES ('973117149', DATE '2026-11-20')) AS t(tax_ident, death_date);
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Every job finished and imported every row"
SELECT slug, state, total_rows, imported_rows
FROM public.import_job
WHERE slug LIKE 'import_395_%'
ORDER BY slug;

\echo "Legal unit records: one per unchanged month, a new record per change, death dates set"
SELECT ei.ident AS tax_ident, lu.valid_from, lu.valid_until, lu.name, lu.death_date, lu.existence_until
FROM public.legal_unit AS lu
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id
ORDER BY ei.ident, lu.valid_from;

\echo "Establishment records: the closed establishment keeps its legal unit link"
SELECT ei.ident AS tax_ident, es.valid_from, es.valid_until, es.name, es.death_date, es.existence_until,
       lu_ei.ident AS legal_unit_tax_ident
FROM public.establishment AS es
JOIN public.external_ident AS ei ON ei.establishment_id = es.id
JOIN public.external_ident AS lu_ei ON lu_ei.legal_unit_id = es.legal_unit_id
ORDER BY ei.ident, es.valid_from;

\echo "Each unit, its enterprise included, stops existing on its death date"
SELECT su.unit_type, su.external_idents ->> 'tax_ident' AS tax_ident,
       max(su.existence_until) AS exists_until
FROM public.statistical_unit AS su
GROUP BY su.unit_type, su.external_idents ->> 'tax_ident'
ORDER BY su.unit_type, tax_ident;

\echo "Units over time: each death counted in its month"
SELECT unit_type, year, month, countable_count, births, deaths
FROM public.statistical_history
WHERE resolution = 'year-month' AND year = 2026 AND month IN (10, 11, 12)
ORDER BY unit_type, month;

ROLLBACK;

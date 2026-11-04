-- STATBUS-565: the stored statistical_history_facet must equal its definition
-- after every derive, in every column.
--
-- worker.statistical_history_facet_reduce MERGEs the summed partitions into
-- public.statistical_history_facet. A matched row is rewritten only when its
-- exists_count or stats_summary changed. A change that leaves both unchanged,
-- such as a rename (name_change_count) or an address change
-- (physical_address_change_count), is never written, so the stored row keeps
-- the counts from the previous derive.
--
-- Fixture: one legal unit, imported, derived, then renamed from 2024-06-01 with
-- the same employees, and derived again. The 2024 year cell keeps exists_count 1
-- and the same stats_summary, while name_change_count goes from 0 to 1.
--
-- This test pins the CORRECT values: on the pre-fix code the stored
-- name_change_count stays 0 and stored_equals_definition is false, and the diff
-- against this expected file is the regression.

BEGIN;

\i test/setup.sql

\echo "Test 365 (STATBUS-565): history facet reduce writes every changed column"

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_565a', 'Test 365 one legal unit', 'Test 365 (STATBUS-565)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_565a_upload(valid_from, valid_to, tax_ident, name, employees) VALUES
    ('2020-01-01', 'infinity', '565000001', 'Original name', '10');

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo
\echo "365.0 before the rename: 2024 cell has no name change"
SELECT f.exists_count, f.name_change_count, (f.stats_summary->'employees'->>'sum')::numeric AS employees_sum
FROM public.statistical_history_facet AS f
WHERE f.resolution = 'year' AND f.year = 2024 AND f.unit_type = 'legal_unit';

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_565b', 'Test 365 rename from 2024-06-01, same employees', 'Test 365 (STATBUS-565)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_565b_upload(valid_from, valid_to, tax_ident, name, employees) VALUES
    ('2024-06-01', 'infinity', '565000001', 'New name', '10');

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo
\echo "365.1 both imports finished"
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug LIKE 'import_565%' ORDER BY slug;

\echo
\echo "365.2 the legal unit's timeline: renamed from 2024-06-01"
SELECT su.name, su.valid_from, su.valid_to
FROM public.statistical_unit AS su
WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = '565000001'
ORDER BY su.valid_from;

\echo
\echo "365.3 the stored 2024 cell equals the definition: one rename, same count and stats"
WITH definition AS (
    SELECT d.unit_type,
           sum(d.exists_count)::integer AS exists_count,
           sum(d.name_change_count)::integer AS name_change_count,
           jsonb_stats_merge_agg(d.stats_summary) AS stats_summary
    FROM public.statistical_history_facet_def('year', 2024, NULL) AS d
    WHERE d.unit_type = 'legal_unit'
    GROUP BY d.unit_type
)
SELECT d.exists_count AS expected_exists_count,
       f.exists_count AS stored_exists_count,
       d.name_change_count AS expected_name_change_count,
       f.name_change_count AS stored_name_change_count,
       d.stats_summary = f.stats_summary AS stats_equal,
       d.exists_count = f.exists_count
         AND d.name_change_count = f.name_change_count
         AND d.stats_summary = f.stats_summary AS stored_equals_definition
FROM definition AS d
JOIN public.statistical_history_facet AS f
  ON f.resolution = 'year' AND f.year = 2024 AND f.unit_type = d.unit_type;

\echo
\echo "365.4 every stored legal-unit row equals the definition in every column, for every year and month"
WITH periods AS (
    SELECT DISTINCT f.resolution, f.year, f.month
    FROM public.statistical_history_facet AS f
),
definition AS (
    SELECT d.*
    FROM periods AS p
    CROSS JOIN LATERAL public.statistical_history_facet_def(p.resolution, p.year, p.month) AS d
    WHERE d.unit_type = 'legal_unit'
),
def_rows AS (
    SELECT resolution, year, month, unit_type,
           primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id,
           physical_region_path, physical_country_id, unit_size_id, status_id,
           exists_count, exists_change, exists_added_count, exists_removed_count,
           countable_count, countable_change, countable_added_count, countable_removed_count,
           births, deaths, name_change_count, primary_activity_category_change_count,
           secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
           physical_region_change_count, physical_country_change_count, physical_address_change_count,
           unit_size_change_count, status_change_count, stats_summary
    FROM definition
),
stored_rows AS (
    SELECT resolution, year, month, unit_type,
           primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id,
           physical_region_path, physical_country_id, unit_size_id, status_id,
           exists_count, exists_change, exists_added_count, exists_removed_count,
           countable_count, countable_change, countable_added_count, countable_removed_count,
           births, deaths, name_change_count, primary_activity_category_change_count,
           secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
           physical_region_change_count, physical_country_change_count, physical_address_change_count,
           unit_size_change_count, status_change_count, stats_summary
    FROM public.statistical_history_facet
    WHERE unit_type = 'legal_unit'
)
SELECT (SELECT count(*) FROM def_rows) AS definition_rows,
       (SELECT count(*) FROM stored_rows) AS stored_rows,
       (SELECT count(*) FROM (SELECT * FROM def_rows EXCEPT ALL SELECT * FROM stored_rows) AS x) AS only_in_definition,
       (SELECT count(*) FROM (SELECT * FROM stored_rows EXCEPT ALL SELECT * FROM def_rows) AS x) AS only_in_stored;

ROLLBACK;

-- STATBUS-565: statistical_history_facet must show every column's change
-- after every derive.
--
-- Before STATBUS-558, worker.statistical_history_facet_reduce MERGEd summed
-- partitions into a stored statistical_history_facet and rewrote a matched row
-- only when its exists_count or stats_summary changed. A change that left both
-- unchanged, such as a rename (name_change_count), was never written.
-- statistical_history_facet is now a view over history_flow_delta, where a
-- unit's change counts are staged and added like any other delta.
--
-- Fixture: one legal unit, imported, derived, then renamed from 2024-06-01 with
-- the same employees, and derived again. The 2024 year cell keeps exists_count 1
-- and the same stats_summary, while name_change_count goes from 0 to 1.

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
\echo "365.3 the 2024 legal-unit cell shows the rename: same count and stats, one name change"
SELECT f.exists_count, f.name_change_count, (f.stats_summary->'employees'->>'sum')::numeric AS employees_sum
FROM public.statistical_history_facet AS f
WHERE f.resolution = 'year' AND f.year = 2024 AND f.unit_type = 'legal_unit';

\echo
\echo "365.4 the rename is counted in 2024 and in June 2024 only"
SELECT f.resolution, f.year, f.month, f.name_change_count
FROM public.statistical_history_facet AS f
WHERE f.unit_type = 'legal_unit' AND f.name_change_count <> 0
ORDER BY f.resolution, f.year, f.month;

ROLLBACK;

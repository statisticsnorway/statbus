-- Test 355 (STATBUS-538): the drilldown facets equal statistical_unit after
-- reset() + reimport, and a full recalculation rebuilds them from scratch.
--
-- statistical_unit_facet is the reduce of statistical_unit_facet_staging, a
-- per-hash_slot cache. Its contract: for every unit_type x region at a date,
-- facet count = number of countable statistical_unit rows existing then.
--
-- Scenario (as on demo 2026-10-30):
--   1. Import legal units, drain.
--   2. reset(true, 'data') clears the units.
--   3. Import again: new ids land in other hash slots.
--   4. Facets must equal statistical_unit.
--   5. A full recalculation, collect_changes with every *_id_ranges NULL
--      (all units, all time), with no caller-side TRUNCATE, must leave
--      facets equal to statistical_unit.

BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');
\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

CREATE TEMP VIEW facet_vs_truth AS
WITH truth AS (
  SELECT unit_type, COALESCE(subpath(physical_region_path, 0, 1)::text, '-') AS region, COUNT(*)::int AS n
  FROM public.statistical_unit
  WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until AND used_for_counting
  GROUP BY 1, 2
), facet AS (
  SELECT unit_type, COALESCE(subpath(physical_region_path, 0, 1)::text, '-') AS region, SUM(count)::int AS n
  FROM public.statistical_unit_facet
  WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until
  GROUP BY 1, 2
)
SELECT unit_type, region, t.n AS truth_count, f.n AS facet_count, t.n IS NOT DISTINCT FROM f.n AS matches
FROM truth AS t FULL JOIN facet AS f USING (unit_type, region)
ORDER BY unit_type, region;

\echo "=== 1. First import ==="
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_355_first', 'Test 355 first load', 'test 355', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
\copy public.import_355_first_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
\o /dev/null
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
\o

\echo "After first import: facets equal statistical_unit"
SELECT * FROM facet_vs_truth;

\echo "=== 2. reset(true, 'data') ==="
\o /dev/null
SELECT public.reset(true, 'data');
\o
SELECT (SELECT count(*) FROM public.legal_unit) AS legal_units,
       (SELECT count(*) FROM public.statistical_unit) AS statistical_units;

\echo "=== 3. Second import: new ids, other hash slots ==="
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_355_second', 'Test 355 second load', 'test 355', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
\copy public.import_355_second_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
\o /dev/null
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
\o

\echo "=== 4. After reset + reimport: facets equal statistical_unit ==="
SELECT * FROM facet_vs_truth;

\echo "=== 5. Staging holds rows for slots without units (as left by a reset before STATBUS-538) ==="
-- Copy every staging row into a slot no current unit hashes to. These rows
-- stand for units that vanished without a change-log entry. The staging
-- table is worker-owned, so this setup runs as postgres.
SET LOCAL ROLE postgres;
INSERT INTO public.statistical_unit_facet_staging
SELECT (s.hash_slot + 1) % 16384, s.valid_from, s.valid_to, s.valid_until, s.unit_type,
       s.physical_region_path, s.primary_activity_category_path, s.sector_path,
       s.legal_form_id, s.physical_country_id, s.status_id, s.count, s.stats_summary
FROM public.statistical_unit_facet_staging AS s
WHERE NOT EXISTS (SELECT 1 FROM public.statistical_unit AS su WHERE su.hash_slot = (s.hash_slot + 1) % 16384)
ON CONFLICT DO NOTHING;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "=== 6. Full recalculation (all ids NULL, all time), no TRUNCATE ==="
SELECT worker.spawn(
    p_command => 'collect_changes',
    p_payload => jsonb_build_object(
        'establishment_id_ranges', NULL,
        'legal_unit_id_ranges',    NULL,
        'enterprise_id_ranges',    NULL,
        'power_group_id_ranges',   NULL,
        'valid_ranges',            NULL
    )
) IS NOT NULL AS task_queued;
\o /dev/null
CALL worker.process_tasks(p_queue => 'analytics');
\o

\echo "After full recalculation: facets equal statistical_unit"
SELECT * FROM facet_vs_truth;

\echo "After full recalculation: history facets equal statistical_unit for the current year"
WITH truth AS (
  SELECT unit_type, COUNT(*)::int AS n FROM public.statistical_unit
  WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until AND used_for_counting
  GROUP BY 1
), hist AS (
  SELECT unit_type, SUM(exists_count)::int AS n FROM public.statistical_history_facet
  WHERE resolution = 'year' AND year = EXTRACT(YEAR FROM CURRENT_DATE)::int
  GROUP BY 1
)
SELECT unit_type, t.n AS truth_count, h.n AS history_facet_count, t.n IS NOT DISTINCT FROM h.n AS matches
FROM truth AS t FULL JOIN hist AS h USING (unit_type)
ORDER BY unit_type;

ROLLBACK;

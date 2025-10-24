SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

\echo "Setting up Statbus to test enterprise grouping and primary"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id,only_one_setting)
SELECT id, true FROM activity_category_standard WHERE code = 'nace_v2.1'
ON CONFLICT (only_one_setting)
DO UPDATE SET
   activity_category_standard_id =(SELECT id FROM activity_category_standard WHERE code = 'nace_v2.1')
   WHERE settings.id = EXCLUDED.id;
;
SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;

\echo "User uploads the sample activity categories"
\copy public.activity_category_available_custom(path,name,description) FROM 'samples/norway/activity_category/activity_category_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.activity_category_available;

\echo "User uploads the sample regions"
\copy public.region_upload(path, name) FROM 'samples/norway/regions/norway-regions-2024.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.region;

\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'samples/norway/legal_form/legal_form_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.legal_form_available;

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'samples/norway/sector/sector_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
SELECT count(*) FROM public.sector_available;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units with Status
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_35_lu_era_status',
    'Import LU Era with Status (35_load_with_status_codes.sql)',
    'Import job for test/data/35_norwegian-legal-units-with-status.csv.',
    'Test data load (35_load_with_status_codes.sql)';
\echo "User uploads the legal units (via import job: import_35_lu_era_status)"
\copy public.import_35_lu_era_status_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code,status_code) FROM 'test/data/35_norwegian-legal-units-with-status.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Establishments with Status
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_35_esflu_era_status',
    'Import ES Era with Status (35_load_with_status_codes.sql)',
    'Import job for test/data/35_norwegian-establishments-with-status.csv.',
    'Test data load (35_load_with_status_codes.sql)';
\echo "User uploads the establishments (via import job: import_35_esflu_era_status)"
\copy public.import_35_esflu_era_status_upload(valid_from, valid_to, tax_ident,legal_unit_tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,status_code) FROM 'test/data/35_norwegian-establishments-with-status.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error
FROM public.import_job
WHERE slug LIKE 'import_35_%' ORDER BY slug;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Checking current statistical units that are included in reports"
SELECT valid_from, valid_to, name, unit_type,  jsonb_pretty(stats_summary) AS stats_summary, status_code, used_for_counting
FROM public.statistical_unit
WHERE used_for_counting
AND valid_to = 'infinity'
ORDER BY unit_type, valid_from;


\echo "Testing statistical unit drilldown - should only include units that have used_for_counting set to true"
SELECT jsonb_pretty(public.remove_ephemeral_data_from_hierarchy(public.statistical_unit_facet_drilldown(
     valid_on := '2025-01-01'
)))
    AS statistical_unit_facet_drilldown;

\echo "Test statistical unit history by year"

SELECT
    resolution, year, unit_type,
    exists_count, exists_change, exists_added_count, exists_removed_count,
    countable_count, countable_change, countable_added_count, countable_removed_count
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2013
ORDER BY year,unit_type;

SELECT
    resolution, year, unit_type,
    countable_count AS count,
    births, deaths
FROM public.statistical_history
WHERE resolution = 'year'
AND year < 2013
ORDER BY year,unit_type;

SELECT jsonb_pretty(public.remove_ephemeral_data_from_hierarchy(public.statistical_history_drilldown(
    year_min := 2010,
    year_max := 2011
)))
    AS statistical_history_drilldown;


    \echo "Test yearly drilldown - enterprise"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          unit_type := 'enterprise'::public.statistical_unit_type,
          resolution := 'year'::public.history_resolution,
          year := NULL::INTEGER,
          region_path := NULL::public.ltree,
          activity_category_path := NULL::public.ltree,
          sector_path := NULL::public.ltree,
          legal_form_id := NULL::INTEGER,
          country_id := NULL::INTEGER,
          year_min := 2010,
          year_max := 2012
     ))) AS statistical_history_drilldown;

\echo "Test yearly drilldown - legal_unit"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          unit_type := 'legal_unit'::public.statistical_unit_type,
          resolution := 'year'::public.history_resolution,
          year := NULL::INTEGER,
          region_path := NULL::public.ltree,
          activity_category_path := NULL::public.ltree,
          sector_path := NULL::public.ltree,
          legal_form_id := NULL::INTEGER,
          country_id := NULL::INTEGER,
          year_min := 2010,
          year_max := 2012
     ))) AS statistical_history_drilldown;

\echo "Test yearly drilldown - establishment"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          unit_type := 'establishment'::public.statistical_unit_type,
          resolution := 'year'::public.history_resolution,
          year := NULL::INTEGER,
          region_path := NULL::public.ltree,
          activity_category_path := NULL::public.ltree,
          sector_path := NULL::public.ltree,
          legal_form_id := NULL::INTEGER,
          country_id := NULL::INTEGER,
          year_min := 2010,
          year_max := 2012
     ))) AS statistical_history_drilldown;




ROLLBACK;

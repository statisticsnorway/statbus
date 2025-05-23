BEGIN;

\i test/setup.sql

\echo "Setting up Statbus to load establishments without legal units"

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

-- SAVEPOINT before_loading_units; -- Removed to simplify transaction handling, aligning with other tests.

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units (Era)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_explicit_dates'),
    'import_03_lu_era',
    'Import Legal Units Era (03_load_and_verify_history_functions.sql)',
    'Import job for legal units from test/data/03_norwegian-legal-units-over-time.csv using legal_unit_explicit_dates definition.',
    'Test data load (03_load_and_verify_history_functions.sql)';

\echo "User uploads the legal units over time (via import job: import_03_lu_era)"
\copy public.import_03_lu_era_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code,data_source_code) FROM 'test/data/03_norwegian-legal-units-over-time.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Establishments (Era for LU)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_explicit_dates'),
    'import_03_esflu_era',
    'Import Establishments Era for LU (03_load_and_verify_history_functions.sql)',
    'Import job for establishments from test/data/03_norwegian-establishments-over-time.csv using establishment_for_lu_explicit_dates definition.',
    'Test data load (03_load_and_verify_history_functions.sql)';

\echo "User uploads the establishments over time (via import job: import_03_esflu_era)"
\copy public.import_03_esflu_era_upload(valid_from, valid_to, tax_ident,legal_unit_tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,data_source_code,unit_size_code,employees,turnover) FROM 'test/data/03_norwegian-establishments-over-time.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Test get_statistical_history_periods with specific date range - yearly resolution"
SELECT
    resolution,
    year,
    month,
    prev_stop,
    curr_start,
    curr_stop
FROM public.get_statistical_history_periods(
    p_resolution := 'year',
    p_valid_after := '2018-01-01',
    p_valid_to := '2020-12-31'
)
ORDER BY year;

\echo "Test get_statistical_history_periods with NULL parameters (should use bounded range)"
SELECT
    resolution,
    year,
    month,
    prev_stop,
    curr_start,
    curr_stop
FROM public.get_statistical_history_periods(
    p_resolution := 'year'
)
WHERE year BETWEEN EXTRACT(YEAR FROM current_date - interval '5 years')::int
              AND EXTRACT(YEAR FROM current_date)::int
ORDER BY year;

\echo "Test get_statistical_history_periods with empty table simulation"
-- Test with specific date range, which will use default values since table is empty at this point
SELECT
    resolution,
    year,
    month,
    prev_stop,
    curr_start,
    curr_stop
FROM public.get_statistical_history_periods(
    p_resolution := 'year',
    p_valid_after := '2020-01-01',
    p_valid_to := '2022-12-31'
)
WHERE year BETWEEN 2020 AND 2022
ORDER BY year;

\echo "Test get_statistical_history_periods with specific date range - monthly resolution"
SELECT
    resolution,
    year,
    month,
    prev_stop,
    curr_start,
    curr_stop
FROM public.get_statistical_history_periods(
    p_resolution := 'year-month',
    p_valid_after := '2019-06-01',
    p_valid_to := '2019-12-31'
)
ORDER BY year, month;


\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Inspecting import job data for import_03_lu_era"
SELECT row_id, state, error, tax_ident, name, valid_from, valid_to
FROM public.import_03_lu_era_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_03_lu_era"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_03_lu_era_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_03_lu_era';

\echo "Inspecting import job data for import_03_esflu_era"
SELECT row_id, state, error, tax_ident, legal_unit_tax_ident, name, valid_from, valid_to
FROM public.import_03_esflu_era_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_03_esflu_era"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_03_esflu_era_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_03_esflu_era';

\echo "Checking statistical_history_periods from statistical_unit data"
SELECT * FROM public.get_statistical_history_periods()
-- Only list previous years, so the test is stable over time.
WHERE year <= 2023;


\echo "Checking timepoints."
SELECT tp.unit_type
     , COALESCE
          ( public.get_external_idents(tp.unit_type, tp.unit_id)->>'tax_ident'
          , eei.external_idents->>'tax_ident'
          ) AS tax_ident
     , tp.timepoint
FROM public.timepoints AS tp
LEFT JOIN public.enterprise_external_idents AS eei
       ON eei.unit_type = tp.unit_type
      AND eei.unit_id = tp.unit_id
      AND eei.valid_after <= tp.timepoint AND tp.timepoint <= eei.valid_to
ORDER BY tp.unit_type, tp.timepoint, tp.unit_id;

\echo "Checking timesegments."
SELECT ts.unit_type
     , COALESCE
          ( public.get_external_idents(ts.unit_type, ts.unit_id)->>'tax_ident'
          , eei.external_idents->>'tax_ident'
          ) AS tax_ident
     , ts.valid_after
     , ts.valid_to
FROM public.timesegments AS ts
LEFT JOIN public.enterprise_external_idents AS eei
       ON eei.unit_type = ts.unit_type
      AND eei.unit_id = ts.unit_id
      AND eei.valid_after <= ts.valid_after AND ts.valid_to <= eei.valid_to
ORDER BY ts.unit_type, ts.valid_after, ts.unit_id;


\echo "Checking timeline_establishment data"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , birth_date
     , death_date
     , search
     , primary_activity_category_path
     , secondary_activity_category_path
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_address_part1
     , physical_address_part2
     , physical_address_part3
     , physical_postcode
     , physical_postplace
     , physical_region_path
     , physical_country_iso_2
     , postal_address_part1
     , postal_address_part2
     , postal_address_part3
     , postal_postcode
     , postal_postplace
     , postal_region_path
     , postal_country_iso_2
     , invalid_codes
FROM public.timeline_establishment
ORDER BY unit_type, unit_id, valid_after, valid_to;


\echo "Checking timeline_establishment stats"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , stats
FROM public.timeline_establishment
ORDER BY unit_type, unit_id, valid_after, valid_to;

\echo "Checking timeline_legal_unit data"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , birth_date
     , death_date
     , search
     , primary_activity_category_path
     , secondary_activity_category_path
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_address_part1
     , physical_address_part2
     , physical_address_part3
     , physical_postcode
     , physical_postplace
     , physical_region_path
     , physical_country_iso_2
     , postal_address_part1
     , postal_address_part2
     , postal_address_part3
     , postal_postcode
     , postal_postplace
     , postal_region_path
     , postal_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;


\x
\echo "Checking timeline_legal_unit stats"
SELECT unit_type
     , public.get_external_idents(unit_type, unit_id)->>'tax_ident' AS tax_ident
     , valid_after
     , valid_from
     , valid_to
     , name
     , stats
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;
\x


\echo "Checking timeline_enterprise data"
SELECT te.unit_type
     , eei.external_idents->>'tax_ident' AS tax_ident
     , te.valid_after
     , te.valid_from
     , te.valid_to
     , te.name
     , te.birth_date
     , te.death_date
     , te.search
     , te.primary_activity_category_path
     , te.secondary_activity_category_path
     , te.activity_category_paths
     , te.sector_path
     , te.sector_code
     , te.sector_name
     , te.data_source_codes
     , te.legal_form_code
     , te.legal_form_name
     , te.physical_address_part1
     , te.physical_address_part2
     , te.physical_address_part3
     , te.physical_postcode
     , te.physical_postplace
     , te.physical_region_path
     , te.physical_country_iso_2
     , te.postal_address_part1
     , te.postal_address_part2
     , te.postal_address_part3
     , te.postal_postcode
     , te.postal_postplace
     , te.postal_region_path
     , te.postal_country_iso_2
     , te.invalid_codes
FROM public.timeline_enterprise AS te
LEFT JOIN public.enterprise_external_idents AS eei
       ON eei.unit_type = te.unit_type
      AND eei.unit_id = te.unit_id
      AND daterange(eei.valid_after, eei.valid_to, '(]')
       && daterange(te.valid_after, te.valid_to, '(]')
ORDER BY te.unit_type, te.unit_id, te.valid_after, te.valid_to;


\x
\echo "Checking timeline_enterprise stats"
SELECT te.unit_type
     , eei.external_idents->>'tax_ident' AS tax_ident
     , te.valid_after
     , te.valid_from
     , te.valid_to
     , te.name
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.timeline_enterprise AS te
LEFT JOIN public.enterprise_external_idents AS eei
       ON eei.unit_type = te.unit_type
      AND eei.unit_id = te.unit_id
      AND daterange(eei.valid_after, eei.valid_to, '(]')
       && daterange(te.valid_after, te.valid_to, '(]')
ORDER BY te.unit_type, te.unit_id, te.valid_after, te.valid_to;
\x


\x
\echo "Check statistical_unit"
SELECT valid_after
     , valid_from
     , valid_to
     , unit_type
     , external_idents
     , jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
          to_jsonb(statistical_unit.*)
          -'stats'
          -'stats_summary'
          -'valid_after'
          -'valid_from'
          -'valid_to'
          -'unit_type'
          -'external_idents'
          )
     ) AS statistical_unit_data
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
 FROM public.statistical_unit
 ORDER BY valid_after, valid_from, valid_to, unit_type, unit_id;

\echo "Checking statistical_unit totals"
SELECT unit_type
     , COUNT(DISTINCT unit_id) AS distinct_unit_count
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , jsonb_pretty(jsonb_stats_summary_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 GROUP BY unit_type;
\x

\echo "Test over the years"

\echo "Verify the generation of ranges for all periods"
SELECT * FROM public.get_statistical_history_periods()
-- Only list previous years, so the test is stable over time.
WHERE year <= 2024;

\echo "Test yearly data"
SELECT year
     , unit_type
     , count
     , births
     , deaths
     , primary_activity_category_change_count
     , secondary_activity_category_change_count
     , sector_change_count
     , legal_form_change_count
     , physical_region_change_count
     , physical_country_change_count
FROM public.statistical_history
WHERE resolution = 'year'
  AND year <= 2024
ORDER BY year,unit_type;

\echo "Test yearly stats"
SELECT year
     , unit_type
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history
WHERE resolution = 'year'
  AND year <= 2024
ORDER BY year,unit_type;

\echo "Test monthly data for 2019"
SELECT year, month
     , unit_type
     , count
     , births
     , deaths
     , primary_activity_category_change_count
     , secondary_activity_category_change_count
     , sector_change_count
     , legal_form_change_count
     , physical_region_change_count
     , physical_country_change_count
FROM public.statistical_history
WHERE resolution = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

\echo "Test monthly stats for 2019"
SELECT year, month
     , unit_type
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history
WHERE resolution = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

\x
\echo "Inspect facet summary table"
SELECT valid_from
     , valid_to
     , unit_type
     , physical_region_path
     , primary_activity_category_path
     , sector_path
     , count
     , jsonb_pretty(stats_summary) AS stats_summary
  FROM public.statistical_unit_facet
  ORDER BY valid_from, valid_to, unit_type
;
\x

\echo "Test yearly facet data"
SELECT year
     , unit_type
     , primary_activity_category_path
     , secondary_activity_category_path
     , sector_path
     , physical_region_path
     , count
     , births
     , deaths
     , primary_activity_category_change_count
     , secondary_activity_category_change_count
     , sector_change_count
     , legal_form_change_count
     , physical_region_change_count
     , physical_country_change_count
FROM public.statistical_history_facet
WHERE resolution = 'year'
  AND year <= 2024
ORDER BY year,unit_type;

\echo "Test yearly facet stats"
SELECT year
     , unit_type
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history_facet
WHERE resolution = 'year'
  AND year <= 2024
ORDER BY year,unit_type;

\echo "Test monthly facet data for 2019"
SELECT year, month
     , unit_type
     , primary_activity_category_path
     , secondary_activity_category_path
     , sector_path
     , physical_region_path
     , count
     , births
     , deaths
     , primary_activity_category_change_count
     , secondary_activity_category_change_count
     , sector_change_count
     , legal_form_change_count
     , physical_region_change_count
     , physical_country_change_count
FROM public.statistical_history_facet
WHERE resolution = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

\echo "Test monthly facet data"
SELECT year, month
     , unit_type
     , jsonb_pretty(stats_summary) AS stats_summary
FROM public.statistical_history_facet
WHERE resolution = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

\a
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
          year_max := 2024
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
          year_max := 2024
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
          year_max := 2024
     ))) AS statistical_history_drilldown;

\echo "Test yearly drilldown - enterprise - with all filters as top level"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          unit_type := 'enterprise'::public.statistical_unit_type,
          resolution := 'year'::public.history_resolution,
          year := 2019,
          region_path := '11'::public.ltree,
          activity_category_path := 'H'::public.ltree,
          sector_path := 'innl'::public.ltree,
          legal_form_id := (SELECT id FROM public.legal_form WHERE code = 'AS'),
          country_id := (SELECT id FROM public.country WHERE iso_2 = 'NO'),
          year_min := 2010,
          year_max := 2024
     ))) AS statistical_history_drilldown;

\echo "Test yearly drilldown - enterprise - with all filters as bottom level"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          unit_type := 'enterprise'::public.statistical_unit_type,
          resolution := 'year'::public.history_resolution,
          year := 2019,
          region_path := '11.21'::public.ltree,
          activity_category_path := 'H.49.4.1.0'::public.ltree,
          sector_path := 'innl.a_ikke_fin.2100'::public.ltree,
          legal_form_id := (SELECT id FROM public.legal_form WHERE code = 'AS'),
          country_id := (SELECT id FROM public.country WHERE iso_2 = 'NO'),
          year_min := 2010,
          year_max := 2024
     ))) AS statistical_history_drilldown;


\echo "Test monthly drilldown"
SELECT jsonb_pretty(
     public.remove_ephemeral_data_from_hierarchy(
     public.statistical_history_drilldown(
          unit_type := 'enterprise'::public.statistical_unit_type,
          resolution := 'year-month'::public.history_resolution,
          year := 2019,
          region_path := NULL::public.ltree,
          activity_category_path := NULL::public.ltree,
          sector_path := NULL::public.ltree,
          legal_form_id := NULL::INTEGER,
          country_id := NULL::INTEGER,
          year_min := 2010,
          year_max := 2024
     ))) AS statistical_history_drilldown;

\echo "Test statistical_unit_hierarchy - For a date when it does not exist"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '823573673'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy(
                'enterprise',
                (SELECT unit_id FROM selected_enterprise),
                'all',
                '2013-01-01'::DATE
            )
          )
     ) AS statistical_unit_hierarchy;

\echo "Test statistical_unit_hierarchy - For a date when it does exist"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '823573673'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy(
                'enterprise',
                (SELECT unit_id FROM selected_enterprise),
                'all',
                '2010-01-01'::DATE
            )
          )
     ) AS statistical_unit_hierarchy;

WITH selected_legal_unit AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '921835809'
        AND unit_type = 'legal_unit'
    LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy('legal_unit',(SELECT unit_id FROM selected_legal_unit),'all')
          )
     ) AS statistical_unit_hierarchy;

WITH selected_establishment AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '895406732'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy('establishment',(SELECT unit_id FROM selected_establishment),'all')
          )
     ) AS statistical_unit_hierarchy;
\a

\x
\echo "Check relevant_statistical_units - no hit at that time."
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '823573673'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT valid_after
     , valid_from
     , valid_to
     , unit_type
     , external_idents
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
  FROM public.relevant_statistical_units(
     'enterprise',
     (SELECT unit_id FROM selected_enterprise),
     '2023-01-01'::DATE
);


\echo "Check relevant_statistical_units"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '921835809'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT valid_after
     , valid_from
     , valid_to
     , unit_type
     , external_idents
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
  FROM public.relevant_statistical_units(
     'enterprise',
     (SELECT unit_id FROM selected_enterprise),
     '2023-01-01'::DATE
);

\i test/rollback_unless_persist_is_specified.sql

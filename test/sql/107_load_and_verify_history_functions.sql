BEGIN;

\i test/setup.sql

\echo "Setting up Statbus to load establishments without legal units"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;

SELECT count(*) FROM public.activity_category_available;

SELECT count(*) FROM public.region;

SELECT count(*) FROM public.legal_form_available;

SELECT count(*) FROM public.sector_available;

-- SAVEPOINT before_loading_units; -- Removed to simplify transaction handling, aligning with other tests.

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units (Era)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_03_lu_era',
    'Import Legal Units Era (03_load_and_verify_history_functions.sql)',
    'Import job for legal units from test/data/03_norwegian-legal-units-over-time.csv using legal_unit_source_dates definition.',
    'Test data load (03_load_and_verify_history_functions.sql)';

\echo "User uploads the legal units over time (via import job: import_03_lu_era)"
\copy public.import_03_lu_era_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code,data_source_code) FROM 'test/data/03_norwegian-legal-units-over-time.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for legal units
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;


-- Create Import Job for Establishments (Era for LU)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_03_esflu_era',
    'Import Establishments Era for LU (03_load_and_verify_history_functions.sql)',
    'Import job for establishments from test/data/03_norwegian-establishments-over-time.csv using establishment_for_lu_source_dates definition.',
    'Test data load (03_load_and_verify_history_functions.sql)';

\echo "User uploads the establishments over time (via import job: import_03_esflu_era)"
\copy public.import_03_esflu_era_upload(valid_from, valid_to, tax_ident,legal_unit_tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,data_source_code,unit_size_code,employees,turnover) FROM 'test/data/03_norwegian-establishments-over-time.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for establishments
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;


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
    p_resolution := 'year'::public.history_resolution,
    p_valid_from := '2018-01-01'::DATE,
    p_valid_until := '2021-01-01'::DATE
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
    p_resolution := 'year'::public.history_resolution
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
    p_resolution := 'year'::public.history_resolution,
    p_valid_from := '2020-01-01'::DATE,
    p_valid_until := '2023-01-01'::DATE
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
    p_resolution := 'year-month'::public.history_resolution,
    p_valid_from := '2019-06-01'::DATE,
    p_valid_until := '2020-01-01'::DATE
)
ORDER BY year, month;


\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Inspecting import job data for import_03_lu_era (showing error rows first)"
(SELECT row_id, state, errors, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw, merge_status
FROM public.import_03_lu_era_data
WHERE state = 'error'
ORDER BY row_id)
UNION ALL
(SELECT row_id, state, errors, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw, merge_status
FROM public.import_03_lu_era_data
WHERE state != 'error'
ORDER BY row_id
LIMIT 5);

\echo "Checking import job status for import_03_lu_era"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_03_lu_era_data dr WHERE dr.state = 'error') AS error_rows,
       error
FROM public.import_job
WHERE slug = 'import_03_lu_era'
ORDER BY slug;

\echo "Inspecting import job data for import_03_esflu_era (showing error rows first)"
(SELECT row_id, state, errors, tax_ident_raw, legal_unit_tax_ident_raw, name_raw, valid_from_raw, valid_to_raw, merge_status
FROM public.import_03_esflu_era_data
WHERE state = 'error'
ORDER BY row_id)
UNION ALL
(SELECT row_id, state, errors, tax_ident_raw, legal_unit_tax_ident_raw, name_raw, valid_from_raw, valid_to_raw, merge_status
FROM public.import_03_esflu_era_data
WHERE state != 'error'
ORDER BY row_id
LIMIT 5);

\echo "Checking import job status for import_03_esflu_era"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_03_esflu_era_data dr WHERE dr.state = 'error') AS error_rows,
       error
FROM public.import_job
WHERE slug = 'import_03_esflu_era'
ORDER BY slug;

\echo "Checking statistical_history_periods from statistical_unit data"
SELECT * FROM public.get_statistical_history_periods()
-- Only list previous years, so the test is stable over time.
WHERE year <= 2023;


\echo "Checking timepoints."
WITH timepoints_with_tax_ident AS (
    SELECT tp.unit_type,
           tp.unit_id,
           tp.timepoint,
           -- For enterprises, the tax_ident is constant over its life. Find it once robustly.
           CASE
               WHEN tp.unit_type = 'enterprise' THEN
                   (SELECT tei.external_idents->>'tax_ident'
                    FROM public.enterprise_external_idents AS tei
                    WHERE tei.unit_id = tp.unit_id ORDER BY tei.valid_from LIMIT 1)
               ELSE
                   public.get_external_idents(tp.unit_type, tp.unit_id)->>'tax_ident'
           END AS tax_ident
    FROM public.timepoints AS tp
)
SELECT tpti.unit_type,
       tpti.tax_ident,
       tpti.timepoint
FROM timepoints_with_tax_ident AS tpti
ORDER BY tpti.unit_type, tpti.tax_ident, tpti.timepoint;

\echo "Checking timesegments."
WITH timesegments_with_tax_ident AS (
    SELECT ts.unit_type,
           ts.unit_id,
           ts.valid_from,
           ts.valid_until,
           -- For enterprises, the tax_ident is constant over its life. Find it once robustly.
           CASE
               WHEN ts.unit_type = 'enterprise' THEN
                   (SELECT tei.external_idents->>'tax_ident'
                    FROM public.enterprise_external_idents AS tei
                    WHERE tei.unit_id = ts.unit_id ORDER BY tei.valid_from LIMIT 1)
               ELSE
                   public.get_external_idents(ts.unit_type, ts.unit_id)->>'tax_ident'
           END AS tax_ident
    FROM public.timesegments AS ts
)
SELECT tsti.unit_type,
       tsti.tax_ident,
       tsti.valid_from,
       tsti.valid_until
FROM timesegments_with_tax_ident AS tsti
ORDER BY tsti.unit_type, tsti.tax_ident, tsti.valid_from;


\echo "Checking timesegments_years."
-- This test checks historical years derived from all loaded test data.
-- Years after 2025 are exlucded, to make the test deterministic as time passes.
SELECT year FROM public.timesegments_years
WHERE year <= 2025
ORDER BY year;


\echo "Checking timeline_establishment data"
WITH timeline_establishment_with_tax_ident AS (
    SELECT te.*,
           public.get_external_idents(te.unit_type, te.unit_id)->>'tax_ident' AS tax_ident
    FROM public.timeline_establishment AS te
)
SELECT tet.unit_type
     , tet.tax_ident
     , tet.valid_from
     , tet.valid_to
     , tet.valid_until
     , tet.name
     , tet.birth_date
     , tet.death_date
     , tet.search
     , tet.primary_activity_category_path
     , tet.secondary_activity_category_path
     , tet.activity_category_paths
     , tet.sector_path
     , tet.sector_code
     , tet.sector_name
     , tet.data_source_codes
     , tet.legal_form_code
     , tet.legal_form_name
     , tet.physical_address_part1
     , tet.physical_address_part2
     , tet.physical_address_part3
     , tet.physical_postcode
     , tet.physical_postplace
     , tet.physical_region_path
     , tet.physical_country_iso_2
     , tet.postal_address_part1
     , tet.postal_address_part2
     , tet.postal_address_part3
     , tet.postal_postcode
     , tet.postal_postplace
     , tet.postal_region_path
     , tet.postal_country_iso_2
FROM timeline_establishment_with_tax_ident AS tet
ORDER BY tet.unit_type, tet.tax_ident, tet.valid_from, tet.valid_until;


\echo "Checking timeline_establishment stats"
WITH timeline_establishment_stats_with_tax_ident AS (
    SELECT tes.*,
           public.get_external_idents(tes.unit_type, tes.unit_id)->>'tax_ident' AS tax_ident
    FROM public.timeline_establishment AS tes
)
SELECT unit_type
     , tax_ident
     , valid_from
     , valid_to
     , valid_until
     , stats
FROM timeline_establishment_stats_with_tax_ident
ORDER BY unit_type, tax_ident, valid_from, valid_until;

\echo "Checking timeline_legal_unit data"
WITH timeline_legal_unit_with_tax_ident AS (
    SELECT tlu.*,
           public.get_external_idents(tlu.unit_type, tlu.unit_id)->>'tax_ident' AS tax_ident
    FROM public.timeline_legal_unit AS tlu
)
SELECT tlut.unit_type
     , tlut.tax_ident
     , tlut.valid_from
     , tlut.valid_to
     , tlut.valid_until
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
     , tlut.postal_region_path
     , tlut.postal_country_iso_2
FROM timeline_legal_unit_with_tax_ident AS tlut
ORDER BY tlut.unit_type, tlut.tax_ident, tlut.valid_from, tlut.valid_until;


\x
\echo "Checking timeline_legal_unit stats"
WITH timeline_legal_unit_stats_with_tax_ident AS (
    SELECT tlus.*,
           public.get_external_idents(tlus.unit_type, tlus.unit_id)->>'tax_ident' AS tax_ident
    FROM public.timeline_legal_unit AS tlus
)
SELECT unit_type
     , tax_ident
     , valid_from
     , valid_to
     , valid_until
     , name
     , stats
     , jsonb_pretty(stats_summary) AS stats_summary
FROM timeline_legal_unit_stats_with_tax_ident
ORDER BY unit_type, tax_ident, valid_from, valid_until;
\x


\echo "Checking timeline_enterprise data"
WITH timeline_enterprise_with_tax_ident AS (
    SELECT te_base.*,
           eei.external_idents->>'tax_ident' AS tax_ident
    FROM public.timeline_enterprise AS te_base
    LEFT JOIN public.enterprise_external_idents AS eei
           ON eei.unit_type = te_base.unit_type
          AND eei.unit_id = te_base.unit_id
          AND daterange(eei.valid_from, eei.valid_until, '[)')
           && daterange(te_base.valid_from, te_base.valid_until, '[)')
)
SELECT te.unit_type
     , te.tax_ident
     , te.valid_from
     , te.valid_to
     , te.valid_until
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
FROM timeline_enterprise_with_tax_ident AS te
ORDER BY te.unit_type, te.tax_ident, te.valid_from, te.valid_until;


\x
\echo "Checking timeline_enterprise stats"
WITH timeline_enterprise_stats_with_tax_ident AS (
    SELECT tes_base.*,
           eei.external_idents->>'tax_ident' AS tax_ident
    FROM public.timeline_enterprise AS tes_base
    LEFT JOIN public.enterprise_external_idents AS eei
           ON eei.unit_type = tes_base.unit_type
          AND eei.unit_id = tes_base.unit_id
          AND daterange(eei.valid_from, eei.valid_until, '[)')
           && daterange(tes_base.valid_from, tes_base.valid_until, '[)')
)
SELECT unit_type
     , tax_ident
     , valid_from
     , valid_to
     , valid_until
     , name
     , jsonb_pretty(stats_summary) AS stats_summary
FROM timeline_enterprise_stats_with_tax_ident
ORDER BY unit_type, tax_ident, valid_from, valid_until;
\x


\x
\echo "Check statistical_unit"
WITH statistical_unit_ordered AS (
    SELECT su_base.*,
           su_base.external_idents->>'tax_ident' AS tax_ident_for_ordering
    FROM public.statistical_unit AS su_base
)
SELECT valid_from
     , valid_to
     , valid_until
     , unit_type
     , external_idents
     , jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
          to_jsonb(statistical_unit_ordered.*)
          -'stats'
          -'stats_summary'
          -'valid_from'
          -'valid_to'
          -'unit_type'
          -'external_idents'
          -'tax_ident_for_ordering'
          -'report_partition_seq'
          )
     ) AS statistical_unit_data
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
 FROM statistical_unit_ordered
 ORDER BY valid_from, valid_until, unit_type, tax_ident_for_ordering;

\echo "Checking statistical_unit totals"
SELECT unit_type
     , COUNT(DISTINCT unit_id) AS distinct_unit_count
     , jsonb_pretty(jsonb_stats_merge_agg(stats_summary)) AS stats_summary
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
     , exists_count
     , exists_change
     , exists_added_count
     , exists_removed_count
     , countable_count
     , countable_change
     , countable_added_count
     , countable_removed_count
FROM public.statistical_history
WHERE resolution = 'year'
  AND year <= 2024
ORDER BY year,unit_type;

SELECT year
     , unit_type
     , countable_count as count
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
     , exists_count
     , exists_change
     , exists_added_count
     , exists_removed_count
     , countable_count
     , countable_change
     , countable_added_count
     , countable_removed_count
FROM public.statistical_history
WHERE resolution = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

\echo "Test monthly data for 2019"
SELECT year, month
     , unit_type
     , countable_count AS count
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
     , exists_count
     , exists_change
     , exists_added_count
     , exists_removed_count
     , countable_count
     , countable_change
     , countable_added_count
     , countable_removed_count
FROM public.statistical_history_facet
WHERE resolution = 'year'
  AND year <= 2024
ORDER BY year,unit_type;

\echo "Test yearly facet data"
SELECT year
     , unit_type
     , primary_activity_category_path
     , secondary_activity_category_path
     , sector_path
     , physical_region_path
     , countable_count AS count
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
     , exists_count
     , exists_change
     , exists_added_count
     , exists_removed_count
     , countable_count
     , countable_change
     , countable_added_count
     , countable_removed_count
FROM public.statistical_history_facet
WHERE resolution = 'year-month' AND year = 2019
ORDER BY year,month,unit_type;

\echo "Test monthly facet data for 2019"
SELECT year, month
     , unit_type
     , primary_activity_category_path
     , secondary_activity_category_path
     , sector_path
     , physical_region_path
     , countable_count AS count
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
SELECT valid_from
     , valid_to
     , valid_until
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
SELECT valid_from
     , valid_to
     , valid_until
     , unit_type
     , external_idents
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
  FROM public.relevant_statistical_units(
     'enterprise',
     (SELECT unit_id FROM selected_enterprise),
     '2023-01-01'::DATE
);

\x
\echo "Test statistical_unit_history_highcharts"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '921835809'
       AND unit_type = 'enterprise'
     ORDER BY valid_from
     LIMIT 1
)
SELECT jsonb_pretty(
    public.remove_ephemeral_data_from_hierarchy(
        public.statistical_unit_history_highcharts(
            (SELECT unit_id FROM selected_enterprise),
            'enterprise'
        )
    )
) AS highcharts_history;
\x

\echo "Test public.statistical_history_highcharts - year resolution, enterprise"
SELECT jsonb_pretty(public.statistical_history_highcharts('year', 'enterprise'));

\echo "Test public.statistical_history_highcharts - year resolution, legal_unit"
SELECT jsonb_pretty(public.statistical_history_highcharts('year', 'legal_unit'));

\echo "Test public.statistical_history_highcharts - year resolution, establishment"
SELECT jsonb_pretty(public.statistical_history_highcharts('year', 'establishment'));

\echo "Test public.statistical_history_highcharts - year-month resolution for 2019, enterprise"
SELECT jsonb_pretty(public.statistical_history_highcharts('year-month', 'enterprise', 2019));

\echo "Test public.statistical_history_highcharts - year-month resolution for 2019, legal_unit"
SELECT jsonb_pretty(public.statistical_history_highcharts('year-month', 'legal_unit', 2019));

\echo "Test public.statistical_history_highcharts - year-month resolution for 2019, establishment"
SELECT jsonb_pretty(public.statistical_history_highcharts('year-month', 'establishment', 2019));

\echo "Test public.statistical_history_highcharts - no data case (enterprise_group)"
SELECT jsonb_pretty(public.statistical_history_highcharts('year', 'enterprise_group'));

\echo "Test public.statistical_history_highcharts - with custom series filter"
SELECT jsonb_pretty(public.statistical_history_highcharts(
    p_resolution => 'year',
    p_unit_type => 'enterprise',
    p_series_codes => ARRAY['countable_count', 'deaths']
));

\echo "Test public.statistical_history_highcharts - with empty series filter (should use default)"
SELECT jsonb_pretty(public.statistical_history_highcharts(
    p_resolution => 'year',
    p_unit_type => 'enterprise',
    p_series_codes => ARRAY[]::text[]
));

\echo "Test public.statistical_history_highcharts - with all series specified"
SELECT jsonb_pretty(public.statistical_history_highcharts(
    p_resolution => 'year',
    p_unit_type => 'enterprise',
    p_series_codes => ARRAY[
        'countable_count',
        'countable_change',
        'countable_added_count',
        'countable_removed_count',
        'exists_count',
        'exists_change',
        'exists_added_count',
        'exists_removed_count',
        'births',
        'deaths',
        'name_change_count',
        'primary_activity_category_change_count',
        'secondary_activity_category_change_count',
        'sector_change_count',
        'legal_form_change_count',
        'physical_region_change_count',
        'physical_country_change_count',
        'physical_address_change_count'
    ]
));

\echo "Test public.statistical_history_highcharts - with an invalid series code"
SELECT jsonb_pretty(public.statistical_history_highcharts(
    p_resolution => 'year',
    p_unit_type => 'enterprise',
    p_series_codes => ARRAY['countable_count', 'invalid_code', 'deaths']
));

\i test/rollback_unless_persist_is_specified.sql

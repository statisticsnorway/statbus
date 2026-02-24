BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/demo/getting-started.sql

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'), -- Corrected slug
    'import_34_lu_era',
    'Import LU Era (34_hierarchy_functions.sql)',
    'Import job for test/data/34_legal_units.csv.',
    'Test data load (34_hierarchy_functions.sql)';
\echo "User uploads legal units (via import job: import_34_lu_era)"
\copy public.import_34_lu_era_upload(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,physical_latitude,physical_longitude,physical_altitude,web_address,email_address,phone_number) FROM 'test/data/34_legal_units.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Formal Establishments
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'), -- Corrected slug
    'import_34_esflu_era',
    'Import Formal ES Era (34_hierarchy_functions.sql)',
    'Import job for test/data/34_formal_establishments.csv.',
    'Test data load (34_hierarchy_functions.sql)';
\echo "User uploads formal establishments (via import job: import_34_esflu_era)"
\copy public.import_34_esflu_era_upload(valid_from,valid_to,tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_latitude,physical_longitude,physical_altitude,web_address,email_address,landline) FROM 'test/data/34_formal_establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Informal Establishments
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates'), -- Corrected slug
    'import_34_eswlu_era',
    'Import Informal ES Era (34_hierarchy_functions.sql)',
    'Import job for test/data/34_informal_establishments.csv.',
    'Test data load (34_hierarchy_functions.sql)';
\echo "User uploads informal establishments (via import job: import_34_eswlu_era)"
\copy public.import_34_eswlu_era_upload(valid_from,valid_to,tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code,physical_latitude,physical_longitude,physical_altitude,web_address,email_address,phone_number) FROM 'test/data/34_informal_establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error
FROM public.import_job
WHERE slug LIKE 'import_34_%' ORDER BY slug;

\echo "Checking for data processing issues in import_34_lu_era_data"
SELECT row_id, errors, invalid_codes, merge_status FROM public.import_34_lu_era_data WHERE errors IS NOT NULL OR invalid_codes IS NOT NULL ORDER BY row_id;

\echo "Checking for data processing issues in import_34_esflu_era_data"
SELECT row_id, errors, invalid_codes, merge_status FROM public.import_34_esflu_era_data WHERE errors IS NOT NULL OR invalid_codes IS NOT NULL ORDER BY row_id;

\echo "Checking for data processing issues in import_34_eswlu_era_data"
SELECT row_id, errors, invalid_codes, merge_status FROM public.import_34_eswlu_era_data WHERE errors IS NOT NULL OR invalid_codes IS NOT NULL ORDER BY row_id;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Checking stats in stat_for_unit"
SELECT
    su.unit_type,
    su.name,
    sd.code AS stat_code,
    sfu.stat,
    sfu.valid_from,
    sfu.valid_to
FROM public.stat_for_unit AS sfu
JOIN public.statistical_unit AS su ON
    (sfu.establishment_id = su.unit_id AND su.unit_type = 'establishment') OR
    (sfu.legal_unit_id = su.unit_id AND su.unit_type = 'legal_unit')
JOIN public.stat_definition AS sd ON sfu.stat_definition_id = sd.id
ORDER BY su.unit_type, su.name, sd.code;

\echo "Checking aggregated stats in statistical_unit"
SELECT unit_type, count(*) AS units_with_stats
FROM public.statistical_unit
WHERE stats_summary IS NOT NULL AND stats_summary != '{}'::jsonb
GROUP BY unit_type
ORDER BY unit_type;
    
SELECT unit_type, name, external_idents
FROM statistical_unit ORDER BY unit_type,name;


\echo "Test statistical_unit_hierarchy - for Nile Pearl Water"
WITH selected_legal_unit AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '1000'
       AND unit_type = 'legal_unit'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy(
                'legal_unit',
                (SELECT unit_id FROM selected_legal_unit),
                'all',
                '2024-01-01'::DATE
            )
          )
     ) AS statistical_unit_hierarchy;


\echo "Test statistical_unit_hierarchy - THE MARINE SERVICES"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '3001'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy(
                'enterprise',
                (SELECT unit_id FROM selected_enterprise),
                'all',
                '2024-01-01'::DATE
            )
          )
     ) AS statistical_unit_hierarchy;


\echo "Test statistical_unit_tree - for Nile Pearl Water"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '1000'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_tree(
                'enterprise',
                (SELECT unit_id FROM selected_enterprise),
                '2024-01-01'::DATE
            )
          )
     ) AS statistical_unit_tree;

\echo "Test statistical_unit_details - for Nile Pearl Water"
WITH selected_legal_unit AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '1000'
       AND unit_type = 'legal_unit'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_details(
                'legal_unit',
                (SELECT unit_id FROM selected_legal_unit),
                '2024-01-01'::DATE
            )
          )
     ) AS statistical_unit_details;

\x
\echo "Test statistical_unit_stats - for Nile Pearl Water"
WITH selected_legal_unit AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '1000'
       AND unit_type = 'legal_unit'
     LIMIT 1
)
SELECT unit_type, jsonb_pretty(stats), jsonb_pretty(stats_summary)
FROM public.statistical_unit_stats(
        'legal_unit',
        (SELECT unit_id FROM selected_legal_unit),
        '2024-01-01'::DATE
    );

\echo "Test statistical_unit_stats - for THE MARINE SERVICES"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '3001'
       AND unit_type = 'enterprise'
     LIMIT 1
)
SELECT unit_type, jsonb_pretty(stats), jsonb_pretty(stats_summary)
FROM public.statistical_unit_stats(
        'enterprise',
        (SELECT unit_id FROM selected_enterprise),
        '2024-01-01'::DATE
    );
\x

-- ============================================================================
-- BENCHMARK: Write EXPLAIN ANALYZE output to perf file (variable timing, not diff-checked)
-- ============================================================================
-- Capture unit_ids into psql variables for use in EXPLAIN ANALYZE
SELECT unit_id AS lu_unit_id FROM public.statistical_unit
WHERE external_idents ->> 'stat_ident' = '1000'
  AND unit_type = 'legal_unit'
LIMIT 1 \gset

SELECT unit_id AS ent_unit_id FROM public.statistical_unit
WHERE external_idents ->> 'stat_ident' = '3001'
  AND unit_type = 'enterprise'
LIMIT 1 \gset

\set perf_file test/expected/performance/109_hierarchy_functions.perf
\pset tuples_only on
\pset footer off
\o :perf_file

SELECT '# Benchmark: statistical_unit_stats and relevant_statistical_units';
SELECT '# Date: ' || now()::text;
SELECT '';

SELECT '## EXPLAIN ANALYZE: statistical_unit_stats (legal_unit, stat_ident=1000)';
\pset tuples_only off
EXPLAIN ANALYZE
SELECT * FROM public.statistical_unit_stats('legal_unit', :lu_unit_id, '2024-01-01'::DATE);

\pset tuples_only on
SELECT '';
SELECT '## EXPLAIN ANALYZE: statistical_unit_stats (enterprise, stat_ident=3001)';
\pset tuples_only off
EXPLAIN ANALYZE
SELECT * FROM public.statistical_unit_stats('enterprise', :ent_unit_id, '2024-01-01'::DATE);

\pset tuples_only on
SELECT '';
SELECT '## EXPLAIN ANALYZE: relevant_statistical_units (legal_unit, stat_ident=1000)';
\pset tuples_only off
EXPLAIN ANALYZE
SELECT * FROM public.relevant_statistical_units('legal_unit', :lu_unit_id, '2024-01-01'::DATE);

\pset tuples_only on
SELECT '';
SELECT '## EXPLAIN ANALYZE: relevant_statistical_units (enterprise, stat_ident=3001)';
\pset tuples_only off
EXPLAIN ANALYZE
SELECT * FROM public.relevant_statistical_units('enterprise', :ent_unit_id, '2024-01-01'::DATE);

\o
\pset tuples_only off
\pset footer on

ROLLBACK;

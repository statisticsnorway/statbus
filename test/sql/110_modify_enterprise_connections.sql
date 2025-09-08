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

\echo "Available import definitions before creating jobs:"
SELECT slug, name, valid, validation_error FROM public.import_definition ORDER BY slug;

-- Create Import Job for Legal Units (Era)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT 
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'), 
    'import_05_lu_era',
    'Import Legal Units Era (05_modify_enterprise_connections.sql)',
    'Import job for legal units from test/data/05_norwegian-legal-units.csv using legal_unit_source_dates definition.',
       'Test data load (05_modify_enterprise_connections.sql)';

\echo "User uploads the legal units (via import job: import_05_lu_era)"
\copy public.import_05_lu_era_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/05_norwegian-legal-units.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Establishments (Era for LU)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT 
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'), 
    'import_05_esflu_era',
    'Import Establishments Era for LU (05_modify_enterprise_connections.sql)',
    'Import job for establishments from test/data/05_norwegian-establishments.csv using establishment_for_lu_source_dates definition.',
    'Test data load (05_modify_enterprise_connections.sql)';

\echo "User uploads the establishments (via import job: import_05_esflu_era)"
\copy public.import_05_esflu_era_upload(valid_from, valid_to, tax_ident,legal_unit_tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover) FROM 'test/data/05_norwegian-establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking unit counts after import processing"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Inspecting import job data for import_05_lu_era"
SELECT row_id, state, errors, tax_ident, name, valid_from, valid_to, merge_statuses
FROM public.import_05_lu_era_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_05_lu_era"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_05_lu_era_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_05_lu_era'
ORDER BY slug;

\echo "Inspecting import job data for import_05_esflu_era"
SELECT row_id, state, errors, tax_ident, legal_unit_tax_ident, name, valid_from, valid_to, merge_statuses
FROM public.import_05_esflu_era_data
ORDER BY row_id
LIMIT 5;

\echo "Checking import job status for import_05_esflu_era"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error,
       (SELECT COUNT(*) FROM public.import_05_esflu_era_data dr WHERE dr.state = 'error') AS error_rows
FROM public.import_job
WHERE slug = 'import_05_esflu_era'
ORDER BY slug;

\echo "Test statistical_unit_hierarchy - for Kranløft Vestland"
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


\echo "Test statistical_unit_hierarchy - for Kranløft Østland"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '921835809'
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

SELECT count(*) FROM public.enterprise;


\echo "Connect - Kranløft Østland - to Kranløft Vestland"
WITH vest_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '823573673'
       AND unit_type = 'enterprise'
     LIMIT 1
), ost_legal_unit AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '921835809'
       AND unit_type = 'legal_unit'
     LIMIT 1
)
SELECT
  public.remove_ephemeral_data_from_hierarchy(
    connect_legal_unit_to_enterprise(ost_legal_unit.unit_id, vest_enterprise.unit_id, '2010-01-01'::date, 'infinity'::date)
  )
FROM vest_enterprise
   , ost_legal_unit;

\echo "Again - Kranløft Østland - to Kranløft Vestland - should be idempotent."
WITH vest_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '823573673'
       AND unit_type = 'enterprise'
     LIMIT 1
), ost_legal_unit AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '921835809'
       AND unit_type = 'legal_unit'
     LIMIT 1
)
SELECT connect_legal_unit_to_enterprise(ost_legal_unit.unit_id, vest_enterprise.unit_id, '2010-01-01'::date, 'infinity'::date)
     - 'enterprise_id'
     - 'legal_unit_id'
FROM vest_enterprise
   , ost_legal_unit;

\echo "Kranløft Vestland - should already be primary"
WITH vest_legal_unit AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '823573673'
       AND unit_type = 'legal_unit'
     LIMIT 1
)
SELECT set_primary_legal_unit_for_enterprise(vest_legal_unit.unit_id, '2010-01-01'::date, 'infinity'::date)
     - 'enterprise_id'
     - 'legal_unit_id'
  FROM vest_legal_unit;


\echo "Kranløft Oslo - is primary for - Kranløft Østland"
WITH oslo_establishment AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '595875335'
       AND unit_type = 'establishment'
     LIMIT 1
)
SELECT
      public.remove_ephemeral_data_from_hierarchy(
         set_primary_establishment_for_legal_unit(oslo_establishment.unit_id, '2010-01-01'::date, 'infinity'::date)
      )
  FROM oslo_establishment;

\echo "Kranløft Oslo - is primary for - Kranløft Østland - idempotent"
WITH oslo_establishment AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '595875335'
       AND unit_type = 'establishment'
     LIMIT 1
)
SELECT public.remove_ephemeral_data_from_hierarchy(
        set_primary_establishment_for_legal_unit(oslo_establishment.unit_id, '2010-01-01'::date, 'infinity'::date)
  )
  FROM oslo_establishment;

SELECT count(*) FROM public.enterprise;

\echo "Test statistical_unit_hierarchy - for Kranløft Vestland - Also contain Østland"
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


\echo "Test statistical_unit_hierarchy - for Kranløft Østland - Contains nothing"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'tax_ident' = '921835809'
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


  \echo Run worker processing for analytics tasks (after manual connections)
  CALL worker.process_tasks(p_queue => 'analytics');
  SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\x
\echo "Check relevant_statistical_units"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE unit_type = 'enterprise'
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


ROLLBACK;

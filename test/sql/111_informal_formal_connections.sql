BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id,only_one_setting)
SELECT id, true FROM activity_category_standard WHERE code = 'isic_v4'
ON CONFLICT (only_one_setting)
DO UPDATE SET
   activity_category_standard_id =(SELECT id FROM activity_category_standard WHERE code = 'isic_v4')
   WHERE settings.id = EXCLUDED.id;
;

\echo "User uploads the sample activity categories"
\copy public.activity_category_available_custom(path,name) FROM 'app/public/demo/activity_custom_isic_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the sample regions"
\copy public.region_upload(path, name) FROM 'app/public/demo/regions_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the sample legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'app/public/demo/legal_forms_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'app/public/demo/sectors_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);



SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

-- Create Import Job for Legal Units
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_33_lu_era',
    'Import LU Era (33_informal_formal_connections.sql)',
    'Import job for test/data/31_legal_units.csv.',
    'Test data load (33_informal_formal_connections.sql)';
\echo "User uploads legal units (via import job: import_33_lu_era)"
INSERT INTO public.import_33_lu_era_upload(valid_from, valid_to, tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) VALUES
('2024-01-01','infinity','2212760144','1000','NILE PEARL WATER','01.10.2016','225613','UG','4752','4','6100',2,9000000,'nlr'),
('2024-01-01','infinity','2812760140','1001','EQUATOR GLOBE SOLUTIONS','01.10.2016','225602','UG','5610','1','6100',2,2400000,'nlr');

-- Create Import Job for Formal Establishments
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_33_esflu_era',
    'Import Formal ES Era (33_informal_formal_connections.sql)',
    'Import job for test/data/31_formal_establishments.csv.',
    'Test data load (33_informal_formal_connections.sql)';
\echo "User uploads formal establishments (via import job: import_33_esflu_era)"
INSERT INTO public.import_33_esflu_era_upload(valid_from, valid_to, tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) VALUES
('2024-01-01','infinity','92212760144','2000','NILE PEARL WATER','225613','UG','4752',0,0,'2212760144','nlr'),
('2024-01-01','infinity','92812760140','2001','EQUATOR GLOBE SOLUTIONS','225602','UG','5610',0,0,'2812760140','nlr');

-- Create Import Job for Informal Establishments
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates'),
    'import_33_eswlu_era',
    'Import Informal ES Era (33_informal_formal_connections.sql)',
    'Import job for test/data/33_informal_establishments.csv.',
    'Test data load (33_informal_formal_connections.sql)';
\echo "User uploads informal establishments (via import job: import_33_eswlu_era)"
INSERT INTO public.import_33_eswlu_era_upload(valid_from,valid_to,tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) VALUES
('2024-01-01','infinity','82212760144','3000','THE INFORMAL NILE PEARL WATER','225613','UG','4752',1,1200,'nlr'),
('2024-01-01','infinity','82812760140','3001','THE EQUATOR GLOBE SOLUTIONS','225602','UG','5610',2,4400,'nlr');

SAVEPOINT after_loading_units;

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error
FROM public.import_job
WHERE slug LIKE 'import_33_%' ORDER BY slug;

\echo Run worker processing for initial analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

SELECT unit_type, name, external_idents
FROM statistical_unit ORDER BY unit_type,name;


\echo "Test statistical_unit_hierarchy - for Nile Pearl Water"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '1000'
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


\echo "Test statistical_unit_hierarchy - for The Equator Globe Solutions"
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

SELECT count(*) FROM public.enterprise;


\echo "Connect - Nile Pearl Water - to The Equator Globe Solutions"
WITH equator_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '3001'
       AND unit_type = 'enterprise'
     LIMIT 1
), nile_legal_unit AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '1000'
       AND unit_type = 'legal_unit'
     LIMIT 1
)
SELECT
  public.remove_ephemeral_data_from_hierarchy(
    connect_legal_unit_to_enterprise(nile_legal_unit.unit_id, equator_enterprise.unit_id)
  )
FROM equator_enterprise
   , nile_legal_unit;

\echo Run worker processing for analytics tasks (after import and manual connection)
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

SELECT unit_type, name, external_idents
FROM statistical_unit ORDER BY unit_type,name;

\echo "Test statistical_unit_hierarchy after"

\echo "Test statistical_unit_hierarchy - for Nile Pearl Water (enterprise) - contains nothing"
WITH selected_enterprise AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '1000'
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

\echo "Test statistical_unit_hierarchy - for Nile Pearl Water (legal unit)"
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

\echo "Test statistical_unit_hierarchy - for The Equator Globe Solutions (informal establishment)"
WITH selected_establishment AS (
     SELECT unit_id FROM public.statistical_unit
     WHERE external_idents ->> 'stat_ident' = '3001'
       AND unit_type = 'establishment'
     LIMIT 1
)
SELECT jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
               public.statistical_unit_hierarchy(
                'establishment',
                (SELECT unit_id FROM selected_establishment),
                'all',
                '2024-01-01'::DATE
            )
          )
     ) AS statistical_unit_hierarchy;

\echo "Test statistical_unit_hierarchy - for The Equator Globe Solutions (enterprise)"
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

ROLLBACK;

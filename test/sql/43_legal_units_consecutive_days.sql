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

SAVEPOINT before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads the legal units over time"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-1.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;


\echo "User uploads the legal units over time"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-4.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo Run worker processing to run import jobs and generate computed data
CALL worker.process_tasks();
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;


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
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_region_path
     , physical_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;


\echo "User uploads the legal units over time"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-3.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;


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
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_region_path
     , physical_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;


ROLLBACK TO before_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "User uploads the legal units over time"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-1.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;


\echo "User uploads the legal units over time"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-3.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;


\echo Run worker processing to run import jobs and generate computed data
CALL worker.process_tasks();
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;


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
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_region_path
     , physical_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;


\echo "User uploads the legal units over time"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/43_legal-units-day-4.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;


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
     , activity_category_paths
     , sector_path
     , sector_code
     , sector_name
     , data_source_codes
     , legal_form_code
     , legal_form_name
     , physical_region_path
     , physical_country_iso_2
     , invalid_codes
FROM public.timeline_legal_unit
ORDER BY unit_type, unit_id, valid_after, valid_to;



ROLLBACK;

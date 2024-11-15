BEGIN;
\echo "Setting up Statbus using the web provided examples"
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


\echo "User uploads legal units"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'test/data/31_legal_units.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
\echo "User uploads formal establishments"
\copy public.import_establishment_era_for_legal_unit(valid_from,valid_to,tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'test/data/31_formal_establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
\echo "User uploads informal establishments"
\copy public.import_establishment_era_without_legal_unit(valid_from,valid_to,tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) FROM 'test/data/33_informal_establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SAVEPOINT after_loading_units;

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();

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

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();

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
                '2024-01-01'::DATE
            )
          )
     ) AS statistical_unit_hierarchy;

ROLLBACK;
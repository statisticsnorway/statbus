SET datestyle TO 'ISO, DMY';

BEGIN;

\echo "Setting up Statbus to test enterprise grouping and primary"

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

\echo "User uploads the legal units"
\copy public.import_legal_unit_era(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postal_code,physical_postal_place,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postal_code,postal_postal_place,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/05_norwegian-legal-units.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the establishments"
\copy public.import_establishment_era_for_legal_unit(valid_from, valid_to, tax_ident,legal_unit_tax_ident,name,birth_date,death_date,physical_address_part1,physical_postal_code,physical_postal_place,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postal_code,postal_postal_place,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover) FROM 'test/data/05_norwegian-establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();


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
                '2010-01-01'::DATE
            )
          )
     ) AS statistical_unit_hierarchy;


\echo "Refreshing materialized views"
-- Exclude the refresh_time_ms as it will vary.
SELECT view_name FROM statistical_unit_refresh_now();

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

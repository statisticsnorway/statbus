-- STATBUS-513: each Reports chart series has exactly one point per period, the
-- period's total. statistical_history holds the total (hash_partition IS NULL)
-- next to per-partition slots that build it (see the column comment). The
-- chart runs as the caller, and the row level security policies show an
-- application role only the totals.
--
-- Fixture: the demo units with source dates (the dev dataset's shape), which
-- spread over several hash partitions.
BEGIN;

\i test/setup.sql

\echo "Test 354 (STATBUS-513): Units-over-time chart has one point per period, the total"

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_513_lu', 'Test 354 demo legal units with source dates', 'Test 354 (STATBUS-513)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
\copy public.import_513_lu_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_513_es', 'Test 354 demo formal establishments with source dates', 'Test 354 (STATBUS-513)', false
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
\copy public.import_513_es_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,physical_latitude,physical_longitude,physical_altitude,birth_date,unit_size_code,status_code) FROM 'app/public/demo/formal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo "354.1 an application role sees one total row per period and unit type"
SELECT resolution, hash_partition IS NULL AS is_total, count(*) AS rows
FROM public.statistical_history
GROUP BY 1, 2 ORDER BY 1, 2;

\echo "354.2 every chart point equals its period's total row, one point per period"
WITH totals AS (
    SELECT unit_type, year, countable_count
    FROM public.statistical_history
    WHERE resolution = 'year' AND hash_partition IS NULL
), chart AS (
    SELECT t.unit_type,
           extract(year FROM to_timestamp((p ->> 0)::bigint / 1000) AT TIME ZONE 'UTC')::int AS year,
           (p ->> 1)::int AS value
    FROM (VALUES ('establishment'::public.statistical_unit_type), ('legal_unit'), ('enterprise')) AS t(unit_type),
         jsonb_array_elements(public.statistical_history_highcharts('year', t.unit_type, NULL, ARRAY['countable_count']) -> 'series') AS s,
         jsonb_array_elements(s -> 'data') AS p
)
SELECT c.unit_type, c.year, count(*) AS points, min(c.value) AS chart_value, max(tt.countable_count) AS total
FROM chart AS c
LEFT JOIN totals AS tt ON tt.unit_type = c.unit_type AND tt.year = c.year
WHERE c.year IN (2023, 2024)
GROUP BY 1, 2
ORDER BY 1, 2;

ROLLBACK;

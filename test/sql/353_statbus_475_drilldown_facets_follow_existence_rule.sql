-- STATBUS-475: the Reports drilldown counts units that EXIST at the selected
-- instant, by the canonical existence rule of STATBUS-460, so it agrees with
-- the dashboard cards and the Units-over-time chart bar for bar.
--
-- Same fixture as test 351 (the STATBUS-458 demo rows): an establishment
-- record window that opens 2023-01-01 with birth_date 2024-11-01 must not be
-- counted in 2023, and a legal unit that dies inside its record window must
-- not be counted after its death.
BEGIN;

\i test/setup.sql

\echo "Test 353 (STATBUS-475): Reports drilldown facets follow the unit existence rule"

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_475_lu', 'Test 353 demo legal units with source dates', 'Test 353 (STATBUS-475)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
\copy public.import_475_lu_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_475_es', 'Test 353 demo formal establishments with source dates', 'Test 353 (STATBUS-475)', false
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
\copy public.import_475_es_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,physical_latitude,physical_longitude,physical_altitude,birth_date,unit_size_code,status_code) FROM 'app/public/demo/formal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_475_life', 'Test 353 death inside the record window', 'Test 353 (STATBUS-475)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_475_life_upload(valid_from, valid_to, tax_ident, name, birth_date, death_date, physical_region_code) VALUES
    ('2023-01-01', 'infinity', '475000002', 'Dies inside its window', '2020-05-01', '2024-06-30', '225613');

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo "353.0 jobs finished"
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug LIKE 'import_475_%' ORDER BY slug;

-- The Reports drilldown total for one unit type at one instant (the number
-- the drilldown page shows), next to the chart's countable_count.
CREATE TEMP VIEW drilldown_vs_chart AS
SELECT i.d, t.unit_type,
       (public.statistical_unit_facet_drilldown(unit_type => t.unit_type, valid_on => i.d)->'stats'->>'count')::int AS drilldown_count,
       h.countable_count AS chart_count
FROM (VALUES ('2023-12-31'::date), ('2024-12-31'::date)) AS i(d)
CROSS JOIN (VALUES ('enterprise'::public.statistical_unit_type), ('legal_unit'), ('establishment')) AS t(unit_type)
LEFT JOIN public.statistical_history AS h
  ON h.resolution = 'year' AND h.hash_partition IS NULL
 AND make_date(h.year, 12, 31) = i.d AND h.unit_type = t.unit_type;

\echo
\echo "353.1 the drilldown total equals the Units-over-time chart bar for bar"
SELECT d, unit_type, drilldown_count, chart_count, drilldown_count = chart_count AS drilldown_matches_chart
FROM drilldown_vs_chart
ORDER BY 1, array_position(ARRAY['enterprise','legal_unit','establishment']::public.statistical_unit_type[], unit_type);

\echo
\echo "353.2 every drilldown breakdown sums to the same total (region, activity category, sector, status, legal form, country)"
WITH dd AS (
    SELECT i.d, t.unit_type,
           public.statistical_unit_facet_drilldown(unit_type => t.unit_type, valid_on => i.d) AS j
    FROM (VALUES ('2023-12-31'::date), ('2024-12-31'::date)) AS i(d)
    CROSS JOIN (VALUES ('legal_unit'::public.statistical_unit_type), ('establishment')) AS t(unit_type)
)
SELECT dd.d, dd.unit_type, dim.dimension,
       (dd.j->'stats'->>'count')::int AS total,
       COALESCE((SELECT sum((e->>'count')::int) FROM jsonb_array_elements(dd.j->'available'->dim.dimension) AS e), 0) AS breakdown_sum
FROM dd
CROSS JOIN (VALUES ('region'), ('status'), ('country')) AS dim(dimension)
ORDER BY 1, 2, 3;

\echo
\echo "353.3 Statistics Denmark ES (window 2023-01-01..infinity, born 2024-11-01) is in the drilldown only from birth"
SELECT i.d,
       (public.statistical_unit_facet_drilldown(unit_type => 'establishment', region_path => r.path, valid_on => i.d)->'stats'->>'count')::int AS establishments_in_its_region
FROM (VALUES ('2023-12-31'::date), ('2024-10-31'::date), ('2024-11-01'::date)) AS i(d)
CROSS JOIN LATERAL (SELECT su.physical_region_path AS path FROM public.statistical_unit AS su
                    WHERE su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = '945000' LIMIT 1) AS r
ORDER BY i.d;

\echo
\echo "353.4 a death inside the record window ends the unit's presence in the drilldown"
SELECT i.d,
       (public.statistical_unit_facet_drilldown(unit_type => 'legal_unit', region_path => r.path, valid_on => i.d)->'stats'->>'count')::int AS legal_units_in_its_region
FROM (VALUES ('2024-06-29'::date), ('2024-06-30'::date)) AS i(d)
CROSS JOIN LATERAL (SELECT su.physical_region_path AS path FROM public.statistical_unit AS su
                    WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = '475000002' LIMIT 1) AS r
ORDER BY i.d;

ROLLBACK;

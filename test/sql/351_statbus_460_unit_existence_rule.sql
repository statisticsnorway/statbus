-- STATBUS-460: every "how many units exist" screen uses ONE canonical existence rule.
--
-- A unit EXISTS at instant d iff
--     COALESCE(birth_date, valid_from) <= d
-- AND (death_date IS NULL OR death_date > d)
-- AND valid_until > d
-- for the record whose validity window covers d (at most one per unit, by the
-- temporal primary key). Implemented once as public.unit_existence_from/until and
-- exposed to PostgREST as the computed fields public.existence_from(<row>) and
-- public.existence_until(<row>): exists at d iff existence_from <= d < existence_until.
--
-- Worked example: STATBUS-458 on dev. The committed demo file
-- app/public/demo/formal_establishments_units_with_source_dates_demo.csv pairs a
-- 2023 snapshot window (valid_from 2023-01-01, valid_to infinity) with
-- birth_date 01.11.2024 for 13 establishments (Statistics Denmark, Statistics
-- Finland, ...). The dashboard cards counted RECORDS covering the instant
-- (valid_from <= d AND valid_to >= d) and showed them in 2023, while the Reports
-- Units-over-time chart (statistical_history, existence rule) did not.
--
-- This test loads the same two demo files dev loaded (legal units + formal
-- establishments, source dates; STATBUS-461 has since corrected Drill Down/Up
-- Norway AS to birth 2023-11-01 and its gate rejects one row), then asserts per
-- instant that the dashboard card query, the chart and the unit detail function
-- agree, and that birth and death dates bound existence inside a record window.
BEGIN;

\i test/setup.sql

\echo "Test 351 (STATBUS-460): one canonical unit existence rule for every count"

CALL test.set_user_from_email('test.admin@statbus.org');

-- Suppress the verbatim echo of the shared include (STATBUS-175 pattern).
\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_460_lu', 'Test 351 demo legal units with source dates', 'Test 351 (STATBUS-460)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
\copy public.import_460_lu_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_460_es', 'Test 351 demo formal establishments with source dates', 'Test 351 (STATBUS-460)', false
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
\copy public.import_460_es_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,physical_latitude,physical_longitude,physical_altitude,birth_date,unit_size_code,status_code) FROM 'app/public/demo/formal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo "351.0 both demo jobs finished"
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug LIKE 'import_460_%' ORDER BY slug;

\echo
\echo "351.1 the 458 rows as recorded in statistical_unit, with their existence window:"
\echo "       Statistics Denmark ES 945000 (window 2023-01-01..infinity, born 2024-11-01) and"
\echo "       Drill Down/Up Norway AS ES 947111113 (two windows, born 2023-11-01 since STATBUS-461 fixed the demo file)"
SELECT su.external_idents->>'tax_ident' AS tax_ident, su.name, su.valid_from, su.valid_to, su.birth_date, su.death_date,
       public.existence_from(su) AS existence_from, public.existence_until(su) AS existence_until
FROM public.statistical_unit AS su
WHERE su.unit_type = 'establishment'
  AND su.external_idents->>'tax_ident' IN ('945000', '947111113')
ORDER BY tax_ident, su.valid_from;

-- The dashboard card query, exactly as StatisticalUnitCountCard sends it to
-- PostgREST: /rest/statistical_unit?unit_type=eq.X&existence_from=lte.d
-- &existence_until=gt.d&used_for_counting=is.true. used_for_counting is what the
-- chart's countable_count adds on top of existence, so the two are the same count.
CREATE TEMP VIEW card AS
SELECT i.d, su.unit_type, count(*) AS card_count, count(DISTINCT su.unit_id) AS distinct_units
FROM (VALUES ('2023-12-31'::date), ('2024-12-31'::date)) AS i(d)
JOIN public.statistical_unit AS su
  ON public.existence_from(su) <= i.d AND i.d < public.existence_until(su) AND su.used_for_counting
GROUP BY i.d, su.unit_type;

\echo
\echo "351.2 the dashboard card equals the Reports Units-over-time chart bar for bar, one row per unit"
SELECT c.d, c.unit_type, c.card_count, h.countable_count AS chart_count,
       c.card_count = h.countable_count AS card_matches_chart,
       c.card_count = c.distinct_units AS one_record_per_unit
FROM card AS c
FULL JOIN (SELECT * FROM public.statistical_history
            WHERE resolution = 'year' AND year IN (2023, 2024) AND hash_partition IS NULL) AS h
  ON make_date(h.year, 12, 31) = c.d AND h.unit_type = c.unit_type
ORDER BY 1, array_position(ARRAY['enterprise','legal_unit','establishment']::public.statistical_unit_type[], c.unit_type);

\echo
\echo "351.3 a unit born after its record window starts does not exist before birth:"
\echo "       Statistics Denmark ES (valid_from 2023-01-01, valid_to infinity, birth 2024-11-01)"
\echo "       is absent from the 2023 list and detail page, present from its birth day"
WITH instant(d) AS (VALUES ('2023-12-31'::date), ('2024-10-31'::date), ('2024-11-01'::date), ('2024-12-31'::date))
SELECT i.d,
       EXISTS (SELECT 1 FROM public.statistical_unit AS su
               WHERE su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = '945000'
                 AND public.existence_from(su) <= i.d AND i.d < public.existence_until(su)) AS in_list,
       public.statistical_unit_details('establishment', es.id, i.d) ? 'establishment' AS on_detail_page
FROM instant AS i
CROSS JOIN LATERAL (SELECT DISTINCT establishment_id AS id FROM public.external_ident
                    WHERE ident = '945000' AND establishment_id IS NOT NULL) AS es
ORDER BY i.d;

\echo
\echo "351.4 born inside its own window IS counted from birth: Drill Down Norway AS"
\echo "       (record 2023-01-01..2023-12-31, birth 2023-11-01) is absent at 2023-06-30, present at 2023-12-31"
WITH instant(d) AS (VALUES ('2023-06-30'::date), ('2023-12-31'::date), ('2024-12-31'::date))
SELECT i.d, count(su.unit_id) AS existing_records, string_agg(su.name, ', ') AS as_named
FROM instant AS i
LEFT JOIN public.statistical_unit AS su
  ON su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = '947111113'
 AND public.existence_from(su) <= i.d AND i.d < public.existence_until(su)
GROUP BY i.d
ORDER BY i.d;

\echo
\echo "351.5 two more legal units through the real import:"
\echo "       460000001 replicates the 458 row in its own window (valid_from 2024-01-01, valid_to infinity, birth 2024-11-01)"
\echo "       460000002 dies inside its window (valid_from 2023-01-01, valid_to infinity, death 2024-06-30)"
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_460_life', 'Test 351 birth and death inside the record window', 'Test 351 (STATBUS-460)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_460_life_upload(valid_from, valid_to, tax_ident, name, birth_date, death_date) VALUES
    ('2024-01-01', 'infinity', '460000001', 'Born inside its window (458 replica)', '2024-11-01', NULL),
    ('2023-01-01', 'infinity', '460000002', 'Dies inside its window', '2020-05-01', '2024-06-30');
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug = 'import_460_life';

\echo
\echo "351.6 the record covers every instant below; existence (list, card, detail page) follows birth and death"
WITH instant(d) AS (VALUES ('2024-06-29'::date), ('2024-06-30'::date), ('2024-10-31'::date), ('2024-11-01'::date), ('2024-12-31'::date))
SELECT su.external_idents->>'tax_ident' AS tax_ident, i.d,
       su.valid_from <= i.d AND i.d < su.valid_until AS record_covers,
       public.existence_from(su) <= i.d AND i.d < public.existence_until(su) AS exists,
       public.statistical_unit_details('legal_unit', su.unit_id, i.d) ? 'legal_unit' AS on_detail_page
FROM instant AS i
JOIN public.statistical_unit AS su
  ON su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' IN ('460000001', '460000002')
 AND su.valid_from <= i.d AND i.d < su.valid_until
ORDER BY 1, 2;

\echo
\echo "351.7 with both, the card still equals the chart: 460000002 counts in 2023 only, 460000001 in 2024 only"
SELECT c.d, c.unit_type, c.card_count, h.countable_count AS chart_count, c.card_count = h.countable_count AS card_matches_chart
FROM card AS c
JOIN public.statistical_history AS h
  ON h.resolution = 'year' AND h.hash_partition IS NULL AND make_date(h.year, 12, 31) = c.d AND h.unit_type = c.unit_type
WHERE c.unit_type = 'legal_unit'
ORDER BY 1;

\echo
\echo "351.8 the rule, spelled once: existence window = record window intersected with the unit's life"
SELECT v.valid_from, v.valid_until, v.birth_date, v.death_date,
       public.unit_existence_from(v.valid_from, v.birth_date) AS existence_from,
       public.unit_existence_until(v.valid_until, v.death_date) AS existence_until
FROM (VALUES
    ('2023-01-01'::date, 'infinity'::date, '2024-11-01'::date, NULL::date),
    ('2024-01-01'::date, 'infinity'::date, '2024-11-01'::date, NULL::date),
    ('2023-01-01'::date, 'infinity'::date, NULL::date, '2024-06-30'::date),
    ('2023-01-01'::date, '2024-01-01'::date, '1990-01-01'::date, NULL::date)
) AS v(valid_from, valid_until, birth_date, death_date);

ROLLBACK;

BEGIN;
\x auto

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/demo/getting-started.sql

-- Create Import Job for Legal Units (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_311_lu_wsd',
    'Import LU Demo CSV w/ dates (311_partial_update_with_regular_import.sql)',
    'Import job for app/public/demo/legal_units_with_source_dates_demo.csv using legal_unit_source_dates definition.',
    'Test data load (311_partial_update_with_regular_import.sql)';
\echo "User uploads the sample legal units with source dates (via import job: import_311_lu_wsd)"
\copy public.import_311_lu_wsd_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Initial Load"
CALL worker.process_tasks(p_queue => 'import');

\echo "Checking import job statuses for Initial Load"
SELECT slug, state, time_context_ident, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug = 'import_311_lu_wsd' ORDER BY slug;

\echo "Run worker processing for analytics tasks - Initial Load"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Taking snapshot of statistics before partial update (for the historical period being changed)"
CREATE TEMP TABLE stats_before_update AS
SELECT unit_type
     , jsonb_stats_summary_merge_agg(stats_summary) AS stats_summary
 FROM statistical_unit
 WHERE valid_from <= '2023-07-01'::date AND '2023-07-01'::date < valid_until
   AND unit_type = 'legal_unit'
 GROUP BY unit_type;

CREATE TEMP TABLE temp_source_for_update (tax_ident text, stat_ident text, turnover text, valid_from text, valid_to text);
\copy temp_source_for_update FROM 'app/public/demo/legal_units_turnover_update_with_source_dates.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Checking raw stat_for_unit data BEFORE partial update"
\x off
WITH lu_map AS (
    SELECT DISTINCT lu.id as legal_unit_id, src.stat_ident
    FROM temp_source_for_update src
    JOIN public.external_ident ei ON ei.ident = src.stat_ident AND ei.type_id = (SELECT id FROM external_ident_type WHERE code = 'stat_ident')
    JOIN public.legal_unit lu ON ei.legal_unit_id = lu.id
    WHERE daterange(lu.valid_from, lu.valid_until) @> CURRENT_DATE
)
SELECT
    lu_map.stat_ident,
    sfu.valid_from, sfu.valid_to,
    sd.code AS stat_code,
    sfu.value_int, sfu.value_float, sfu.value_string, sfu.value_bool
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN lu_map ON sfu.legal_unit_id = lu_map.legal_unit_id
WHERE daterange(sfu.valid_from, sfu.valid_until) && daterange('2023-01-01', '2024-01-01', '[)')
ORDER BY lu_map.stat_ident::int, sd.code, sfu.valid_from;
\x auto


\echo "Create Import Job for Partial Legal Unit Update using a REGULAR import definition"
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_311_lu_partial_update',
    'Import LU Partial Update (311_partial_update_with_regular_import.sql)',
    'Import job for app/public/demo/legal_units_turnover_update.csv using a REGULAR definition (legal_unit_source_dates), not a stats update one.',
    'Test data load (311_partial_update_with_regular_import.sql)';
\echo "User uploads the legal units turnover update file to a regular import job (import_311_lu_partial_update)"
\copy public.import_311_lu_partial_update_upload(tax_ident,stat_ident,turnover,valid_from,valid_to) FROM 'app/public/demo/legal_units_turnover_update_with_source_dates.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Partial Update"
CALL worker.process_tasks(p_queue => 'import');

\echo "Checking import job status for Partial Update"
SELECT slug, state, time_context_ident, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug = 'import_311_lu_partial_update' ORDER BY slug;

\echo "Run worker processing for analytics tasks - Partial Update"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Checking import data for partial update. Expecting one error, and 8 successful updates with merge_status showing what was applied."
\x on
SELECT
    row_id,
    operation,
    state,
    jsonb_pretty(errors) AS errors,
    jsonb_pretty(merge_status) as merge_status
FROM public.import_311_lu_partial_update_data
ORDER BY row_id;
\x auto

\echo "Checking raw stat_for_unit data AFTER partial update to verify the merge"
\x off
SELECT
    idt.stat_ident,
    sfu.valid_from, sfu.valid_to,
    sd.code AS stat_code,
    sfu.value_int, sfu.value_float, sfu.value_string, sfu.value_bool
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
-- Use a subquery to get a unique legal_unit_id to stat_ident mapping from the import table for reporting
JOIN (
    SELECT DISTINCT legal_unit_id, stat_ident_raw AS stat_ident
    FROM public.import_311_lu_partial_update_data
    WHERE state = 'processed' AND legal_unit_id IS NOT NULL
) idt ON sfu.legal_unit_id = idt.legal_unit_id
WHERE daterange(sfu.valid_from, sfu.valid_until) && daterange('2023-01-01', '2024-01-01', '[)')
ORDER BY idt.stat_ident::int, sd.code, sfu.valid_from;
\x auto

\echo "Checking resulting statistics after Partial Update. Should show turnover updated, and employees unchanged."
\x off
WITH stats_after AS (
    SELECT unit_type, jsonb_stats_summary_merge_agg(stats_summary) AS stats_summary
    FROM statistical_unit
    WHERE valid_from <= '2023-07-01'::date AND '2023-07-01'::date < valid_until AND unit_type = 'legal_unit'
    GROUP BY unit_type
)
SELECT
    'turnover' as statistic,
    sb.stats_summary->'turnover' = sa.stats_summary->'turnover' as are_identical,
    jsonb_pretty(sb.stats_summary->'turnover') AS before,
    jsonb_pretty(sa.stats_summary->'turnover') AS after
FROM stats_after sa JOIN stats_before_update sb ON sa.unit_type = sb.unit_type
UNION ALL
SELECT
    'employees' as statistic,
    sb.stats_summary->'employees' = sa.stats_summary->'employees' as are_identical,
    jsonb_pretty(sb.stats_summary->'employees') AS before,
    jsonb_pretty(sa.stats_summary->'employees') AS after
FROM stats_after sa JOIN stats_before_update sb ON sa.unit_type = sb.unit_type;
\x auto

ROLLBACK;

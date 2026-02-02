BEGIN;
\x auto

\i test/setup.sql

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');
\i samples/demo/getting-started.sql

-- Create Import Job for Legal Units (prerequisite)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_312_lu_wsd',
    'Import LU Demo CSV w/ dates (312)',
    'Import job for 312',
    'Test data load (312)';
\copy public.import_312_lu_wsd_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Establishments (prerequisite)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_312_est_wsd',
    'Import Formal EST Demo CSV w/ dates (312)',
    'Import job for 312',
    'Test data load (312)';
\copy public.import_312_est_wsd_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,physical_latitude,physical_longitude,physical_altitude,birth_date,unit_size_code,status_code) FROM 'app/public/demo/formal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Initial Load"
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Taking snapshot of statistics before partial update (for the historical period being changed)"
CREATE TEMP TABLE stats_before_update AS
SELECT unit_type
     -- ORDER BY ensures deterministic floating-point accumulation order
     , jsonb_stats_summary_merge_agg(stats_summary ORDER BY stats_summary::text) AS stats_summary
 FROM statistical_unit
 WHERE valid_from <= '2023-07-01'::date AND '2023-07-01'::date < valid_until
   AND unit_type = 'establishment'
 GROUP BY unit_type;

CREATE TEMP TABLE temp_source_for_update (tax_ident text, stat_ident text, turnover text, valid_from text, valid_to text);
\copy temp_source_for_update FROM 'app/public/demo/formal_establishments_turnover_update_with_source_dates.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Checking raw stat_for_unit data BEFORE partial update"
\x off
WITH est_map AS (
    SELECT DISTINCT est.id as establishment_id, src.stat_ident
    FROM temp_source_for_update src
    JOIN public.external_ident ei ON ei.ident = src.stat_ident AND ei.type_id = (SELECT id FROM external_ident_type WHERE code = 'stat_ident')
    JOIN public.establishment est ON ei.establishment_id = est.id
    WHERE daterange(est.valid_from, est.valid_until) @> CURRENT_DATE
)
SELECT
    est_map.stat_ident,
    sfu.valid_from, sfu.valid_to,
    sd.code AS stat_code,
    sfu.value_int, sfu.value_float, sfu.value_string, sfu.value_bool
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN est_map ON sfu.establishment_id = est_map.establishment_id
WHERE daterange(sfu.valid_from, sfu.valid_until) && daterange('2023-01-01', '2024-01-01', '[)')
ORDER BY est_map.stat_ident::int, sd.code, sfu.valid_from;
\x auto

CALL test.remove_pg_temp_for_tx_user_switch(p_keep_tables => ARRAY['stats_before_update', 'temp_source_for_update', '_batch_accumulator']);
GRANT SELECT ON TABLE stats_before_update TO regular_user;
\echo "Switching to regular user for partial update"
CALL test.set_user_from_email('test.regular@statbus.org');

\echo "Create Import Job for Partial Establishment Update using a REGULAR import definition"
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_312_est_partial_update',
    'Import EST Partial Update (312_partial_update_establishment_with_regular_import.sql)',
    'Import job for partial establishment update using a REGULAR definition.',
    'Test data load (312_partial_update_establishment_with_regular_import.sql)';

\echo "User uploads the establishments turnover update file to a regular import job (import_312_est_partial_update)"
\copy public.import_312_est_partial_update_upload(tax_ident,stat_ident,turnover,valid_from,valid_to) FROM 'app/public/demo/formal_establishments_turnover_update_with_source_dates.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Partial Update"
CALL worker.process_tasks(p_queue => 'import');

\echo "Run worker processing for analytics tasks - Partial Update"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Checking import data for partial update. Expecting all rows to be processed successfully."
\x on
SELECT
    row_id,
    operation,
    state,
    jsonb_pretty(errors) AS errors,
    jsonb_pretty(merge_status) as merge_status
FROM public.import_312_est_partial_update_data
ORDER BY row_id;
\x auto

\echo "Checking last_edit_by_user_id on statistical_unit to confirm it changed after partial update"
\x off
WITH updated_unit AS (
    SELECT establishment_id AS unit_id
    FROM public.import_312_est_partial_update_data
    WHERE state = 'processed' AND establishment_id IS NOT NULL
    LIMIT 1
)
SELECT
    su.external_idents ->> 'stat_ident' AS stat_ident,
    su.valid_from,
    su.valid_to,
    u.email AS last_edit_by,
    su.stats
FROM public.statistical_unit su
JOIN public.user u ON su.last_edit_by_user_id = u.id
WHERE su.unit_id = (SELECT unit_id FROM updated_unit)
  AND su.unit_type = 'establishment'
ORDER BY su.valid_from;
\x auto


\echo "Checking raw stat_for_unit data AFTER partial update to verify the merge and edit user"
\x off
SELECT
    idt.stat_ident,
    sfu.valid_from, sfu.valid_to,
    sd.code AS stat_code,
    sfu.value_int, sfu.value_float, sfu.value_string, sfu.value_bool,
    u.email AS edit_by
FROM public.stat_for_unit sfu
JOIN public.stat_definition sd ON sfu.stat_definition_id = sd.id
JOIN public.user u ON sfu.edit_by_user_id = u.id
JOIN (
    SELECT DISTINCT establishment_id, stat_ident_raw AS stat_ident
    FROM public.import_312_est_partial_update_data
    WHERE state = 'processed' AND establishment_id IS NOT NULL
) idt ON sfu.establishment_id = idt.establishment_id
WHERE daterange(sfu.valid_from, sfu.valid_until) && daterange('2023-01-01', '2024-01-01', '[)')
ORDER BY idt.stat_ident::int, sd.code, sfu.valid_from;
\x auto

\echo "Checking resulting statistics after Partial Update. Should show turnover updated, and employees unchanged."
\x off
WITH stats_after AS (
    -- ORDER BY ensures deterministic floating-point accumulation order
    SELECT unit_type, jsonb_stats_summary_merge_agg(stats_summary ORDER BY stats_summary::text) AS stats_summary
    FROM statistical_unit
    WHERE valid_from <= '2023-07-01'::date AND '2023-07-01'::date < valid_until AND unit_type = 'establishment'
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

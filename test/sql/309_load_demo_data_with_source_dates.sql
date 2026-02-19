BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/demo/getting-started.sql

SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;

\echo "Initial unit counts"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Available import definitions for data with source dates, and for turnover updates:"
SELECT slug, name, valid_time_from FROM public.import_definition WHERE valid_time_from = 'source_columns' OR slug LIKE '%update%' ORDER BY slug;

-- Create Import Job for Legal Units (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_309_lu_wsd',
    'Import LU Demo CSV w/ dates (309_load_demo_data_with_source_dates.sql)',
    'Import job for app/public/demo/legal_units_with_source_dates_demo.csv using legal_unit_source_dates definition.',
    'Test data load (309_load_demo_data_with_source_dates.sql)';
\echo "User uploads the sample legal units with source dates (via import job: import_309_lu_wsd)"
\copy public.import_309_lu_wsd_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Formal Establishments (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_309_esflu_wsd',
    'Import Formal ES Demo CSV w/ dates (309_load_demo_data_with_source_dates.sql)',
    'Import job for app/public/demo/formal_establishments_units_with_source_dates_demo.csv using establishment_for_lu_source_dates definition.',
    'Test data load (309_load_demo_data_with_source_dates.sql)';
\echo "User uploads the sample formal establishments with source dates (via import job: import_309_esflu_wsd)"
\copy public.import_309_esflu_wsd_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,physical_latitude,physical_longitude,physical_altitude,birth_date,unit_size_code,status_code) FROM 'app/public/demo/formal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Informal Establishments (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates'),
    'import_309_eswlu_wsd',
    'Import Informal ES Demo CSV w/ dates (309_load_demo_data_with_source_dates.sql)',
    'Import job for app/public/demo/informal_establishments_units_with_source_dates_demo.csv using establishment_without_lu_source_dates definition.',
    'Test data load (309_load_demo_data_with_source_dates.sql)';
\echo "User uploads the sample informal establishments with source dates (via import job: import_309_eswlu_wsd)"
\copy public.import_309_eswlu_wsd_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,physical_country_iso_2,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,unit_size_code,status_code,physical_latitude,physical_longitude,physical_altitude) FROM 'app/public/demo/informal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Initial Load"
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Initial Load"
SELECT slug, state, time_context_ident, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug LIKE 'import_309_%' AND slug NOT LIKE '%turnover%' ORDER BY slug;

\echo "Checking for any errors in import_309_lu_wsd_data (including ErrorLine entries)"
SELECT row_id, tax_ident_raw, stat_ident_raw, name_raw, state, action, 
       errors
FROM public.import_309_lu_wsd_data 
WHERE name_raw LIKE 'ErrorLine%' OR state = 'error' OR errors::text != '{}'
ORDER BY row_id
LIMIT 20;

\echo "Unit counts after initial load"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Run worker processing for analytics tasks - Initial Load"
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking statistics after Initial Load"
\x
SELECT unit_type
     , COUNT(DISTINCT unit_id)
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , jsonb_pretty(jsonb_stats_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until
 GROUP BY unit_type;
\x

-- Create Import Job for Legal Units Turnover Update
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'generic_unit_stats_update_job_provided'),
    'import_309_lu_turnover_update',
    'Import LU Turnover Update (309_load_demo_data_with_source_dates.sql)',
    'Import job for app/public/demo/legal_units_turnover_update.csv using generic_unit_stats_update_job_provided definition.',
    'Test data load (309_load_demo_data_with_source_dates.sql)',
    'r_year_curr';
\echo "User uploads the legal units turnover update (via import job: import_309_lu_turnover_update)"
\copy public.import_309_lu_turnover_update_upload(tax_ident,stat_ident,turnover) FROM 'app/public/demo/legal_units_turnover_update.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Turnover Update"
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Turnover Update"
SELECT slug, state, time_context_ident, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug = 'import_309_lu_turnover_update' ORDER BY slug;

\echo "Unit counts after turnover update"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Run worker processing for analytics tasks - Turnover Update"
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Calculating expected statistics from raw _upload tables for verification"
\x
WITH deduped_updates AS (
    SELECT DISTINCT ON (tax_ident)
        tax_ident, employees, turnover
    FROM public.import_309_lu_turnover_update_upload
    ORDER BY tax_ident, stat_ident DESC -- Deduplicate update file, preferring latest stat_ident
),
update_time_context AS (
    -- The update job uses 'r_year_curr', so we resolve its date range to correctly apply the update
    SELECT valid_from, valid_to AS valid_until FROM public.time_context WHERE ident = 'r_year_curr'
),
active_legal_units AS (
    SELECT
        (import.safe_cast_to_integer(
            -- Apply update only if today is within the update's time context
            CASE WHEN CURRENT_DATE >= utc.valid_from AND CURRENT_DATE < utc.valid_until
                THEN COALESCE(upd.employees, lu.employees)
                ELSE lu.employees
            END
        )).p_value as employees,
        (import.safe_cast_to_numeric(
            CASE WHEN CURRENT_DATE >= utc.valid_from AND CURRENT_DATE < utc.valid_until
                THEN COALESCE(upd.turnover, lu.turnover)
                ELSE lu.turnover
            END
        )).p_value as turnover
    FROM public.import_309_lu_wsd_upload AS lu
    LEFT JOIN deduped_updates AS upd ON lu.tax_ident = upd.tax_ident
    CROSS JOIN update_time_context utc
    WHERE (import.safe_cast_to_date(lu.valid_from)).p_value <= CURRENT_DATE AND CURRENT_DATE < ((import.safe_cast_to_date(lu.valid_to)).p_value + '1 day'::interval)
),
active_establishments AS (
    SELECT
        (import.safe_cast_to_integer(employees)).p_value as employees,
        (import.safe_cast_to_numeric(turnover)).p_value as turnover
    FROM (
        SELECT employees, turnover, valid_from, valid_to FROM public.import_309_esflu_wsd_upload
        UNION ALL
        SELECT employees, turnover, valid_from, valid_to FROM public.import_309_eswlu_wsd_upload
    ) AS all_es
    WHERE (import.safe_cast_to_date(all_es.valid_from)).p_value <= CURRENT_DATE AND CURRENT_DATE < ((import.safe_cast_to_date(all_es.valid_to)).p_value + '1 day'::interval)
),
legal_unit_aggs AS (
    SELECT
        COUNT(*) AS total_active_count,
        COUNT(employees) AS employees_count, SUM(employees) AS employees_sum, AVG(employees) AS employees_mean, MAX(employees) AS employees_max, MIN(employees) AS employees_min, STDDEV_SAMP(employees) AS employees_stddev, VAR_SAMP(employees) AS employees_variance,
        COUNT(turnover) AS turnover_count, SUM(turnover) AS turnover_sum, AVG(turnover) AS turnover_mean, MAX(turnover) AS turnover_max, MIN(turnover) AS turnover_min, STDDEV_SAMP(turnover) AS turnover_stddev, VAR_SAMP(turnover) AS turnover_variance
    FROM active_legal_units
),
establishment_aggs AS (
    SELECT
        COUNT(*) AS total_active_count,
        COUNT(employees) AS employees_count, SUM(employees) AS employees_sum, AVG(employees) AS employees_mean, MAX(employees) AS employees_max, MIN(employees) AS employees_min, STDDEV_SAMP(employees) AS employees_stddev, VAR_SAMP(employees) AS employees_variance,
        COUNT(turnover) AS turnover_count, SUM(turnover) AS turnover_sum, AVG(turnover) AS turnover_mean, MAX(turnover) AS turnover_max, MIN(turnover) AS turnover_min, STDDEV_SAMP(turnover) AS turnover_stddev, VAR_SAMP(turnover) AS turnover_variance
    FROM active_establishments
),
legal_unit_stats AS (
    SELECT
        'legal_unit' AS unit_type,
        total_active_count AS count,
        jsonb_pretty(jsonb_build_object(
            'employees', jsonb_build_object('type','number','count',employees_count,'sum',employees_sum,'mean',round(employees_mean,2),'max',employees_max,'min',employees_min,'stddev',round(employees_stddev,2),'variance',round(employees_variance,2),'sum_sq_diff',round((employees_count-1)*employees_variance,2),'coefficient_of_variation_pct',CASE WHEN employees_mean = 0 THEN 0 ELSE round((employees_stddev/employees_mean)*100,2) END),
            'turnover', jsonb_build_object('type','number','count',turnover_count,'sum',turnover_sum,'mean',round(turnover_mean,2),'max',turnover_max,'min',turnover_min,'stddev',round(turnover_stddev,2),'variance',round(turnover_variance,2),'sum_sq_diff',round((turnover_count-1)*turnover_variance,2),'coefficient_of_variation_pct',CASE WHEN turnover_mean = 0 THEN 0 ELSE round((turnover_stddev/turnover_mean)*100,2) END)
        )) AS stats_summary
    FROM legal_unit_aggs
),
establishment_stats AS (
    SELECT
        'establishment' AS unit_type,
        total_active_count AS count,
        jsonb_pretty(jsonb_build_object(
            'employees', jsonb_build_object('type','number','count',employees_count,'sum',employees_sum,'mean',round(employees_mean,2),'max',employees_max,'min',employees_min,'stddev',round(employees_stddev,2),'variance',round(employees_variance,2),'sum_sq_diff',round((employees_count-1)*employees_variance,2),'coefficient_of_variation_pct',CASE WHEN employees_mean = 0 THEN 0 ELSE round((employees_stddev/employees_mean)*100,2) END),
            'turnover', jsonb_build_object('type','number','count',turnover_count,'sum',turnover_sum,'mean',round(turnover_mean,2),'max',turnover_max,'min',turnover_min,'stddev',round(turnover_stddev,2),'variance',round(turnover_variance,2),'sum_sq_diff',round((turnover_count-1)*turnover_variance,2),'coefficient_of_variation_pct',CASE WHEN turnover_mean = 0 THEN 0 ELSE round((turnover_stddev/turnover_mean)*100,2) END)
        )) AS stats_summary
    FROM establishment_aggs
)
SELECT unit_type, count, stats_summary FROM legal_unit_stats
UNION ALL
SELECT unit_type, count, stats_summary FROM establishment_stats
ORDER BY unit_type;

\echo ""
\echo "Checking statistics after Turnover Update"
\x
SELECT unit_type
     , COUNT(DISTINCT unit_id)
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , jsonb_pretty(jsonb_stats_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until
 GROUP BY unit_type;
\x

RESET client_min_messages;

\i test/rollback_unless_persist_is_specified.sql

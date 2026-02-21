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
    'import_310_lu_wsd',
    'Import LU Demo CSV w/ dates (310_idempotent_import_source_dates.sql)',
    'Import job for app/public/demo/legal_units_with_source_dates_demo.csv using legal_unit_source_dates definition.',
    'Test data load (310_idempotent_import_source_dates.sql)';
\echo "User uploads the sample legal units with source dates (via import job: import_310_lu_wsd)"
\copy public.import_310_lu_wsd_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Formal Establishments (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_310_esflu_wsd',
    'Import Formal ES Demo CSV w/ dates (310_idempotent_import_source_dates.sql)',
    'Import job for app/public/demo/formal_establishments_units_with_source_dates_demo.csv using establishment_for_lu_source_dates definition.',
    'Test data load (310_idempotent_import_source_dates.sql)';
\echo "User uploads the sample formal establishments with source dates (via import job: import_310_esflu_wsd)"
\copy public.import_310_esflu_wsd_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,physical_latitude,physical_longitude,physical_altitude,birth_date,unit_size_code,status_code) FROM 'app/public/demo/formal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Informal Establishments (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates'),
    'import_310_eswlu_wsd',
    'Import Informal ES Demo CSV w/ dates (310_idempotent_import_source_dates.sql)',
    'Import job for app/public/demo/informal_establishments_units_with_source_dates_demo.csv using establishment_without_lu_source_dates definition.',
    'Test data load (310_idempotent_import_source_dates.sql)';
\echo "User uploads the sample informal establishments with source dates (via import job: import_310_eswlu_wsd)"
\copy public.import_310_eswlu_wsd_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,physical_country_iso_2,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,unit_size_code,status_code,physical_latitude,physical_longitude,physical_altitude) FROM 'app/public/demo/informal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Initial Load"
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Initial Load"
SELECT slug, state, time_context_ident, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug LIKE 'import_310_%' AND slug NOT LIKE '%turnover%' ORDER BY slug;

\echo "Unit counts after initial load"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "Run worker processing for analytics tasks - Initial Load"
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Idempotency Check: Re-running initial load should result in no changes."
\echo "Taking snapshot of statistical_unit table"
CREATE TEMP TABLE statistical_unit_snapshot_1 AS TABLE statistical_unit;

-- Create new import jobs for the idempotency check
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_310_lu_wsd_idem',
    'Idempotency Check: Import LU Demo CSV w/ dates (310_idempotent_import_source_dates.sql)',
    'Import job for app/public/demo/legal_units_with_source_dates_demo.csv using legal_unit_source_dates definition.',
    'Test data load (310_idempotent_import_source_dates.sql)';
\echo "Re-uploading sample legal units with source dates (via import job: import_310_lu_wsd_idem)"
\copy public.import_310_lu_wsd_idem_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_310_esflu_wsd_idem',
    'Idempotency Check: Import Formal ES Demo CSV w/ dates (310_idempotent_import_source_dates.sql)',
    'Import job for app/public/demo/formal_establishments_units_with_source_dates_demo.csv using establishment_for_lu_source_dates definition.',
    'Test data load (310_idempotent_import_source_dates.sql)';
\echo "Re-uploading sample formal establishments with source dates (via import job: import_310_esflu_wsd_idem)"
\copy public.import_310_esflu_wsd_idem_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,physical_latitude,physical_longitude,physical_altitude,birth_date,unit_size_code,status_code) FROM 'app/public/demo/formal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates'),
    'import_310_eswlu_wsd_idem',
    'Idempotency Check: Import Informal ES Demo CSV w/ dates (310_idempotent_import_source_dates.sql)',
    'Import job for app/public/demo/informal_establishments_units_with_source_dates_demo.csv using establishment_without_lu_source_dates definition.',
    'Test data load (310_idempotent_import_source_dates.sql)';
\echo "Re-uploading sample informal establishments with source dates (via import job: import_310_eswlu_wsd_idem)"
\copy public.import_310_eswlu_wsd_idem_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,physical_country_iso_2,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,unit_size_code,status_code,physical_latitude,physical_longitude,physical_altitude) FROM 'app/public/demo/informal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Idempotency Check"
CALL worker.process_tasks(p_queue => 'import');
\echo "Run worker processing for analytics tasks - Idempotency Check"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Checking data rows for idempotency jobs. Expecting all operations to be 'skip' and merge_status to be 'SKIPPED_IDENTICAL'."
\x
SELECT 'import_310_lu_wsd_idem_data' as source, row_id, operation, errors, invalid_codes, jsonb_pretty(merge_status) as merge_status FROM public.import_310_lu_wsd_idem_data WHERE NOT (merge_status->>'temporal_merge' = 'SKIPPED_IDENTICAL');
SELECT 'import_310_esflu_wsd_idem_data' as source, row_id, operation, errors, invalid_codes, jsonb_pretty(merge_status) as merge_status FROM public.import_310_esflu_wsd_idem_data WHERE NOT (merge_status->>'temporal_merge' = 'SKIPPED_IDENTICAL');
SELECT 'import_310_eswlu_wsd_idem_data' as source, row_id, operation, errors, invalid_codes, jsonb_pretty(merge_status) as merge_status FROM public.import_310_eswlu_wsd_idem_data WHERE NOT (merge_status->>'temporal_merge' = 'SKIPPED_IDENTICAL');
\x

\echo "Verifying statistical_unit table is unchanged after initial load idempotency check"
\x
CREATE TEMP TABLE diff1 AS
    (SELECT unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, invalid_codes, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths FROM statistical_unit)
    EXCEPT
    (SELECT unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, invalid_codes, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths FROM statistical_unit_snapshot_1)
    UNION ALL
    (SELECT unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, invalid_codes, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths FROM statistical_unit_snapshot_1
     EXCEPT
     SELECT unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, invalid_codes, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths FROM statistical_unit)
;
SELECT 'Initial Load Idempotency Diff:' AS check_name, * FROM diff1;
SELECT CASE WHEN (SELECT COUNT(*) FROM diff1) = 0 THEN 'OK: statistical_unit is unchanged' ELSE 'FAIL: statistical_unit has changed' END AS idempotency_check_initial_load,
       (SELECT COUNT(*) FROM diff1) as changed_rows;
DROP TABLE diff1;
\x

-- Create Import Job for Legal Units Turnover Update
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'generic_unit_stats_update_job_provided'),
    'import_310_lu_turnover_update',
    'Import LU Turnover Update (310_idempotent_import_source_dates.sql)',
    'Import job for app/public/demo/legal_units_turnover_update.csv using generic_unit_stats_update_job_provided definition.',
    'Test data load (310_idempotent_import_source_dates.sql)',
    'r_year_curr';
\echo "User uploads the legal units turnover update (via import job: import_310_lu_turnover_update)"
\copy public.import_310_lu_turnover_update_upload(tax_ident,stat_ident,turnover) FROM 'app/public/demo/legal_units_turnover_update.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Turnover Update"
CALL worker.process_tasks(p_queue => 'import');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking import job statuses for Turnover Update"
SELECT slug, state, time_context_ident, total_rows, imported_rows, error IS NOT NULL AS has_error FROM public.import_job WHERE slug = 'import_310_lu_turnover_update' ORDER BY slug;

\echo "Run worker processing for analytics tasks - Turnover Update"
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Idempotency Check: Re-running turnover update should result in no changes."
\echo "Taking snapshot of statistical_unit table"
CREATE TEMP TABLE statistical_unit_snapshot_2 AS TABLE statistical_unit;

-- Create a new import job for the turnover idempotency check
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'generic_unit_stats_update_job_provided'),
    'import_310_lu_turnover_update_idem',
    'Idempotency Check: Import LU Turnover Update (310_idempotent_import_source_dates.sql)',
    'Import job for app/public/demo/legal_units_turnover_update.csv using generic_unit_stats_update_job_provided definition.',
    'Test data load (310_idempotent_import_source_dates.sql)',
    'r_year_curr';
\echo "Re-uploading the legal units turnover update (via import job: import_310_lu_turnover_update_idem)"
\copy public.import_310_lu_turnover_update_idem_upload(tax_ident,stat_ident,turnover) FROM 'app/public/demo/legal_units_turnover_update.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Run worker processing for import jobs - Turnover Idempotency Check"
CALL worker.process_tasks(p_queue => 'import');
\echo "Run worker processing for analytics tasks - Turnover Idempotency Check"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Checking data rows for turnover idempotency job. Expecting all operations to be 'skip' and merge_status to be 'SKIPPED_IDENTICAL'."
\x
SELECT 'import_310_lu_turnover_update_idem_data' as source, row_id, operation, errors, invalid_codes, jsonb_pretty(merge_status) as merge_status FROM public.import_310_lu_turnover_update_idem_data WHERE NOT (merge_status->>'stats_update' = 'SKIPPED_IDENTICAL');
\x

\echo "Verifying statistical_unit table is unchanged after turnover update idempotency check"
\x
CREATE TEMP TABLE diff2 AS (
    ((SELECT unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, invalid_codes, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths FROM statistical_unit)
     EXCEPT
     (SELECT unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, invalid_codes, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths FROM statistical_unit_snapshot_2))
    UNION ALL
    ((SELECT unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, invalid_codes, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths FROM statistical_unit_snapshot_2)
     EXCEPT
     (SELECT unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, primary_activity_category_id, primary_activity_category_path, primary_activity_category_code, secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code, activity_category_paths, sector_id, sector_path, sector_code, sector_name, data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name, physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace, physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2, physical_latitude, physical_longitude, physical_altitude, postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace, postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2, postal_latitude, postal_longitude, postal_altitude, web_address, email_address, phone_number, landline, mobile_number, fax_number, unit_size_id, unit_size_code, status_id, status_code, used_for_counting, invalid_codes, has_legal_unit, related_establishment_ids, excluded_establishment_ids, included_establishment_ids, related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids, related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids, stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths FROM statistical_unit)))
;
SELECT 'Turnover Update Idempotency Diff:' AS check_name, * FROM diff2;
\x
SELECT CASE WHEN (SELECT COUNT(*) FROM diff2) = 0 THEN 'OK: statistical_unit is unchanged' ELSE 'FAIL: statistical_unit has changed' END AS idempotency_check_turnover_update,
       (SELECT COUNT(*) FROM diff2) as changed_rows;
DROP TABLE diff2;

\echo ""
\echo "Checking final statistics after Turnover Update"
\x
SELECT unit_type
     , COUNT(DISTINCT unit_id)
     , jsonb_agg(DISTINCT invalid_codes) FILTER (WHERE invalid_codes IS NOT NULL) AS invalid_codes
     , jsonb_pretty(jsonb_stats_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until
 GROUP BY unit_type;
\x

ROLLBACK;

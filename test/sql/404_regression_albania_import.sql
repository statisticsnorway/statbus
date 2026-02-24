BEGIN;

\i test/setup.sql

-- While the datestyle is set for the database, the pg_regress tool sets the MDY format
-- to ensure consistent date formatting, so we must manually override this.
-- The Albania data uses DD/MM/YYYY format.
SET datestyle TO 'ISO, DMY';

\echo "=== Test 318: Albania Import Regression Test ==="
\echo "This test uses actual Albania client data to reproduce an import analysis hang issue."

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Setting up Albania customizations (tax data source, status codes, stat variables)"
-- The Albania custom setup adds:
-- 1. 'tax' data source
-- 2. Custom status codes (1=Active, 2=Closed, 3=Passive, 4=Never_Active)
-- 3. Custom stat definitions: female, male, selfemp, punpag
-- (Inlined from custom/al.sql to avoid permission issues with procedure creation)

-- Disable stat_ident as Albania doesn't use it
UPDATE public.external_ident_type SET enabled = FALSE WHERE code = 'stat_ident';

-- Add 'tax' data source
INSERT INTO public.data_source_custom (code, name) VALUES ('tax', 'Tax');

-- Disable default status codes and add Albania-specific ones
UPDATE public.status SET enabled = FALSE WHERE id IN (1, 2);

INSERT INTO public.status (code, name, assigned_by_default, used_for_counting, priority, enabled, custom)
VALUES
    ('1', 'Active', TRUE, TRUE, 3, TRUE, TRUE),
    ('2', 'Closed', FALSE, FALSE, 6, TRUE, TRUE),
    ('3', 'Passive', FALSE, FALSE, 4, TRUE, TRUE),
    ('4', 'Never_Active', FALSE, FALSE, 5, TRUE, TRUE);

-- Add Albania-specific stat definitions (male, female, selfemp, punpag)
INSERT INTO public.stat_definition (code, type, frequency, name, priority)
VALUES
    ('female', 'int', 'yearly', 'Female', 3),
    ('male', 'int', 'yearly', 'Male', 4),
    ('selfemp', 'int', 'yearly', 'SelfEmp', 5),
    ('punpag', 'int', 'yearly', 'PunPag', 6)
ON CONFLICT (code) DO UPDATE SET enabled = true;

\echo "Setting activity category standard to ISIC v4 and country to Albania"
INSERT INTO settings(activity_category_standard_id, country_id)
SELECT (SELECT id FROM activity_category_standard WHERE code = 'isic_v4')
     , (SELECT id FROM public.country WHERE iso_2 = 'AL')
ON CONFLICT (only_one_setting)
DO UPDATE SET
    activity_category_standard_id = EXCLUDED.activity_category_standard_id,
    country_id = EXCLUDED.country_id;

\echo "Uploading Albania regions"
\echo "NOTE: Region paths use leading zeros (01, 02, etc.) to avoid code collisions"
\copy public.region_upload(path, name) FROM 'test/data/318_albania_regions.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Uploading Albania sectors"
\copy public.sector_custom_only(path, name, description) FROM 'test/data/318_albania_sectors.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Uploading Albania legal forms"
\copy public.legal_form_custom_only(code, name) FROM 'test/data/318_albania_legal_forms.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Verifying reference data loaded correctly"
SELECT COUNT(*) AS region_count FROM public.region;
SELECT COUNT(*) AS sector_count FROM public.sector_custom_only;
SELECT COUNT(*) AS legal_form_count FROM public.legal_form_custom_only;

\echo "Checking available stat definitions (should include male, female, selfemp, punpag)"
SELECT code, name, type FROM public.stat_definition ORDER BY priority;

\echo "Checking data sources (should include 'tax')"
SELECT code, name FROM public.data_source ORDER BY code;

\echo "Initial unit counts"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "=== Creating import job for Legal Units (with source dates) ==="
-- Albania data has valid_from and valid_to columns, so we use legal_unit_source_dates
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_318_lu',
    'Import Albania Legal Units (318_regression_albania_import.sql)',
    'Import job for test/data/318_albania_legal_units.csv using legal_unit_source_dates definition.',
    'Test data load (318_regression_albania_import.sql)';

\echo "Uploading Albania legal units (333 rows)"
\copy public.import_318_lu_upload(tax_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code,male,female,selfemp,punpag) FROM 'test/data/318_albania_legal_units.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Checking upload table row count"
SELECT COUNT(*) AS upload_row_count FROM public.import_318_lu_upload;

\echo "=== Running import worker for legal units ==="
\echo "NOTE: This is where the analysis step may hang with large/complex data"
CALL worker.process_tasks(p_queue => 'import');

\echo "Checking worker task status after legal unit import"
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking legal unit import job status"
SELECT slug, state, time_context_ident, total_rows, imported_rows, error IS NOT NULL AS has_error 
FROM public.import_job WHERE slug = 'import_318_lu';

\echo "Checking for any errors in legal unit import data"
SELECT row_id, tax_ident_raw, name_raw, state, action, errors
FROM public.import_318_lu_data 
WHERE state = 'error' OR errors::text != '{}'
ORDER BY row_id
LIMIT 20;

\echo "Legal unit counts after import"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "=== Creating import job for Establishments (job provided time) ==="
-- Albania establishment data lacks valid_from/valid_to, so we use job_provided time
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_job_provided'),
    'import_318_es',
    'Import Albania Establishments (318_regression_albania_import.sql)',
    'Import job for test/data/318_albania_establishments.csv using establishment_for_lu_job_provided definition.',
    'Test data load (318_regression_albania_import.sql)',
    'r_year_curr';

\echo "Uploading Albania establishments (8439 rows)"
\copy public.import_318_es_upload(legal_unit_tax_ident,tax_ident,physical_region_code,primary_activity_category_code,secondary_activity_category_code,employees,name,postal_country_iso_2,physical_country_iso_2) FROM 'test/data/318_albania_establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "Checking establishment upload table row count"
SELECT COUNT(*) AS upload_row_count FROM public.import_318_es_upload;

\echo "=== Running import worker for establishments ==="
CALL worker.process_tasks(p_queue => 'import');

\echo "Checking worker task status after establishment import"
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking establishment import job status"
SELECT slug, state, time_context_ident, total_rows, imported_rows, error IS NOT NULL AS has_error 
FROM public.import_job WHERE slug = 'import_318_es';

\echo "Checking for any errors in establishment import data"
SELECT row_id, tax_ident_raw, name_raw, legal_unit_tax_ident_raw, state, action, errors
FROM public.import_318_es_data 
WHERE state = 'error' OR errors::text != '{}'
ORDER BY row_id
LIMIT 20;

\echo "Final unit counts"
SELECT
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) AS distinct_unit_count FROM public.enterprise) AS enterprise_count;

\echo "=== Running analytics worker ==="
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Checking worker task status after analytics"
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "Checking statistics summary"
\x
SELECT unit_type
     , COUNT(DISTINCT unit_id)
     , jsonb_pretty(jsonb_stats_merge_agg(stats_summary)) AS stats_summary
 FROM statistical_unit
 WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until
 GROUP BY unit_type;
\x

RESET client_min_messages;

\i test/rollback_unless_persist_is_specified.sql

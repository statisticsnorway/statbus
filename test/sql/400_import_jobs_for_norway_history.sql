--
-- Test: Import jobs for Norway history data
--
-- This test uses multiple transactions to allow worker.process_tasks() to
-- commit between tasks, avoiding O(n^2) performance issues that occur when
-- all batch processing happens in a single transaction.
--
-- CRITICAL: Upload order determines processing priority!
-- - Older years must be uploaded before newer years (newer cuts older)
-- - All LU uploads must happen before all ES uploads (ES depends on LU external_idents)
--
-- Structure:
-- 0. Cleanup phase: Ensure clean state from any prior runs
-- 1. Setup phase (transaction 1): Create definitions, jobs, load data in correct order
-- 2. Processing phase (no transaction): Worker commits per-task
-- 3. Verification phase (transaction 2): Check results
-- 4. Cleanup phase: Remove test data unless PERSIST=true
--

-- ============================================================================
-- PHASE 0: INITIAL CLEANUP AND PAUSE WORKER
-- ============================================================================
-- Reset any leftover data from prior test runs. This is necessary because
-- the test commits data during execution, so a failed or interrupted run
-- may leave data behind.
\echo "Cleaning up any leftover data from prior runs"
SELECT public.reset(true, 'getting-started');

-- Pause the background worker so we control task processing order.
-- Manual CALL worker.process_tasks() is NOT affected by pause.
-- The worker will auto-resume after 1 hour if we forget to call resume.
\echo "Pausing background worker for test duration"
SELECT worker.pause('1 hour'::interval);

-- ============================================================================
-- PHASE 1: SETUP (in transaction so setup.sql helpers work)
-- ============================================================================
BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Setting up Statbus for Norway"
\i samples/norway/getting-started.sql

\i samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
\i samples/norway/brreg/create-import-definition-underenhet-2024.sql

-- Display summary of created definitions
SELECT slug, name, note, valid_time_from, strategy, valid, validation_error
FROM public.import_definition
WHERE slug LIKE 'brreg_%_2024'
ORDER BY slug;

-- Create ALL jobs at once (LU and ES)
-- Per year jobs for hovedenhet (legal units)
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2015_h', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2015 History', 'This job handles the import of BRREG Hovedenhet history data for 2015.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2016_h', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2016 History', 'This job handles the import of BRREG Hovedenhet history data for 2016.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2017_h', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2017 History', 'This job handles the import of BRREG Hovedenhet history data for 2017.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2018_h', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2018 History', 'This job handles the import of BRREG Hovedenhet history data for 2018.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

-- Per year jobs for underenhet (establishments)
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2015_h', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2015 History', 'This job handles the import of BRREG Underenhet history data for 2015.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2016_h', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2016 History', 'This job handles the import of BRREG Underenhet history data for 2016.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2017_h', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2017 History', 'This job handles the import of BRREG Underenhet history data for 2017.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2018_h', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2018 History', 'This job handles the import of BRREG Underenhet history data for 2018.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

\echo Verify the concrete tables of one import job
\d public.import_lu_2015_h_upload
\d public.import_lu_2015_h_data

\d public.import_es_2015_h_upload
\d public.import_es_2015_h_data

-- Display the definition snapshot for one job (optional, can be large)
-- SELECT slug, definition_snapshot FROM public.import_job WHERE slug = 'import_lu_2015_h' ORDER BY slug;

-- Verify user context is set correctly for import jobs
\echo "Verifying user context for import jobs"
SELECT slug,
       (SELECT email FROM public.user WHERE id = user_id) AS user_email
FROM public.import_job
WHERE slug = 'import_lu_2015_h'
ORDER BY slug;

-- ============================================================================
-- UPLOAD DATA IN CORRECT ORDER:
-- 1. All LU uploads (oldest to newest) - these get lower priority numbers
-- 2. All ES uploads (oldest to newest) - these get higher priority numbers
-- This ensures all LU tasks complete before any ES tasks start
-- ============================================================================

\echo "Loading historical legal units (hovedenheter) - oldest first"
\copy public.import_lu_2015_h_upload FROM 'samples/norway/history/2015-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2016_h_upload FROM 'samples/norway/history/2016-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2017_h_upload FROM 'samples/norway/history/2017-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2018_h_upload FROM 'samples/norway/history/2018-enheter.csv' WITH CSV HEADER;

\echo "Loading historical establishments (underenheter) - oldest first, AFTER all LU"
\copy public.import_es_2015_h_upload FROM 'samples/norway/history/2015-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2016_h_upload FROM 'samples/norway/history/2016-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2017_h_upload FROM 'samples/norway/history/2017-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2018_h_upload FROM 'samples/norway/history/2018-underenheter.csv' WITH CSV HEADER;

\echo Check import job state before processing
SELECT state, count(*) FROM import_job GROUP BY state;

\echo Check data row state before import (should be empty as worker hasn't run prepare)
SELECT state, count(*) FROM public.import_lu_2015_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_es_2015_h_data GROUP BY state;

-- Commit setup so worker can see the data
COMMIT;

-- ============================================================================
-- PHASE 2: PROCESSING (outside transaction - worker commits per task)
-- ============================================================================
-- Process LU tasks first (priorities 1-4), then ES tasks (priorities 5-8).
-- This is CRITICAL because ES analysis needs to look up LU external_idents,
-- which are only created AFTER the LU's process step completes.
-- Using p_max_priority ensures all lower-priority tasks complete before
-- higher-priority ones start.

\echo "Processing legal unit imports first (priorities 1-4)"
CALL worker.process_tasks(p_queue => 'import', p_max_priority => 4);

\echo "Processing establishment imports (priorities 5-8)"
-- Notice that 'WARNING:  Could not find primary_activity_category_code' is expected due to data quality issues, but should not hinder the import process.
CALL worker.process_tasks(p_queue => 'import');

-- ============================================================================
-- PHASE 3: VERIFICATION (in transaction for consistent reads)
-- ============================================================================
BEGIN;

\echo Check the states of the import job tasks.
select queue,t.command,state,error from worker.tasks as t join worker.command_registry as c on t.command = c.command where t.command = 'import_job_process' order by priority;
select slug, state, error is not null as failed, time_context_ident, default_valid_from, default_valid_to, total_rows, imported_rows, import_completed_pct, error as error_details from public.import_job WHERE slug LIKE 'import_%_h' ORDER BY slug;

\echo Check import job state after import
SELECT state, count(*) FROM import_job GROUP BY state;

\echo Check data row state after import (should be 'processed' or 'error')
SELECT state, count(*) FROM public.import_lu_2015_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_lu_2016_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_lu_2017_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_lu_2018_h_data GROUP BY state;

SELECT state, count(*) FROM public.import_es_2015_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_es_2016_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_es_2017_h_data GROUP BY state;
SELECT state, count(*) FROM public.import_es_2018_h_data GROUP BY state;

\echo "Show any error rows from import data tables"
SELECT row_id, errors, merge_status FROM public.import_lu_2015_h_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, errors, merge_status FROM public.import_lu_2016_h_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, errors, merge_status FROM public.import_lu_2017_h_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, errors, merge_status FROM public.import_lu_2018_h_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, errors, merge_status FROM public.import_es_2015_h_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, errors, merge_status FROM public.import_es_2016_h_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, errors, merge_status FROM public.import_es_2017_h_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, errors, merge_status FROM public.import_es_2018_h_data WHERE state = 'error' ORDER BY row_id;

\echo Check the state of all tasks before running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

COMMIT;

-- Run analytics outside transaction
CALL worker.process_tasks(p_queue => 'analytics');

BEGIN;

\echo Check the state of all tasks after running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

COMMIT;

-- Run any remaining tasks outside transaction
CALL worker.process_tasks();

BEGIN;

\echo Check the state of all tasks after running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo Overview of statistical units, but not details, there are too many units.
SELECT valid_from
     , valid_to
     , name
     , external_idents ->> 'tax_ident' AS tax_ident
     , unit_type
 FROM public.statistical_unit
 ORDER BY valid_from, valid_to, name, external_idents ->> 'tax_ident', unit_type, unit_id;

\echo Generate traces of indices used to build the history, analysis with tools such as shipped "/pev2" aka "postgres explain visualizer pev2 query performance"
\o tmp/50_import_jobs_for_norway_small_history-timepoints.log
EXPLAIN ANALYZE SELECT * FROM public.timepoints;
\o tmp/50_import_jobs_for_norway_small_history-timesegments_def.log
EXPLAIN ANALYZE SELECT * FROM public.timesegments_def;
\o tmp/50_import_jobs_for_norway_small_history-timeline_establishment_def.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_establishment_def;
\o tmp/50_import_jobs_for_norway_small_history-timeline_legal_unit_def.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_legal_unit_def;
\o tmp/50_import_jobs_for_norway_small_history-timeline_enterprise_def.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_enterprise_def;
\o tmp/50_import_jobs_for_norway_small_history-statistical_unit_def.log
EXPLAIN ANALYZE SELECT * FROM public.statistical_unit_def;
\o

RESET client_min_messages;

COMMIT;

-- ============================================================================
-- PHASE 4: CLEANUP (unless PERSIST=true)
-- ============================================================================
-- Resume the background worker before cleanup
\echo "Resuming background worker"
SELECT worker.resume();

\i test/cleanup_unless_persist_is_specified.sql

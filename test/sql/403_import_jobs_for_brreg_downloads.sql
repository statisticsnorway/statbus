--
-- Test: Import jobs for BRREG full download data
--
-- This test uses multiple transactions to allow worker.process_tasks() to
-- commit between tasks, avoiding O(n^2) performance issues.
--
-- CRITICAL: Upload order determines processing priority!
-- - LU (hovedenhet) must be uploaded before ES (underenhet)
-- - ES depends on LU external_idents which are created during LU processing
--
-- NOTE: This test requires manually downloaded files in tmp/:
-- - tmp/enheter.csv (from BRREG hovedenhet download)
-- - tmp/underenheter_filtered.csv (from BRREG underenhet download, filtered)
--

-- ============================================================================
-- PHASE 0: INITIAL CLEANUP AND PAUSE WORKER
-- ============================================================================
\echo "Cleaning up any leftover data from prior runs"
SELECT public.reset(true, 'getting-started');

\echo "Pausing background worker for test duration"
SELECT worker.pause('1 hour'::interval);

-- ============================================================================
-- PHASE 1: SETUP (in transaction so setup.sql helpers work)
-- ============================================================================
BEGIN;

\i test/setup.sql

\echo "Setting up Statbus (Norway) and BRREG import definitions (2025)"
\i samples/norway/getting-started.sql
\i samples/norway/brreg/create-import-definition-hovedenhet-2025.sql
\i samples/norway/brreg/create-import-definition-underenhet-2025.sql

\echo "Switch to test admin user"
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Verify import definitions exist"
SELECT slug, name, mode
  FROM public.import_definition
 WHERE slug IN ('brreg_hovedenhet_2025','brreg_underenhet_2025')
 ORDER BY slug;

-- ============================================================================
-- Create import jobs - LU first, then ES (upload order = processing priority)
-- ============================================================================
\echo "Create import job for LU (hovedenhet) - uploaded FIRST for priority"
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2025')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id)
SELECT def.id,
       'import_hovedenhet_2025',
       '2025-01-01'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Hovedenhet 2025 (Current)',
       'This job handles the import of current BRREG Hovedenhet data.',
       (select id from public.user where email = 'test.admin@statbus.org')
FROM def
ON CONFLICT (slug) DO UPDATE SET
    default_valid_from = '2025-01-01'::DATE,
    default_valid_to = 'infinity'::DATE
RETURNING slug, state;

\echo "Load LU data FIRST"
\copy public.import_hovedenhet_2025_upload FROM 'tmp/enheter.csv' WITH CSV HEADER

\echo "Create import job for ES (underenhet) - uploaded SECOND"
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2025')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id)
SELECT def.id,
       'import_underenhet_2025',
       '2025-01-01'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Underenhet 2025 (Current)',
       'This job handles the import of current BRREG Underenhet data.',
       (select id from public.user where email = 'test.admin@statbus.org')
FROM def
ON CONFLICT (slug) DO UPDATE SET
    default_valid_from = '2025-01-01'::DATE,
    default_valid_to = 'infinity'::DATE
RETURNING slug, state;

\echo "Load ES data SECOND (lower priority than LU)"
\copy public.import_underenhet_2025_upload FROM 'tmp/underenheter_filtered.csv' WITH CSV HEADER

\echo "Check import job state before processing"
SELECT slug, state, total_rows, imported_rows
  FROM public.import_job
 WHERE slug IN ('import_hovedenhet_2025', 'import_underenhet_2025')
 ORDER BY slug;

COMMIT;

-- ============================================================================
-- PHASE 2: PROCESSING (outside transaction - worker commits per task)
-- ============================================================================
\echo "Processing import jobs (LU processes first due to upload order)"
CALL worker.process_tasks(p_queue => 'import');

-- ============================================================================
-- PHASE 3: VERIFICATION
-- ============================================================================
BEGIN;

\echo "Check the states of the import job tasks"
SELECT queue, t.command, state, error
  FROM worker.tasks AS t
  JOIN worker.command_registry AS c on t.command = c.command
 WHERE t.command = 'import_job_process'
 ORDER BY priority;

\echo "Check import job state after processing"
SELECT slug, state, error IS NOT NULL AS failed, total_rows, imported_rows, import_completed_pct, error as error_details
  FROM public.import_job
 WHERE slug IN ('import_hovedenhet_2025', 'import_underenhet_2025')
 ORDER BY slug;

\echo "Check data row states after import"
SELECT state, count(*) FROM public.import_hovedenhet_2025_data GROUP BY state ORDER BY state;
SELECT state, count(*) FROM public.import_underenhet_2025_data GROUP BY state ORDER BY state;

\echo "Show any error rows from import data tables"
SELECT row_id, errors, merge_status FROM public.import_hovedenhet_2025_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, errors, merge_status FROM public.import_underenhet_2025_data WHERE state = 'error' ORDER BY row_id;

COMMIT;

-- Skip analytics for now - derive_reports is too slow
-- CALL worker.process_tasks(p_queue => 'analytics');

-- ============================================================================
-- PHASE 4: CLEANUP
-- ============================================================================
\echo "Resuming background worker"
SELECT worker.resume();

\i test/cleanup_unless_persist_is_specified.sql

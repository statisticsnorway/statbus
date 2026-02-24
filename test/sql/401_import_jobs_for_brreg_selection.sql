--
-- Test: Import jobs for BRREG selection data (~29K rows)
--
-- This test uses multiple transactions to allow worker.process_tasks() to
-- commit between tasks, avoiding O(n^2) performance issues.
--
-- CRITICAL: Upload order determines processing priority!
-- - LU (hovedenhet) must be uploaded before ES (underenhet)
-- - ES depends on LU external_idents which are created during LU processing
--
-- Performance benchmark data is written to:
--   test/expected/performance/401_import_benchmark.perf
--

-- ============================================================================
-- PHASE 0: SETUP
-- ============================================================================
-- Note: No reset needed - 4xx tests run in isolated databases from template

\echo 'Pausing background worker for test duration'
SELECT worker.pause('1 hour'::interval);

-- ============================================================================
-- PHASE 1: SETUP (in transaction so setup.sql helpers work)
-- ============================================================================
BEGIN;

\i test/setup.sql

\echo "Setting up Statbus (Norway) and BRREG import definitions (2024)"
\i samples/norway/getting-started.sql
\i samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
\i samples/norway/brreg/create-import-definition-underenhet-2024.sql

\echo "Switch to test admin user"
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Verify import definitions exist"
SELECT slug, name, mode
  FROM public.import_definition
 WHERE slug IN ('brreg_hovedenhet_2024','brreg_underenhet_2024')
 ORDER BY slug;

-- ============================================================================
-- Create import jobs - LU first, then ES (upload order = processing priority)
-- ============================================================================
\echo "Create import job for LU (hovedenhet) - uploaded FIRST for priority"
WITH def_he AS (
  SELECT id FROM public.import_definition WHERE slug = 'brreg_hovedenhet_2024'
)
INSERT INTO public.import_job (
  definition_id,
  slug,
  default_valid_from,
  default_valid_to,
  description,
  note,
  user_id
)
SELECT
  def_he.id,
  'import_hovedenhet_2025_selection',
  '2025-01-01'::date,
  'infinity'::date,
  'Import Job for BRREG Hovedenhet 2025 Selection',
  'This job handles the import of BRREG Hovedenhet selection data for 2025.',
  (SELECT id FROM public.user WHERE email = 'test.admin@statbus.org')
FROM def_he
ON CONFLICT (slug) DO NOTHING
RETURNING slug, state;

\echo "Load LU data FIRST"
\copy public.import_hovedenhet_2025_selection_upload FROM 'samples/norway/legal_unit/enheter-selection.csv' WITH CSV HEADER

\echo "Create import job for ES (underenhet) - uploaded SECOND"
WITH def_ue AS (
  SELECT id FROM public.import_definition WHERE slug = 'brreg_underenhet_2024'
)
INSERT INTO public.import_job (
  definition_id,
  slug,
  default_valid_from,
  default_valid_to,
  description,
  note,
  user_id
)
SELECT
  def_ue.id,
  'import_underenhet_2025_selection',
  '2025-01-01'::date,
  'infinity'::date,
  'Import Job for BRREG Underenhet 2025 Selection',
  'This job handles the import of BRREG Underenhet selection data for 2025.',
  (SELECT id FROM public.user WHERE email = 'test.admin@statbus.org')
FROM def_ue
ON CONFLICT (slug) DO NOTHING
RETURNING slug, state;

\echo "Load ES data SECOND (lower priority than LU)"
\copy public.import_underenhet_2025_selection_upload FROM 'samples/norway/establishment/underenheter-selection.csv' WITH CSV HEADER

\echo "Check import job state before processing"
SELECT slug, state, total_rows, imported_rows
  FROM public.import_job
 WHERE slug LIKE 'import_%_selection'
 ORDER BY slug;

COMMIT;

-- ============================================================================
-- PHASE 2: PROCESSING (outside transaction - worker commits per task)
-- ============================================================================
\echo "Processing import jobs (LU processes first due to upload order)"
CALL worker.process_tasks(p_queue => 'import');

-- ============================================================================
-- PHASE 3: VERIFICATION AND BENCHMARK
-- ============================================================================
BEGIN;

\echo 'Check the states of the import job tasks'
SELECT queue, t.command, state, error
  FROM worker.tasks AS t
  JOIN worker.command_registry AS c on t.command = c.command
 WHERE t.command = 'import_job_process'
 ORDER BY priority;

\echo 'Check import job state after processing (deterministic)'
SELECT slug, state, error IS NOT NULL AS failed, total_rows, imported_rows, import_completed_pct
  FROM public.import_job
 WHERE slug LIKE 'import_%_selection'
 ORDER BY slug;

\echo 'Check data row states after import'
SELECT state, count(*) FROM public.import_hovedenhet_2025_selection_data GROUP BY state ORDER BY state;
SELECT state, count(*) FROM public.import_underenhet_2025_selection_data GROUP BY state ORDER BY state;

\echo 'Show any error rows from import data tables (first 10)'
SELECT row_id, errors, merge_status FROM public.import_hovedenhet_2025_selection_data WHERE state = 'error' ORDER BY row_id LIMIT 10;
SELECT row_id, errors, merge_status FROM public.import_underenhet_2025_selection_data WHERE state = 'error' ORDER BY row_id LIMIT 10;

-- ============================================================================
-- SCALING ANALYSIS (Deterministic classification)
-- ============================================================================
\echo ''
\echo '--- Scaling Analysis (Deterministic) ---'
\echo 'Comparing LU (~5K rows) vs ES (~24K rows) performance.'
\echo 'ES has ~5x more rows - if time ratio >> 5, scaling is non-linear.'
\echo ''

-- Calculate scaling classification (deterministic output only)
-- Variable timing data is written to the .perf file below
WITH job_metrics AS (
    SELECT
        slug,
        CASE WHEN slug LIKE '%hovedenhet%' THEN 'LU' ELSE 'ES' END AS phase,
        total_rows,
        analysis_rows_per_sec,
        import_rows_per_sec AS processing_rows_per_sec
    FROM public.import_job
    WHERE slug LIKE 'import_%_selection'
)
SELECT
    phase,
    total_rows,
    -- Classify based on absolute performance (deterministic categories)
    CASE
        WHEN processing_rows_per_sec >= 1000 THEN 'GOOD'
        WHEN processing_rows_per_sec >= 100 THEN 'OK'
        WHEN processing_rows_per_sec >= 10 THEN 'SLOW'
        ELSE 'VERY_SLOW'
    END AS proc_status,
    CASE
        WHEN analysis_rows_per_sec >= 1000 THEN 'GOOD'
        WHEN analysis_rows_per_sec >= 100 THEN 'OK'
        WHEN analysis_rows_per_sec >= 10 THEN 'SLOW'
        ELSE 'VERY_SLOW'
    END AS analysis_status
FROM job_metrics
ORDER BY phase;

\echo ''
\echo 'Target: sql_saga achieves ~5000 rows/sec. Anything below 100 rows/sec needs investigation.'
\echo 'See test/expected/performance/401_import_benchmark.perf for detailed timing.'
\echo ''

COMMIT;

-- ============================================================================
-- WRITE PERFORMANCE DATA TO FILE (Variable timing)
-- ============================================================================
BEGIN;

\set perf_file test/expected/performance/401_import_benchmark.perf
\pset tuples_only on
\pset footer off
\o :perf_file
SELECT '# Import Benchmark: BRREG Selection Data (~29K rows)';
SELECT '# These numbers are reference baselines, not test assertions.';
SELECT '# Target: sql_saga achieves ~5000 rows/sec at 1M+ scale.';
SELECT '#';
SELECT '';
\pset tuples_only off
SELECT '# Job timing summary:' as "header";
SELECT
    slug,
    total_rows,
    ROUND(EXTRACT(EPOCH FROM (analysis_stop_at - analysis_start_at))::numeric, 2) AS analysis_sec,
    ROUND(EXTRACT(EPOCH FROM (processing_stop_at - processing_start_at))::numeric, 2) AS processing_sec,
    ROUND(EXTRACT(EPOCH FROM (processing_stop_at - analysis_start_at))::numeric, 2) AS total_sec,
    ROUND(analysis_rows_per_sec::numeric, 2) AS analysis_rows_per_sec,
    ROUND(import_rows_per_sec::numeric, 2) AS processing_rows_per_sec
FROM public.import_job
WHERE slug LIKE 'import_%_selection'
ORDER BY slug;

\pset tuples_only on
SELECT '';
\pset tuples_only off
SELECT '# Per-row timing (ms/row):' as "header";
SELECT
    slug,
    total_rows,
    ROUND((EXTRACT(EPOCH FROM (analysis_stop_at - analysis_start_at)) * 1000 / NULLIF(total_rows, 0))::numeric, 2) AS analysis_ms_per_row,
    ROUND((EXTRACT(EPOCH FROM (processing_stop_at - processing_start_at)) * 1000 / NULLIF(total_rows, 0))::numeric, 2) AS processing_ms_per_row
FROM public.import_job
WHERE slug LIKE 'import_%_selection'
ORDER BY slug;

\pset tuples_only on
SELECT '';
\pset tuples_only off
SELECT '# Scaling comparison (LU ~5K vs ES ~24K rows):' as "header";
WITH metrics AS (
    SELECT
        CASE WHEN slug LIKE '%hovedenhet%' THEN 'LU' ELSE 'ES' END AS phase,
        total_rows,
        import_rows_per_sec AS processing_rows_per_sec,
        analysis_rows_per_sec,
        EXTRACT(EPOCH FROM (processing_stop_at - processing_start_at)) * 1000 / NULLIF(total_rows, 0) AS processing_ms_per_row
    FROM public.import_job
    WHERE slug LIKE 'import_%_selection'
)
SELECT
    'LU' AS base_phase,
    (SELECT total_rows FROM metrics WHERE phase = 'LU') AS lu_rows,
    (SELECT total_rows FROM metrics WHERE phase = 'ES') AS es_rows,
    ROUND((SELECT total_rows FROM metrics WHERE phase = 'ES')::numeric / 
          NULLIF((SELECT total_rows FROM metrics WHERE phase = 'LU'), 0), 2) AS row_ratio,
    ROUND((SELECT processing_ms_per_row FROM metrics WHERE phase = 'ES')::numeric / 
          NULLIF((SELECT processing_ms_per_row FROM metrics WHERE phase = 'LU'), 0), 2) AS ms_per_row_ratio,
    CASE
        WHEN (SELECT processing_ms_per_row FROM metrics WHERE phase = 'ES') / 
             NULLIF((SELECT processing_ms_per_row FROM metrics WHERE phase = 'LU'), 0) < 1.5 THEN 'LINEAR (O(n))'
        WHEN (SELECT processing_ms_per_row FROM metrics WHERE phase = 'ES') / 
             NULLIF((SELECT processing_ms_per_row FROM metrics WHERE phase = 'LU'), 0) < 3.0 THEN 'SUBLINEAR'
        ELSE 'NON-LINEAR (investigate)'
    END AS scaling_assessment;

\o
\pset footer on
\pset tuples_only off

COMMIT;

-- ============================================================================
-- PHASE 3B: ANALYTICS (enabled for performance testing)
-- ============================================================================
-- The analytics derivation includes multiple phases:
-- 1. derive_reports (~1ms) - just enqueues derive_statistical_history
-- 2. derive_statistical_history (~26s) - then enqueues derive_statistical_unit_facet
-- 3. derive_statistical_unit_facet (~1.2s) - then enqueues derive_statistical_history_facet
-- 4. derive_statistical_history_facet (~10+ min) - the bottleneck

BEGIN;

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

\echo Check the state of all tasks after final processing.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

COMMIT;

-- ============================================================================
-- PHASE 4: CLEANUP
-- ============================================================================
\echo 'Resuming background worker'
SELECT worker.resume();

\i test/cleanup_unless_persist_is_specified.sql

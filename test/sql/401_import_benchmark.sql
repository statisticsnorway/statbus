--
-- Test: Import Performance Benchmark with Query Profiling
--
-- Uses small-history data (~40 rows) for quick iteration.
-- Enables AUTO EXPLAIN and pg_stat_monitor to identify slow queries.
--
-- Output files:
--   test/expected/performance/401_import_benchmark.perf - timing summary
--   test/expected/performance/401_import_benchmark_queries.perf - slow query analysis
--

-- ============================================================================
-- PHASE 0: SETUP AND ENABLE PROFILING
-- ============================================================================
-- Note: No reset needed - 4xx tests run in isolated databases from template

\echo 'Pausing background worker for test duration'
SELECT worker.pause('1 hour'::interval);

-- Enable AUTO EXPLAIN for slow queries (logs to PostgreSQL log)
-- This captures EXPLAIN ANALYZE for queries taking > 100ms
LOAD 'auto_explain';
SET auto_explain.log_min_duration = '100ms';
SET auto_explain.log_analyze = true;
SET auto_explain.log_buffers = true;
SET auto_explain.log_timing = true;
SET auto_explain.log_nested_statements = true;

-- Reset pg_stat_monitor if available (for query statistics)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_monitor') THEN
        PERFORM pg_stat_monitor_reset();
    END IF;
END;
$$;

-- ============================================================================
-- PHASE 1: SETUP (in transaction)
-- ============================================================================
BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\echo 'Setting up Statbus for Norway'
\i samples/norway/getting-started.sql

\i samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
\i samples/norway/brreg/create-import-definition-underenhet-2024.sql

-- Create benchmark results table
CREATE TEMP TABLE benchmark_results (
    phase TEXT NOT NULL,
    job_slug TEXT NOT NULL,
    total_rows INT,
    analysis_ms NUMERIC,
    processing_ms NUMERIC,
    total_ms NUMERIC,
    analysis_rows_per_sec NUMERIC,
    processing_rows_per_sec NUMERIC
) ON COMMIT PRESERVE ROWS;

-- Per year jobs for hovedenhet (LU)
WITH def AS (SELECT id FROM public.import_definition WHERE slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, edit_comment)
SELECT def.id, 'import_lu_2015_bench', '2015-01-01'::DATE, 'infinity'::DATE,
       'Benchmark LU 2015', 'Benchmark test', 'LU 2015'
FROM def;

WITH def AS (SELECT id FROM public.import_definition WHERE slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, edit_comment)
SELECT def.id, 'import_lu_2016_bench', '2016-01-01'::DATE, 'infinity'::DATE,
       'Benchmark LU 2016', 'Benchmark test', 'LU 2016'
FROM def;

WITH def AS (SELECT id FROM public.import_definition WHERE slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, edit_comment)
SELECT def.id, 'import_lu_2017_bench', '2017-01-01'::DATE, 'infinity'::DATE,
       'Benchmark LU 2017', 'Benchmark test', 'LU 2017'
FROM def;

WITH def AS (SELECT id FROM public.import_definition WHERE slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, edit_comment)
SELECT def.id, 'import_lu_2018_bench', '2018-01-01'::DATE, 'infinity'::DATE,
       'Benchmark LU 2018', 'Benchmark test', 'LU 2018'
FROM def;

-- Per year jobs for underenhet (ES)
WITH def AS (SELECT id FROM public.import_definition WHERE slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, edit_comment)
SELECT def.id, 'import_es_2015_bench', '2015-01-01'::DATE, 'infinity'::DATE,
       'Benchmark ES 2015', 'Benchmark test', 'ES 2015'
FROM def;

WITH def AS (SELECT id FROM public.import_definition WHERE slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, edit_comment)
SELECT def.id, 'import_es_2016_bench', '2016-01-01'::DATE, 'infinity'::DATE,
       'Benchmark ES 2016', 'Benchmark test', 'ES 2016'
FROM def;

WITH def AS (SELECT id FROM public.import_definition WHERE slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, edit_comment)
SELECT def.id, 'import_es_2017_bench', '2017-01-01'::DATE, 'infinity'::DATE,
       'Benchmark ES 2017', 'Benchmark test', 'ES 2017'
FROM def;

WITH def AS (SELECT id FROM public.import_definition WHERE slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, edit_comment)
SELECT def.id, 'import_es_2018_bench', '2018-01-01'::DATE, 'infinity'::DATE,
       'Benchmark ES 2018', 'Benchmark test', 'ES 2018'
FROM def;

-- Load all LU data first (upload order determines processing priority)
\echo 'Loading LU data (oldest first)'
\copy public.import_lu_2015_bench_upload FROM 'samples/norway/small-history/2015-enheter.csv' WITH CSV HEADER
\copy public.import_lu_2016_bench_upload FROM 'samples/norway/small-history/2016-enheter.csv' WITH CSV HEADER
\copy public.import_lu_2017_bench_upload FROM 'samples/norway/small-history/2017-enheter.csv' WITH CSV HEADER
\copy public.import_lu_2018_bench_upload FROM 'samples/norway/small-history/2018-enheter.csv' WITH CSV HEADER

-- Load all ES data after LU (ES depends on LU external_idents)
\echo 'Loading ES data (oldest first, AFTER all LU)'
\copy public.import_es_2015_bench_upload FROM 'samples/norway/small-history/2015-underenheter.csv' WITH CSV HEADER
\copy public.import_es_2016_bench_upload FROM 'samples/norway/small-history/2016-underenheter.csv' WITH CSV HEADER
\copy public.import_es_2017_bench_upload FROM 'samples/norway/small-history/2017-underenheter.csv' WITH CSV HEADER
\copy public.import_es_2018_bench_upload FROM 'samples/norway/small-history/2018-underenheter.csv' WITH CSV HEADER

\echo 'Jobs created and data loaded'
SELECT slug, state, total_rows FROM public.import_job WHERE slug LIKE 'import_%_bench' ORDER BY slug;

COMMIT;

-- ============================================================================
-- PHASE 2: PROCESSING (outside transaction - worker commits per task)
-- ============================================================================
\echo ''
\echo '================================================================================'
\echo 'IMPORT BENCHMARK: Performance Measurement with Query Profiling'
\echo '================================================================================'
\echo ''

-- Process all import jobs
\echo 'Processing all import jobs...'
CALL worker.process_tasks(p_queue => 'import');

-- ============================================================================
-- PHASE 3: COLLECT BENCHMARK RESULTS
-- ============================================================================
BEGIN;

\echo ''
\echo 'Collecting benchmark results...'

-- Insert timing data from import_job table
INSERT INTO benchmark_results (phase, job_slug, total_rows, analysis_ms, processing_ms, total_ms, analysis_rows_per_sec, processing_rows_per_sec)
SELECT
    CASE WHEN slug LIKE '%_lu_%' THEN 'LU' ELSE 'ES' END AS phase,
    slug,
    total_rows,
    ROUND(EXTRACT(EPOCH FROM (analysis_stop_at - analysis_start_at)) * 1000, 1) AS analysis_ms,
    ROUND(EXTRACT(EPOCH FROM (processing_stop_at - processing_start_at)) * 1000, 1) AS processing_ms,
    ROUND(EXTRACT(EPOCH FROM (processing_stop_at - analysis_start_at)) * 1000, 1) AS total_ms,
    analysis_rows_per_sec,
    import_rows_per_sec
FROM public.import_job
WHERE slug LIKE 'import_%_bench'
ORDER BY slug;

-- ============================================================================
-- DETERMINISTIC OUTPUT: Job states and row counts
-- ============================================================================
\echo ''
\echo '--- Job Completion Status (Deterministic) ---'
SELECT
    slug,
    state,
    total_rows,
    imported_rows,
    CASE WHEN error IS NOT NULL THEN 'ERROR' ELSE 'OK' END AS status
FROM public.import_job
WHERE slug LIKE 'import_%_bench'
ORDER BY slug;

\echo ''
\echo '--- Data Row States (Deterministic) ---'
SELECT state, count(*) AS count FROM public.import_lu_2015_bench_data GROUP BY state ORDER BY state;
SELECT state, count(*) AS count FROM public.import_lu_2016_bench_data GROUP BY state ORDER BY state;
SELECT state, count(*) AS count FROM public.import_lu_2017_bench_data GROUP BY state ORDER BY state;
SELECT state, count(*) AS count FROM public.import_lu_2018_bench_data GROUP BY state ORDER BY state;
SELECT state, count(*) AS count FROM public.import_es_2015_bench_data GROUP BY state ORDER BY state;
SELECT state, count(*) AS count FROM public.import_es_2016_bench_data GROUP BY state ORDER BY state;
SELECT state, count(*) AS count FROM public.import_es_2017_bench_data GROUP BY state ORDER BY state;
SELECT state, count(*) AS count FROM public.import_es_2018_bench_data GROUP BY state ORDER BY state;

\echo ''
\echo '--- Error Rows (Deterministic) ---'
SELECT row_id, state, errors FROM public.import_lu_2015_bench_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, state, errors FROM public.import_es_2015_bench_data WHERE state = 'error' ORDER BY row_id;

-- ============================================================================
-- SCALING ANALYSIS (Deterministic classification)
-- ============================================================================
\echo ''
\echo '--- Scaling Analysis (Deterministic) ---'
\echo 'Comparing LU vs ES performance to detect O(n²) regressions.'
\echo ''

-- Calculate aggregate stats per phase
CREATE TEMP VIEW phase_summary AS
SELECT
    phase,
    SUM(total_rows) AS total_rows,
    SUM(analysis_ms) AS analysis_ms,
    SUM(processing_ms) AS processing_ms,
    SUM(total_ms) AS total_ms,
    CASE WHEN SUM(analysis_ms) > 0 THEN ROUND(SUM(total_rows) / (SUM(analysis_ms) / 1000.0), 1) END AS analysis_rows_per_sec,
    CASE WHEN SUM(processing_ms) > 0 THEN ROUND(SUM(total_rows) / (SUM(processing_ms) / 1000.0), 1) END AS processing_rows_per_sec
FROM benchmark_results
GROUP BY phase;

-- Output scaling classification (deterministic)
SELECT
    phase,
    total_rows,
    CASE
        WHEN processing_rows_per_sec IS NULL THEN 'NO_DATA'
        WHEN processing_rows_per_sec >= 100 THEN 'OK'
        WHEN processing_rows_per_sec >= 50 THEN 'SLOW'
        ELSE 'VERY_SLOW'
    END AS processing_status,
    CASE
        WHEN analysis_rows_per_sec IS NULL THEN 'NO_DATA'
        WHEN analysis_rows_per_sec >= 100 THEN 'OK'
        WHEN analysis_rows_per_sec >= 50 THEN 'SLOW'
        ELSE 'VERY_SLOW'
    END AS analysis_status
FROM phase_summary
ORDER BY phase;

\echo ''
\echo 'See test/expected/performance/401_import_benchmark.perf for detailed timing.'
\echo 'Check PostgreSQL logs for AUTO EXPLAIN output of slow queries.'
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
SELECT '# Import Benchmark Performance Baseline (Small History ~40 rows)';
SELECT '# With AUTO EXPLAIN enabled for queries > 100ms';
SELECT '# Check PostgreSQL logs for detailed query plans';
SELECT '#';
SELECT '';
\pset tuples_only off
SELECT '# Per-job timing:' as "header";
SELECT
    job_slug,
    total_rows,
    ROUND(analysis_ms)::int AS analysis_ms,
    ROUND(processing_ms)::int AS processing_ms,
    ROUND(total_ms)::int AS total_ms,
    ROUND(analysis_rows_per_sec, 1) AS analysis_rows_per_sec,
    ROUND(processing_rows_per_sec, 1) AS processing_rows_per_sec
FROM benchmark_results
ORDER BY job_slug;

\pset tuples_only on
SELECT '';
\pset tuples_only off
SELECT '# Phase summary:' as "header";
SELECT
    phase,
    total_rows,
    ROUND(analysis_ms)::int AS analysis_ms,
    ROUND(processing_ms)::int AS processing_ms,
    ROUND(total_ms)::int AS total_ms,
    ROUND(analysis_rows_per_sec, 1) AS analysis_rows_per_sec,
    ROUND(processing_rows_per_sec, 1) AS processing_rows_per_sec
FROM phase_summary
ORDER BY phase;

\pset tuples_only on
SELECT '';
\pset tuples_only off
SELECT '# Detailed job info from import_job table:' as "header";
SELECT
    slug,
    state,
    total_rows,
    imported_rows,
    ROUND(analysis_rows_per_sec, 2) AS analysis_rows_per_sec,
    ROUND(import_rows_per_sec, 2) AS import_rows_per_sec,
    ROUND(EXTRACT(EPOCH FROM (analysis_stop_at - analysis_start_at)), 2) AS analysis_sec,
    ROUND(EXTRACT(EPOCH FROM (processing_stop_at - processing_start_at)), 2) AS processing_sec
FROM public.import_job
WHERE slug LIKE 'import_%_bench'
ORDER BY slug;

\o
\pset footer on
\pset tuples_only off

COMMIT;

-- ============================================================================
-- COLLECT pg_stat_monitor DATA (if available)
-- ============================================================================
BEGIN;

\set queries_file test/expected/performance/401_import_benchmark_queries.perf
\pset tuples_only on
\pset footer off
\o :queries_file
SELECT '# Slow Query Analysis from pg_stat_monitor';
SELECT '# Queries sorted by total execution time';
SELECT '#';
SELECT '';
\pset tuples_only off

-- Output top slow queries if pg_stat_monitor is available
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_monitor') THEN
        -- Create temp table with query stats
        CREATE TEMP TABLE temp_query_stats AS
        SELECT
            queryid::text,
            calls,
            ROUND(total_exec_time::numeric, 2) AS total_exec_time_ms,
            ROUND((total_exec_time / NULLIF(calls, 0))::numeric, 2) AS avg_exec_time_ms,
            rows,
            ROUND((shared_blks_hit + shared_blks_read)::numeric / NULLIF(calls, 0), 0) AS avg_blks_per_call,
            LEFT(regexp_replace(query, E'[\\n\\r]+', ' ', 'g'), 200) AS query_preview
        FROM pg_stat_monitor
        WHERE total_exec_time > 10  -- Only queries taking > 10ms total
        ORDER BY total_exec_time DESC
        LIMIT 30;
    ELSE
        CREATE TEMP TABLE temp_query_stats AS
        SELECT 
            'N/A'::text AS queryid,
            0::bigint AS calls,
            0::numeric AS total_exec_time_ms,
            0::numeric AS avg_exec_time_ms,
            0::bigint AS rows,
            0::numeric AS avg_blks_per_call,
            'pg_stat_monitor extension not available'::text AS query_preview
        WHERE false;
    END IF;
END;
$$;

SELECT '# Top queries by total execution time:' as "header";
SELECT * FROM temp_query_stats ORDER BY total_exec_time_ms DESC;

\o
\pset footer on
\pset tuples_only off

COMMIT;

-- ============================================================================
-- CLEANUP
-- ============================================================================
\echo 'Resuming background worker'
SELECT worker.resume();

\i test/cleanup_unless_persist_is_specified.sql

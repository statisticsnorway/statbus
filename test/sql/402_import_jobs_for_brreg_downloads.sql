BEGIN;

\i test/setup.sql

\echo "Setting up Statbus (Norway) and BRREG import definitions (2025)"
\i samples/norway/getting-started.sql
\i samples/norway/brreg/create-import-definition-hovedenhet-2025.sql
\i samples/norway/brreg/create-import-definition-underenhet-2025.sql

\echo "Switch to test admin user"
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Create import jobs for BRREG full download (2025)"
-- Create import job for hovedenhet (legal units)
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
    default_valid_to = 'infinity'::DATE;

-- Create import job for underenhet (establishments)
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
    default_valid_to = 'infinity'::DATE;

\echo "Verify import definitions exist"
SELECT slug, name, mode
  FROM public.import_definition
 WHERE slug IN ('brreg_hovedenhet_2025','brreg_underenhet_2025')
 ORDER BY slug;

\echo "Verify created import jobs (BRREG download)"
SELECT slug, state, default_valid_from, default_valid_to
  FROM public.import_job
 WHERE slug IN ('import_hovedenhet_2025', 'import_underenhet_2025')
 ORDER BY slug;

\echo "Loading data for BRREG full download from tmp/ files"
\copy public.import_hovedenhet_2025_upload FROM 'tmp/enheter.csv' WITH CSV HEADER
\copy public.import_underenhet_2025_upload FROM 'tmp/underenheter_filtered.csv' WITH CSV HEADER

\echo "Check import job state before calling worker"
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug IN ('import_hovedenhet_2025', 'import_underenhet_2025') ORDER BY slug;

\echo "Run worker to process import jobs"
CALL worker.process_tasks(p_queue => 'import');

\echo "Check the states of the import job tasks"
SELECT queue, t.command, state, error
  FROM worker.tasks AS t
  JOIN worker.command_registry AS c on t.command = c.command
 WHERE t.command = 'import_job_process'
 ORDER BY priority;

\echo "Check import job state after calling worker"
SELECT slug, state, error IS NOT NULL AS failed, total_rows, imported_rows, import_completed_pct, error as error_details
  FROM public.import_job
 WHERE slug IN ('import_hovedenhet_2025', 'import_underenhet_2025')
 ORDER BY slug;

\echo "Check data row states after import"
SELECT state, count(*) FROM public.import_hovedenhet_2025_data GROUP BY state;
SELECT state, count(*) FROM public.import_underenhet_2025_data GROUP BY state;

\echo "Show any error rows from import data tables"
SELECT row_id, errors, merge_status FROM public.import_hovedenhet_2025_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, errors, merge_status FROM public.import_underenhet_2025_data WHERE state = 'error' ORDER BY row_id;

\i test/rollback_unless_persist_is_specified.sql

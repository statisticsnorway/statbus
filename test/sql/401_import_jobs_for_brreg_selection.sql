BEGIN;

\i test/setup.sql

\echo "Setting up Statbus (Norway) and BRREG import definitions (2024)"
\i samples/norway/getting-started.sql
\i samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
\i samples/norway/brreg/create-import-definition-underenhet-2024.sql

\echo "Switch to test admin user"
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Create import jobs for BRREG selection (2025)"
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
ON CONFLICT (slug) DO NOTHING;

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
ON CONFLICT (slug) DO NOTHING;

\echo "Verify import definitions exist"
SELECT slug, name, mode
  FROM public.import_definition
 WHERE slug IN ('brreg_hovedenhet_2024','brreg_underenhet_2024')
 ORDER BY slug;

\echo "Verify created import jobs (BRREG selection)"
SELECT slug, state, default_valid_from, default_valid_to
  FROM public.import_job
 WHERE slug IN (
   'import_hovedenhet_2025_selection',
   'import_underenhet_2025_selection'
 )
 ORDER BY slug;

\echo "Loading data for BRREG selection from sample files"
\copy public.import_hovedenhet_2025_selection_upload FROM 'samples/norway/legal_unit/enheter-selection.csv' WITH CSV HEADER
\copy public.import_underenhet_2025_selection_upload FROM 'samples/norway/establishment/underenheter-selection.csv' WITH CSV HEADER

\echo "Check import job state before calling worker"
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug LIKE 'import_%_selection' ORDER BY slug;

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
 WHERE slug LIKE 'import_%_selection'
 ORDER BY slug;

\echo "Check data row states after import"
SELECT state, count(*) FROM public.import_hovedenhet_2025_selection_data GROUP BY state ORDER BY state;
SELECT state, count(*) FROM public.import_underenhet_2025_selection_data GROUP BY state ORDER BY state;

\echo "Show any error rows from import data tables"
SELECT row_id, errors, merge_status FROM public.import_hovedenhet_2025_selection_data WHERE state = 'error' ORDER BY row_id;
SELECT row_id, errors, merge_status FROM public.import_underenhet_2025_selection_data WHERE state = 'error' ORDER BY row_id;

\i test/rollback_unless_persist_is_specified.sql

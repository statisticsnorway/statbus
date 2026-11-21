-- usage: ./sb psql -d DB -v jobuser=EMAIL -f tmp/5vxfjm/run-import.sql
\set ON_ERROR_STOP 1
\timing on
SET datestyle TO 'ISO, DMY';
BEGIN;
SELECT auth.set_user_context_from_email('test.admin@statbus.org');
SET LOCAL ROLE "test.admin@statbus.org";
\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\i samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
\i samples/norway/brreg/create-import-definition-underenhet-2024.sql
\o
COMMIT;
BEGIN;
SELECT auth.set_user_context_from_email(:'jobuser');
SET LOCAL ROLE :"jobuser";
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, review)
SELECT id, 'lu_sel', '2025-01-01', 'infinity', 'LU selection', false FROM public.import_definition WHERE slug='brreg_hovedenhet_2024'
RETURNING id, slug, (SELECT email FROM auth.user WHERE id=user_id) AS job_user;
\copy public.lu_sel_upload FROM 'samples/norway/legal_unit/enheter-selection.csv' WITH CSV HEADER
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, review)
SELECT id, 'es_sel', '2025-01-01', 'infinity', 'ES selection', false FROM public.import_definition WHERE slug='brreg_underenhet_2024'
RETURNING id, slug;
\copy public.es_sel_upload FROM 'samples/norway/establishment/underenheter-selection.csv' WITH CSV HEADER
COMMIT;
RESET ROLE;
SELECT set_config('request.jwt.claims', '', false);
\set ON_ERROR_STOP 0
SELECT clock_timestamp() AS t0 \gset
CALL worker.process_tasks(p_queue => 'import');
SELECT clock_timestamp() - :'t0'::timestamptz AS import_wall;
SELECT slug, state, total_rows, imported_rows, error FROM public.import_job ORDER BY id;

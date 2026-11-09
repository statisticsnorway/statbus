\set ON_ERROR_STOP on
-- Keep test user claims alive for the fixture session, as in SQL380.
BEGIN;
\i test/setup.sql
CALL test.set_user_from_email('test.admin@statbus.org');
\i samples/norway/getting-started.sql
-- Fixture-only SQL worker calls finish before any measured jobs are created.
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_mixed_seed_lu', 'Mixed seed LU', 'Benchmark fixture', false, 50
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_mixed_seed_lu_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
SELECT '2020-01-01', 'infinity', (591000000 + n)::text, 'Mixed LU ' || n || ' 2020', '2100', 'AS', 'brreg'
FROM generate_series(1, 200) AS n;
CALL worker.process_tasks(p_queue => 'import');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_mixed_seed_es', 'Mixed seed formal ES', 'Benchmark fixture', false, 50
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
INSERT INTO public.import_mixed_seed_es_upload
    (valid_from, valid_to, tax_ident, legal_unit_tax_ident, name, data_source_code)
SELECT '2020-01-01', 'infinity', (591100000 + n)::text,
       (591000000 + ((n - 1) % 200) + 1)::text, 'Mixed ES ' || n || ' 2020', 'brreg'
FROM generate_series(1, 400) AS n;
CALL worker.process_tasks(p_queue => 'import');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_mixed_seed_informal', 'Mixed seed informal ES', 'Benchmark fixture', false, 50
FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';
INSERT INTO public.import_mixed_seed_informal_upload (valid_from, valid_to, tax_ident, name, data_source_code)
SELECT '2020-01-01', 'infinity', (591200000 + n)::text, 'Mixed informal ' || n || ' 2020', 'brreg'
FROM generate_series(1, 200) AS n;
CALL worker.process_tasks(p_queue => 'import');
-- Fail before measured uploads if fixture preparation did not produce exact seeds.
DO LANGUAGE plpgsql $mixed_seed_check$
BEGIN
    IF (SELECT count(*) FROM public.import_job AS job
        JOIN (VALUES ('import_mixed_seed_lu', 200), ('import_mixed_seed_es', 400),
                     ('import_mixed_seed_informal', 200)) AS expected(slug, rows) USING (slug)
        WHERE job.state = 'finished' AND job.total_rows = expected.rows
          AND job.imported_rows = expected.rows AND job.error_count = 0) <> 3 THEN
        RAISE EXCEPTION 'Mixed fixture seed imports did not finish exact input rows';
    END IF;
END;
$mixed_seed_check$;
-- Valid shared enterprise dependencies, identified by logical names, before analysis.
UPDATE public.legal_unit SET enterprise_id =
    (SELECT enterprise_id FROM public.legal_unit WHERE name = 'Mixed LU 1 2020'),
    primary_for_enterprise = false WHERE name = 'Mixed LU 2 2020';
UPDATE public.establishment SET enterprise_id =
    (SELECT enterprise_id FROM public.establishment WHERE name = 'Mixed informal 1 2020'),
    primary_for_enterprise = false WHERE name = 'Mixed informal 2 2020';
-- Only uploads below: the actual Crystal worker analyses and processes every row.
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_mixed_lu', 'Mixed LU histories', 'Benchmark measured', false, 50
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_mixed_lu_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
SELECT y || '-01-01', CASE WHEN y = 2022 THEN 'infinity' ELSE y || '-12-31' END,
       (591000000 + n)::text, 'Mixed LU ' || n || ' ' || y, '2100', 'AS', 'brreg'
FROM generate_series(2021, 2022) AS y CROSS JOIN generate_series(1, 400) AS n ORDER BY y, n;
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_mixed_es', 'Mixed formal histories', 'Benchmark measured', false, 50
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
INSERT INTO public.import_mixed_es_upload
    (valid_from, valid_to, tax_ident, legal_unit_tax_ident, name, data_source_code)
SELECT y || '-01-01', CASE WHEN y = 2022 THEN 'infinity' ELSE y || '-12-31' END,
       (591100000 + n)::text,
       (591000000 + CASE WHEN n <= 400 THEN ((n - 1) % 200) + 1 ELSE ((n - 401) % 200) + 201 END)::text,
       'Mixed ES ' || n || ' ' || y, 'brreg'
FROM generate_series(2021, 2022) AS y CROSS JOIN generate_series(1, 800) AS n ORDER BY y, n;
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_mixed_informal', 'Mixed informal histories', 'Benchmark measured', false, 50
FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';
INSERT INTO public.import_mixed_informal_upload (valid_from, valid_to, tax_ident, name, data_source_code)
SELECT y || '-01-01', CASE WHEN y = 2022 THEN 'infinity' ELSE y || '-12-31' END,
       (591200000 + n)::text, 'Mixed informal ' || n || ' ' || y, 'brreg'
FROM generate_series(2021, 2022) AS y CROSS JOIN generate_series(1, 400) AS n ORDER BY y, n;
COMMIT;

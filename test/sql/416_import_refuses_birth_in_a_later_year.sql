BEGIN;

\i test/setup.sql

-- f2gx3m: an import row whose birth_date is in a later calendar year than its valid_from is an error
-- on that row, with a message naming both dates (import.analyse_date_consistency). A birth_date
-- later in the same year stays valid: the unit is counted from its birth (public.unit_existence_from).
-- jo's establishment 86 had valid_from 2023-01-01 and birth_date 2024-11-01.

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_f2gx3m_lu', 'Test 416 legal units', 'Test 416 (f2gx3m)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';

INSERT INTO public.import_f2gx3m_lu_upload (valid_from, valid_to, tax_ident, name, birth_date, death_date) VALUES
    ('2023-01-01', 'infinity',   '416000001', 'Born a later year',        '2024-11-01', NULL),
    ('2023-01-01', 'infinity',   '416000002', 'Born later the same year', '2023-11-01', NULL),
    ('2023-01-01', 'infinity',   '416000003', 'Born an earlier year',     '1924-11-01', NULL),
    ('2023-01-01', 'infinity',   '416000004', 'No birth date',            NULL,         NULL);

CALL worker.process_tasks(p_queue => 'import');

\echo
\echo "416.1 the job finishes; only the row born a later year is skipped"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_job_error
FROM public.import_job WHERE slug = 'import_f2gx3m_lu';

\echo "416.2 each row's state, action and errors, key and message"
SELECT dt.row_id, dt.name_raw, dt.state, dt.action, e.key, e.value
FROM public.import_f2gx3m_lu_data AS dt
LEFT JOIN LATERAL jsonb_each_text(dt.errors) AS e(key, value) ON TRUE
ORDER BY dt.row_id, e.key;

ROLLBACK;

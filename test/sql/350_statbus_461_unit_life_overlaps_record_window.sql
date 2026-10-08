BEGIN;

\i test/setup.sql

\echo "Test 350 (STATBUS-461): a unit's life must overlap the validity window of every record that claims it"
\echo
\echo "Rule (overlap, NOT containment): a row is rejected iff its unit cannot exist"
\echo "anywhere inside the row's window [valid_from, valid_until):"
\echo "  birth_date >= valid_until  (born on or after the window ends), or"
\echo "  death_date <= valid_from   (died on or before the window starts)."
\echo "birth_date > valid_from and death_date < valid_until stay legal (born or died"
\echo "inside the window). A rejected row gets state=error, action=skip and an errors"
\echo "entry keyed by the source_input columns at fault; every other row in the same"
\echo "file still imports and the job still finishes."
\echo
\echo "Fixtures: test/data/461_date_consistency_*.csv hold the violating AND the valid"
\echo "rows together, so one import proves both the rejection and the acceptance."

CALL test.set_user_from_email('test.admin@statbus.org');

-- Suppress the verbatim echo of the shared include (STATBUS-175 pattern).
\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\o
\set ECHO all

\echo
\echo "=== Step registration: the date_consistency step exists ==="
SELECT code, name, priority, analyse_procedure::text, process_procedure::text, is_holistic
FROM public.import_step WHERE code = 'date_consistency';

\echo
\echo "=== Step linkage: every definition that imports units (a legal_unit or establishment step) carries it ==="
SELECT d.slug,
       d.valid_time_from,
       d.mode,
       EXISTS (
           SELECT 1 FROM public.import_definition_step AS ds
           JOIN public.import_step AS s ON s.id = ds.step_id
           WHERE ds.definition_id = d.id AND s.code = 'date_consistency'
       ) AS has_date_consistency
FROM public.import_definition AS d
ORDER BY d.slug;

\echo
\echo "=== Step order for a unit definition (analysis runs in this order) ==="
SELECT s.priority, s.code
FROM public.import_definition_step AS ds
JOIN public.import_step AS s ON s.id = ds.step_id
JOIN public.import_definition AS d ON d.id = ds.definition_id
WHERE d.slug = 'legal_unit_source_dates' AND s.priority <= 20
ORDER BY s.priority;


-- ═════════════════════════════════════════════════════════════════════════
-- Part A: legal units, source dates. The full variation matrix (C01..C15).
-- ═════════════════════════════════════════════════════════════════════════

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT id, 'import_461_lu', 'Test 350 legal units', 'test/data/461_date_consistency_legal_units.csv', 'Test 350 (STATBUS-461)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';

\copy public.import_461_lu_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date) FROM 'test/data/461_date_consistency_legal_units.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');

\echo
\echo "A1 job reaches finished (a hard row error must not fail the job):"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_job_error
FROM public.import_job WHERE slug = 'import_461_lu';

\echo "A2 row-state counts (the skipped rows are visible as error):"
SELECT get_import_job_progress(id)->'row_states' AS row_states
FROM public.import_job WHERE slug = 'import_461_lu';

\echo "A3 every row: outcome and which error keys it carries"
SELECT row_id, tax_ident_raw, name_raw, valid_from_raw, valid_to_raw, birth_date_raw, death_date_raw,
       state, action,
       ARRAY(SELECT jsonb_object_keys(errors) ORDER BY 1) AS error_keys
FROM public.import_461_lu_data
ORDER BY row_id;

\echo "A4 the exact error messages, key for key (the text is asserted verbatim):"
SELECT dt.row_id, e.key, e.value
FROM public.import_461_lu_data AS dt
CROSS JOIN LATERAL jsonb_each_text(dt.errors) AS e(key, value)
ORDER BY dt.row_id, e.key;

CALL worker.process_tasks(p_queue => 'analytics');

\echo "A5 target table: legal_unit rows per identifier in statistical_unit (0 = absent)"
SELECT ids.tax_ident,
       ids.expectation,
       count(su.unit_id) AS statistical_unit_rows,
       string_agg(su.valid_from || '..' || su.valid_to
                  || ' born ' || COALESCE(su.birth_date::text, '-')
                  || ' died ' || COALESCE(su.death_date::text, '-'), '; ' ORDER BY su.valid_from) AS slices
FROM (VALUES
    ('461000001', 'C01 reject'),
    ('461000002', 'C02 reject'),
    ('461000003', 'C03 reject'),
    ('461000004', 'C04 reject'),
    ('461000005', 'C05 reject'),
    ('461000006', 'C06 accept'),
    ('461000007', 'C07 accept'),
    ('461000008', 'C08 accept'),
    ('461000009', 'C09 accept'),
    ('461000010', 'C10a accept'),
    ('461000011', 'C10b reject'),
    ('461000012', 'C11a accept'),
    ('461000013', 'C11b reject'),
    ('461000014', 'C12 accept'),
    ('461000015', 'C13 accept'),
    ('461000016', 'C14a 2023 reject, 2024 accept'),
    ('461000017', 'C14b 2023 accept, 2024 reject'),
    ('461000018', 'C14c 2024 accept, 2023 reject'),
    ('461000019', 'C15 reject (valid_time)')
) AS ids(tax_ident, expectation)
LEFT JOIN public.statistical_unit AS su
       ON su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = ids.tax_ident
GROUP BY ids.tax_ident, ids.expectation
ORDER BY ids.tax_ident;


-- ═════════════════════════════════════════════════════════════════════════
-- Part B: legal units, job-provided window (the job_provided definition kind).
-- ═════════════════════════════════════════════════════════════════════════

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, default_valid_from, default_valid_to, review)
SELECT id, 'import_461_lu_jp', 'Test 350 legal units, job provided window', 'Test 350 (STATBUS-461)', '2023-01-01', '2023-12-31', false
FROM public.import_definition WHERE slug = 'legal_unit_job_provided';

INSERT INTO public.import_461_lu_jp_upload(tax_ident, name, birth_date, death_date) VALUES
    ('461300001', 'J01 Born after job window', '2024-11-01', NULL),
    ('461300002', 'J02 Born inside job window', '2023-05-01', NULL),
    ('461300003', 'J03 Died before job window', NULL, '2022-12-31'),
    ('461300004', 'J04 Neither date', NULL, NULL);

CALL worker.process_tasks(p_queue => 'import');

\echo
\echo "B1 job and row-state counts:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_job_error,
       get_import_job_progress(id)->'row_states' AS row_states
FROM public.import_job WHERE slug = 'import_461_lu_jp';

\echo "B2 rows, keys and exact messages:"
SELECT dt.row_id, dt.name_raw, dt.state, dt.action, e.key, e.value
FROM public.import_461_lu_jp_data AS dt
LEFT JOIN LATERAL jsonb_each_text(dt.errors) AS e(key, value) ON TRUE
ORDER BY dt.row_id, e.key;


-- ═════════════════════════════════════════════════════════════════════════
-- Part C: informal establishments (establishment_without_lu_source_dates).
-- E01 is the shape of the shipped 'Drill Down / Drill Up' pair.
-- ═════════════════════════════════════════════════════════════════════════

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT id, 'import_461_eswlu', 'Test 350 informal establishments', 'test/data/461_date_consistency_informal_establishments.csv', 'Test 350 (STATBUS-461)', false
FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';

\copy public.import_461_eswlu_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date) FROM 'test/data/461_date_consistency_informal_establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- ═════════════════════════════════════════════════════════════════════════
-- Part D: formal establishments (establishment_for_lu_source_dates), linked to
-- legal unit 461000014 (C12, valid 2023-01-01..infinity).
-- ═════════════════════════════════════════════════════════════════════════

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT id, 'import_461_esflu', 'Test 350 formal establishments', 'test/data/461_date_consistency_formal_establishments.csv', 'Test 350 (STATBUS-461)', false
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';

\copy public.import_461_esflu_upload(valid_from,valid_to,tax_ident,name,legal_unit_tax_ident,birth_date,death_date) FROM 'test/data/461_date_consistency_formal_establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');

\echo
\echo "C1/D1 jobs and row-state counts:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_job_error,
       get_import_job_progress(id)->'row_states' AS row_states
FROM public.import_job WHERE slug IN ('import_461_eswlu', 'import_461_esflu')
ORDER BY slug;

\echo "C2 informal establishment rows, keys and exact messages:"
SELECT dt.row_id, dt.name_raw, dt.state, dt.action, e.key, e.value
FROM public.import_461_eswlu_data AS dt
LEFT JOIN LATERAL jsonb_each_text(dt.errors) AS e(key, value) ON TRUE
ORDER BY dt.row_id, e.key;

\echo "D2 formal establishment rows, keys and exact messages:"
SELECT dt.row_id, dt.name_raw, dt.state, dt.action, e.key, e.value
FROM public.import_461_esflu_data AS dt
LEFT JOIN LATERAL jsonb_each_text(dt.errors) AS e(key, value) ON TRUE
ORDER BY dt.row_id, e.key;

CALL worker.process_tasks(p_queue => 'analytics');

\echo "C3/D3 target table: establishment rows per identifier in statistical_unit (0 = absent)"
SELECT ids.tax_ident,
       ids.expectation,
       count(su.unit_id) AS statistical_unit_rows,
       string_agg(su.name || ' ' || su.valid_from || '..' || su.valid_to
                  || ' born ' || COALESCE(su.birth_date::text, '-')
                  || ' died ' || COALESCE(su.death_date::text, '-'), '; ' ORDER BY su.valid_from) AS slices
FROM (VALUES
    ('461100001', 'E01 2023 reject, 2024 accept'),
    ('461100002', 'E02 reject'),
    ('461100003', 'E03 accept'),
    ('461100004', 'E04 accept'),
    ('461200001', 'F01 2023 reject, 2024 accept'),
    ('461200002', 'F02 accept'),
    ('461200003', 'F03 reject')
) AS ids(tax_ident, expectation)
LEFT JOIN public.statistical_unit AS su
       ON su.unit_type = 'establishment' AND su.external_idents->>'tax_ident' = ids.tax_ident
GROUP BY ids.tax_ident, ids.expectation
ORDER BY ids.tax_ident;


-- ═════════════════════════════════════════════════════════════════════════
-- Part E: the documented scan, across every unit type.
-- ═════════════════════════════════════════════════════════════════════════

\echo
\echo "E1 documented scan: rows whose unit life cannot overlap the row window (expect 0 per unit type)"
SELECT unit_type,
       count(*) AS rows,
       count(*) FILTER (WHERE birth_date >= valid_until OR death_date <= valid_from) AS violators
FROM public.statistical_unit
GROUP BY unit_type
ORDER BY unit_type;

ROLLBACK;

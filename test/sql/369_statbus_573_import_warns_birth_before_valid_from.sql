BEGIN;

\i test/setup.sql

\echo "Test 369 (STATBUS-573): the import warns when a unit's timeline starts after its birth date in the same year"
\echo
\echo "History counts a birth only when a unit's existence starts at its birth_date (STATBUS-558, rule C)."
\echo "A unit born 2023-03-01 but first recorded from 2023-05-07 enters the stock in May as added, never as born."
\echo "The import marks such a row with a warning under birth_date_raw so the user can set valid_from to the"
\echo "birth date. The row still imports. Only the piece that starts the unit's timeline is warned: a later"
\echo "piece of the same unit, in the file or already stored, starts after an earlier piece by design."

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\o
\set ECHO all

-- ═════════════════════════════════════════════════════════════════════════
-- Part A: legal units, source dates.
-- ═════════════════════════════════════════════════════════════════════════

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT id, 'import_573_lu', 'Test 369 legal units', 'test/data/573_birth_before_valid_from_legal_units.csv', 'Test 369 (STATBUS-573)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';

\copy public.import_573_lu_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date) FROM 'test/data/573_birth_before_valid_from_legal_units.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');

\echo
\echo "A1 the job finishes and imports every row (a warning does not skip a row):"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_job_error
FROM public.import_job WHERE slug = 'import_573_lu';

\echo "A2 every row: state, action and its warnings, key and message"
\echo "   W01 and W10 start their unit's timeline after a birth earlier in the same year: warned."
\echo "   W05 and W06: only the first piece of the unit (W06 regardless of its order in the file)."
\echo "   W02 born the year before, W03 born on valid_from, W04 born after, W07 no birth date,"
\echo "   W08 exists from its birth: not warned."
SELECT dt.row_id, dt.tax_ident_raw, dt.name_raw, dt.valid_from_raw, dt.birth_date_raw, dt.state, dt.action,
       e.key AS warning_key, e.value AS warning
FROM public.import_573_lu_data AS dt
LEFT JOIN LATERAL jsonb_each_text(dt.warnings) AS e(key, value) ON TRUE
ORDER BY dt.row_id, e.key;

-- ═════════════════════════════════════════════════════════════════════════
-- Part B: a second file. W08 already exists from its birth, so its later piece is not the start of its
-- timeline. W10 gets the missing first piece from its birth date, which is what the warning asks for.
-- ═════════════════════════════════════════════════════════════════════════

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT id, 'import_573_lu_update', 'Test 369 legal units, second file', 'test/data/573_birth_before_valid_from_legal_units_update.csv', 'Test 369 (STATBUS-573)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';

\copy public.import_573_lu_update_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date) FROM 'test/data/573_birth_before_valid_from_legal_units_update.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');

\echo
\echo "B1 the second job finishes and imports every row:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_job_error
FROM public.import_job WHERE slug = 'import_573_lu_update';

\echo "B2 no row of the second file is warned: W08's piece follows its stored timeline, W09 is born on"
\echo "   valid_from, W10's new first piece starts at its birth date."
SELECT dt.row_id, dt.tax_ident_raw, dt.name_raw, dt.valid_from_raw, dt.birth_date_raw, dt.state, dt.action,
       dt.warnings
FROM public.import_573_lu_update_data AS dt
ORDER BY dt.row_id;

CALL worker.process_tasks(p_queue => 'analytics');

\echo
\echo "B3 history for legal units, months of 2023. Added in May: W01, W02, W03, W05, W06, W07 (6); born in May"
\echo "   only W03 (born on valid_from). Born in March: W08 and W10 (W10 now starts at its birth date). January: W09."
\echo "   June: W04 born after valid_from (added and born). W01 stays added, not born, until its row is corrected."
SELECT month, exists_added_count, births
FROM public.statistical_history
WHERE resolution = 'year-month' AND year = 2023 AND unit_type = 'legal_unit'
  AND (exists_added_count <> 0 OR births <> 0)
ORDER BY month;

-- ═════════════════════════════════════════════════════════════════════════
-- Part C: informal establishments get the same warning.
-- ═════════════════════════════════════════════════════════════════════════

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT id, 'import_573_eswlu', 'Test 369 informal establishments', 'test/data/573_birth_before_valid_from_informal_establishments.csv', 'Test 369 (STATBUS-573)', false
FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';

\copy public.import_573_eswlu_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date) FROM 'test/data/573_birth_before_valid_from_informal_establishments.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');

\echo
\echo "C1 job and rows: E01 warned, E02 not"
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug = 'import_573_eswlu';
SELECT dt.row_id, dt.tax_ident_raw, dt.name_raw, dt.state, dt.action, e.key AS warning_key, e.value AS warning
FROM public.import_573_eswlu_data AS dt
LEFT JOIN LATERAL jsonb_each_text(dt.warnings) AS e(key, value) ON TRUE
ORDER BY dt.row_id, e.key;

ROLLBACK;

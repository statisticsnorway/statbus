BEGIN;

\i test/setup.sql

\echo "Test 347: Import field length limits (truncate+warn descriptive overflows, hard-fail identifier overflows)"
\echo
\echo "Pre-fix (before import.analyse_length_limits): a legal_unit import row with"
\echo "physical_address_part1 > 200 chars would abort the entire batch at process-step"
\echo "MERGE time with '22001 string_data_right_truncation'. The import.process_location"
\echo "EXCEPTION WHEN OTHERS handler caught + re-threw, killing the whole job for one"
\echo "overlong field in one row. Albania-shaped 500-char addresses were the canonical"
\echo "failure case."
\echo
\echo "Post-fix (this test): analyse_length_limits runs at priority 105 (after all other"
\echo "analyses, before any process step's MERGE). Descriptive columns (legal_unit.name,"
\echo "location.address_*, contact.email_address, etc) get truncated with a warning"
\echo "recorded in dt.warnings. Identifier columns (external_ident.ident, varchar(50))"
\echo "hard-fail: state=error, errors populated, row NOT UPSERTed (identifier truncation"
\echo "would silently change the operator's primary key — data-corruption pathway)."

CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

-- Confirm the analyse_length_limits step is wired into the import flow.
\echo
\echo "=== Step registration check ==="
SELECT code, priority, analyse_procedure::text, process_procedure::text, is_holistic
FROM public.import_step WHERE code = 'analyse_length_limits';


-- ─── C1: At-limit value (no truncation) ──────────────────────────────────

SAVEPOINT scenario_c1;
\echo
\echo "=== C1: At-limit value (200 chars in physical_address_part1) ==="
\echo "Expectation: row stored with original 200-char value, zero warnings."

DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'imp_347_c1_atlimit', 'Test 347 C1 at-limit', '200-char address', 'Test 347');
END $$;

INSERT INTO public.imp_347_c1_atlimit_upload(
    valid_from, valid_to, tax_ident, name, birth_date, physical_address_part1,
    physical_country_iso_2, primary_activity_category_code, sector_code, legal_form_code
) VALUES
    ('2020-01-01', '2020-12-31', '347000001', 'C1 LU At Limit', '2020-01-01',
     repeat('a', 200), 'NO', '01.110', '2100', 'AS');

CALL worker.process_tasks(p_queue => 'import');

\echo "C1 job state:"
SELECT slug, state, total_rows, imported_rows
FROM public.import_job WHERE slug = 'imp_347_c1_atlimit';

\echo "C1 _data row warnings/errors/state:"
SELECT row_id, state,
       (warnings = '{}'::jsonb) AS warnings_empty,
       (errors   = '{}'::jsonb) AS errors_empty
FROM public.imp_347_c1_atlimit_data ORDER BY row_id;

\echo "C1 public.location address length:"
SELECT length(loc.address_part1) AS addr_len
FROM public.location loc
JOIN public.legal_unit lu ON lu.id = loc.legal_unit_id
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident = '347000001' AND loc.type = 'physical';

ROLLBACK TO SAVEPOINT scenario_c1;


-- ─── C2: Descriptive overflow (truncate + warn) ──────────────────────────

SAVEPOINT scenario_c2;
\echo
\echo "=== C2: Descriptive overflow (250 chars in physical_address_part1) ==="
\echo "Expectation: row stored, value truncated to 200, dt.warnings carries the"
\echo "truncation record, public.location.address_part1 length = 200."

DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'imp_347_c2_overflow', 'Test 347 C2 descriptive overflow', '250-char address', 'Test 347');
END $$;

INSERT INTO public.imp_347_c2_overflow_upload(
    valid_from, valid_to, tax_ident, name, birth_date, physical_address_part1,
    physical_country_iso_2, primary_activity_category_code, sector_code, legal_form_code
) VALUES
    ('2020-01-01', '2020-12-31', '347000002', 'C2 LU Overflow', '2020-01-01',
     repeat('b', 250), 'NO', '01.110', '2100', 'AS');

CALL worker.process_tasks(p_queue => 'import');

\echo "C2 job state:"
SELECT slug, state, total_rows, imported_rows
FROM public.import_job WHERE slug = 'imp_347_c2_overflow';

\echo "C2 _data row warnings (should contain physical_address_part1 truncation):"
SELECT row_id, state,
       warnings ? 'physical_address_part1' AS has_addr_warning,
       warnings #>> '{physical_address_part1,truncated_from}' AS truncated_from,
       warnings #>> '{physical_address_part1,to}' AS truncated_to,
       (errors = '{}'::jsonb) AS errors_empty
FROM public.imp_347_c2_overflow_data ORDER BY row_id;

\echo "C2 public.location address length (should be 200, not 250):"
SELECT length(loc.address_part1) AS addr_len
FROM public.location loc
JOIN public.legal_unit lu ON lu.id = loc.legal_unit_id
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident = '347000002' AND loc.type = 'physical';

ROLLBACK TO SAVEPOINT scenario_c2;


-- ─── C3: Multiple descriptive overflows in one row ───────────────────────

SAVEPOINT scenario_c3;
\echo
\echo "=== C3: Multiple descriptive overflows in one row ==="
\echo "Expectation: 250-char address + 60-char email — BOTH truncated, BOTH in warnings"
\echo "(one JSONB object, two keys)."

DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'imp_347_c3_multi', 'Test 347 C3 multiple overflows', '250-addr + 60-email', 'Test 347');
END $$;

INSERT INTO public.imp_347_c3_multi_upload(
    valid_from, valid_to, tax_ident, name, birth_date, physical_address_part1, email_address,
    physical_country_iso_2, primary_activity_category_code, sector_code, legal_form_code
) VALUES
    ('2020-01-01', '2020-12-31', '347000003', 'C3 LU Multi', '2020-01-01',
     repeat('c', 250), repeat('x', 50) || '@example.com',  -- 62 chars total
     'NO', '01.110', '2100', 'AS');

CALL worker.process_tasks(p_queue => 'import');

\echo "C3 _data row warnings (should contain BOTH columns):"
SELECT row_id, state,
       warnings ? 'physical_address_part1' AS has_addr,
       warnings ? 'email_address'          AS has_email,
       warnings #>> '{physical_address_part1,truncated_from}' AS addr_from,
       warnings #>> '{email_address,truncated_from}'          AS email_from,
       (errors = '{}'::jsonb) AS errors_empty
FROM public.imp_347_c3_multi_data ORDER BY row_id;

\echo "C3 public targets lengths (address=200, email=50):"
SELECT
    (SELECT length(loc.address_part1)
     FROM public.location loc
     JOIN public.legal_unit lu ON lu.id = loc.legal_unit_id
     JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
     WHERE ei.ident = '347000003' AND loc.type = 'physical') AS addr_len,
    (SELECT length(c.email_address)
     FROM public.contact c
     JOIN public.legal_unit lu ON lu.id = c.legal_unit_id
     JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
     WHERE ei.ident = '347000003') AS email_len;

ROLLBACK TO SAVEPOINT scenario_c3;


-- ─── C4: Identifier overflow (hard fail) ─────────────────────────────────

SAVEPOINT scenario_c4;
\echo
\echo "=== C4: Identifier overflow (60-char tax_ident, limit 50) ==="
\echo "Expectation: dt.state='error', dt.errors carries the too_long record,"
\echo "NO row in public.external_ident, NO row in public.legal_unit."

DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'imp_347_c4_idfail', 'Test 347 C4 identifier overflow', '60-char tax_ident', 'Test 347');
END $$;

INSERT INTO public.imp_347_c4_idfail_upload(
    valid_from, valid_to, tax_ident, name, birth_date,
    physical_country_iso_2, primary_activity_category_code, sector_code, legal_form_code
) VALUES
    ('2020-01-01', '2020-12-31', repeat('9', 60), 'C4 LU Id Overflow', '2020-01-01',
     'NO', '01.110', '2100', 'AS');

CALL worker.process_tasks(p_queue => 'import');

\echo "C4 _data row state + errors (state=error, errors has tax_ident_raw):"
SELECT row_id, state,
       errors ? 'tax_ident_raw' AS has_ident_error,
       errors #>> '{tax_ident_raw,too_long}' AS too_long,
       errors #>> '{tax_ident_raw,limit}'    AS limit_val
FROM public.imp_347_c4_idfail_data ORDER BY row_id;

\echo "C4 external_ident count for the 60-char ident (should be 0):"
SELECT count(*) AS ext_ident_count
FROM public.external_ident
WHERE ident = repeat('9', 60);

\echo "C4 legal_unit count for 60-char ident (should be 0):"
SELECT count(*) AS lu_count
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
WHERE ei.ident = repeat('9', 60);

ROLLBACK TO SAVEPOINT scenario_c4;


-- ─── C5: Albania-shaped row (500-char address — the original bug) ────────

SAVEPOINT scenario_c5;
\echo
\echo "=== C5: Albania-shaped row (500-char physical_address_part1) ==="
\echo "Pre-fix: this aborted the whole job with batch_error_process_location 22001."
\echo "Post-fix: row stores with address truncated to 200, warning emitted,"
\echo "job state='finished' (or 'analysing_failed' if it failed pre-fix)."

DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'imp_347_c5_albania', 'Test 347 C5 Albania 500-char', 'pre-fix killed whole job', 'Test 347');
END $$;

INSERT INTO public.imp_347_c5_albania_upload(
    valid_from, valid_to, tax_ident, name, birth_date, physical_address_part1,
    physical_country_iso_2, primary_activity_category_code, sector_code, legal_form_code
) VALUES
    ('2020-01-01', '2020-12-31', '347000005', 'C5 Albania-shape', '2020-01-01',
     repeat('A', 500), 'NO', '01.110', '2100', 'AS');

CALL worker.process_tasks(p_queue => 'import');

\echo "C5 job state (post-fix: should be finished, not failed):"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error
FROM public.import_job WHERE slug = 'imp_347_c5_albania';

\echo "C5 _data row (address truncated 500→200, warning recorded):"
SELECT row_id, state,
       warnings #>> '{physical_address_part1,truncated_from}' AS truncated_from,
       warnings #>> '{physical_address_part1,to}'             AS truncated_to,
       (errors = '{}'::jsonb) AS errors_empty
FROM public.imp_347_c5_albania_data ORDER BY row_id;

\echo "C5 public.location.address_part1 length (should be 200):"
SELECT length(loc.address_part1) AS addr_len
FROM public.location loc
JOIN public.legal_unit lu ON lu.id = loc.legal_unit_id
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
WHERE ei.ident = '347000005' AND loc.type = 'physical';

ROLLBACK TO SAVEPOINT scenario_c5;


-- ─── C6: Sanity — no false positives on normal rows ──────────────────────

SAVEPOINT scenario_c6;
\echo
\echo "=== C6: Sanity check — 5 normal rows, all sub-limit ==="
\echo "Expectation: zero warnings, zero errors, all 5 rows in public.legal_unit."

DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'imp_347_c6_normal', 'Test 347 C6 normal rows', 'no false positives', 'Test 347');
END $$;

INSERT INTO public.imp_347_c6_normal_upload(
    valid_from, valid_to, tax_ident, name, birth_date, physical_address_part1, email_address,
    physical_country_iso_2, primary_activity_category_code, sector_code, legal_form_code
) VALUES
    ('2020-01-01', '2020-12-31', '347000601', 'C6 LU One',   '2020-01-01', 'Short Street 1',  'one@ex.org',   'NO', '01.110', '2100', 'AS'),
    ('2020-01-01', '2020-12-31', '347000602', 'C6 LU Two',   '2020-01-01', 'Short Street 2',  'two@ex.org',   'NO', '01.110', '2100', 'AS'),
    ('2020-01-01', '2020-12-31', '347000603', 'C6 LU Three', '2020-01-01', 'Short Street 3',  'three@ex.org', 'NO', '01.110', '2100', 'AS'),
    ('2020-01-01', '2020-12-31', '347000604', 'C6 LU Four',  '2020-01-01', 'Short Street 4',  'four@ex.org',  'NO', '01.110', '2100', 'AS'),
    ('2020-01-01', '2020-12-31', '347000605', 'C6 LU Five',  '2020-01-01', 'Short Street 5',  'five@ex.org',  'NO', '01.110', '2100', 'AS');

CALL worker.process_tasks(p_queue => 'import');

\echo "C6 _data rows — all warnings/errors empty:"
SELECT count(*) AS total_rows,
       count(*) FILTER (WHERE warnings = '{}'::jsonb) AS no_warning_count,
       count(*) FILTER (WHERE errors   = '{}'::jsonb) AS no_error_count,
       count(*) FILTER (WHERE state = 'error') AS error_count
FROM public.imp_347_c6_normal_data;

\echo "C6 public.legal_unit count (should be 5):"
SELECT count(*) AS lu_count
FROM public.legal_unit lu
JOIN public.external_ident ei ON ei.legal_unit_id = lu.id
WHERE ei.ident LIKE '34700060%';

ROLLBACK TO SAVEPOINT scenario_c6;


ROLLBACK;

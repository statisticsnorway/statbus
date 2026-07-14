BEGIN;

\i test/setup.sql

\echo "=== Test 124: Duplicate Primary Controller — Import & Constraint (STATBUS-120) ==="
\echo "Covers the gap left by 117-121: two would-be PRIMARY controllers of the SAME"
\echo "type on ONE influenced unit at overlapping time. The predicated temporal"
\echo "exclusion legal_relationship_influenced_primary_excl must reject the second."
\echo "Sections: (1) direct-INSERT constraint, (2) duplicate-primary import batch,"
\echo "(3) mixed batch — valid edges must import while only the conflict is rejected."

-- Deterministic power_group idents
ALTER SEQUENCE public.power_group_ident_seq RESTART WITH 1;

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

-- Load base configuration (regions, status codes, import definitions, etc.)
\i samples/norway/getting-started.sql

-- Seed relationship types demonstrating primary_influencer_only semantics.
-- HFOR (parent company): structurally 1:1 per subsidiary → primary_influencer_only=TRUE.
-- DTPR (partner, pro-rata): 1:N → FALSE (multiple allowed per influenced unit).
INSERT INTO public.legal_rel_type (code, name, description, primary_influencer_only, enabled, custom)
SELECT 'HFOR', 'Hovedforetak', 'Main enterprise / parent company (structurally 1:1)', TRUE, true, false
WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type WHERE code = 'HFOR');

INSERT INTO public.legal_rel_type (code, name, description, primary_influencer_only, enabled, custom)
SELECT 'DTPR', 'Partner (proratarisk)', 'Partner with pro-rata liability (multiple per entity)', FALSE, true, false
WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type WHERE code = 'DTPR');

-- ============================================================================
\echo "=== Section 0: Create legal units with tax_idents (import-resolvable) ==="
-- ============================================================================
-- Ctrl A / Ctrl B are two independent controllers; Target C is the influenced
-- unit both would control as a PRIMARY influencer (the conflict). Ctrl D / Target E
-- and Ctrl F / Target G are clean edges used to prove batch isolation in Section 3.

CREATE TEMP TABLE _lu_data (tax_ident text, lu_name text, ent_short text);
INSERT INTO _lu_data VALUES
    ('900000001', 'Ctrl A',   'DPC1'),
    ('900000002', 'Ctrl B',   'DPC2'),
    ('900000003', 'Target C', 'DPC3'),
    ('900000004', 'Ctrl D',   'DPC4'),
    ('900000005', 'Target E', 'DPC5'),
    ('900000006', 'Ctrl F',   'DPC6'),
    ('900000007', 'Target G', 'DPC7');

INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_comment)
SELECT d.ent_short, (SELECT id FROM auth.user LIMIT 1), 'Dup-primary test enterprise'
FROM _lu_data AS d
ORDER BY d.tax_ident;

INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date, d.lu_name, e.id, true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth.user LIMIT 1), 'Dup-primary test LU'
FROM _lu_data AS d
JOIN public.enterprise AS e ON e.short_name = d.ent_short
ORDER BY d.tax_ident;

INSERT INTO public.external_ident (type_id, shape, ident, legal_unit_id, edit_by_user_id, edit_comment)
SELECT
    (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident'),
    'regular'::external_ident_shape,
    d.tax_ident,
    lu.id,
    (SELECT id FROM auth.user LIMIT 1),
    'Dup-primary test tax_ident'
FROM _lu_data AS d
JOIN public.legal_unit AS lu ON lu.name = d.lu_name
ORDER BY d.tax_ident;

\echo "Legal units created with tax_idents:"
SELECT ei.ident AS tax_ident, lu.name
FROM public.legal_unit AS lu
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident LIKE '900000%'
ORDER BY ei.ident;

-- ============================================================================
\echo "=== Section 1: Direct INSERT — the exclusion constraint (isolated) ==="
-- ============================================================================
-- All of Section 1 runs under a SAVEPOINT that is rolled back, so the import
-- sections start with an EMPTY legal_relationship table for Target C.
SAVEPOINT section1;

\echo "1: The backing exclusion constraint on legal_relationship:"
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.legal_relationship'::regclass
  AND conname = 'legal_relationship_influenced_primary_excl';

\echo "1a: First PRIMARY controller Ctrl A -> Target C (HFOR) — succeeds"
INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Ctrl A'),
    (SELECT id FROM public.legal_unit WHERE name = 'Target C'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'HFOR'),
    100.00, (SELECT id FROM auth.user LIMIT 1), 'A is primary controller of C';

\echo "1b: Second PRIMARY controller Ctrl B -> Target C (HFOR, overlapping) — MUST be rejected"
SAVEPOINT dup_primary;
\set ON_ERROR_STOP off
INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Ctrl B'),
    (SELECT id FROM public.legal_unit WHERE name = 'Target C'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'HFOR'),
    100.00, (SELECT id FROM auth.user LIMIT 1), 'B is second primary of C - SHOULD FAIL';
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT dup_primary;

\echo "1b: Exactly one PRIMARY row exists for Target C (the second was rejected):"
SELECT count(*) AS primary_rows_for_C
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS lu ON lu.id = lr.influenced_id AND lu.name = 'Target C'
WHERE lr.primary_influencer_only IS TRUE;

\echo "1c: A NON-primary type (DTPR) allows MULTIPLE controllers of Target C — both succeed"
INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Ctrl B'),
    (SELECT id FROM public.legal_unit WHERE name = 'Target C'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'DTPR'),
    20.00, (SELECT id FROM auth.user LIMIT 1), 'B is a (non-primary) partner of C';
INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2020-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Ctrl D'),
    (SELECT id FROM public.legal_unit WHERE name = 'Target C'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'DTPR'),
    15.00, (SELECT id FROM auth.user LIMIT 1), 'D is another (non-primary) partner of C';

\echo "1c: Non-primary controllers of Target C (multiple allowed):"
SELECT count(*) AS nonprimary_rows_for_C
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS lu ON lu.id = lr.influenced_id AND lu.name = 'Target C'
WHERE lr.primary_influencer_only IS FALSE;

\echo "1d: A non-overlapping second PRIMARY (later period) is allowed — succeeds"
-- End A->C on 2022-12-31, then B->C primary from 2023 — no temporal overlap.
UPDATE public.legal_relationship AS lr SET valid_until = '2023-01-01'::date
FROM public.legal_unit AS a, public.legal_unit AS c
WHERE lr.influencing_id = a.id AND a.name = 'Ctrl A'
  AND lr.influenced_id = c.id AND c.name = 'Target C'
  AND lr.type_id = (SELECT id FROM public.legal_rel_type WHERE code = 'HFOR');
INSERT INTO public.legal_relationship (valid_from, influencing_id, influenced_id, type_id, percentage, edit_by_user_id, edit_comment)
SELECT '2023-01-01'::date,
    (SELECT id FROM public.legal_unit WHERE name = 'Ctrl B'),
    (SELECT id FROM public.legal_unit WHERE name = 'Target C'),
    (SELECT id FROM public.legal_rel_type WHERE code = 'HFOR'),
    100.00, (SELECT id FROM auth.user LIMIT 1), 'B becomes primary of C from 2023 (no overlap with A)';

\echo "1d: Two PRIMARY rows for Target C now exist across DISJOINT periods:"
SELECT a.name AS influencing, lr.valid_from, lr.valid_until
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS a ON a.id = lr.influencing_id
JOIN public.legal_unit AS c ON c.id = lr.influenced_id AND c.name = 'Target C'
WHERE lr.primary_influencer_only IS TRUE
ORDER BY lr.valid_from;

ROLLBACK TO SAVEPOINT section1;

-- ============================================================================
\echo "=== Section 2: IMPORT batch containing a duplicate-primary conflict ==="
-- ============================================================================
-- Two rows in ONE import batch each make a PRIMARY (HFOR) edge into Target C at
-- overlapping time. The STATBUS-178 analyse-layer detector (import.analyse_legal_relationship
-- STEP 3b) catches this at tier-1: an intra-batch conflict is ambiguous (a CSV carries no
-- principled ordering), so BOTH rows error with key 'duplicate_primary_controller',
-- action='skip'. The batch is NOT poisoned — the conflict never reaches the exclusion in
-- process, the job finishes cleanly (state='finished', NOT 'failed'). Here every row is a
-- conflict, so 0 rows import (correctly).
\echo "2: tier-1 detector — both duplicate-primary rows error per-row; the job finishes (not failed)"

-- review => false: run the pipeline to completion without a manual review pause, so
-- the batch's per-row outcome (which rows import, which error) is directly observable.
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT id, 'import_124_dup', 'Test 124: Duplicate primary controllers', 'Two HFOR primaries into Target C', 'Test 124 dup', false
FROM public.import_definition
WHERE slug = 'legal_relationship_source_dates';

INSERT INTO public.import_124_dup_upload(valid_from, valid_to, influencing_tax_ident, influenced_tax_ident, rel_type_code, percentage) VALUES
    ('2020-01-01', 'infinity', '900000001', '900000003', 'HFOR', '100'),
    ('2020-01-01', 'infinity', '900000002', '900000003', 'HFOR', '100');

CALL worker.process_tasks(p_queue => 'import');

\echo "2: Import job final state:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_job_error
FROM public.import_job WHERE slug = 'import_124_dup';

\echo "2: Per-row analysis (state / action / operation / error keys):"
SELECT row_id, state, action, operation,
       (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(errors) AS k) AS error_keys
FROM public.import_124_dup_data
ORDER BY row_id;

\echo "2: Resulting PRIMARY (HFOR) rows for Target C in legal_relationship (expect at most 1):"
SELECT count(*) AS primary_rows_for_C
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS c ON c.id = lr.influenced_id AND c.name = 'Target C'
WHERE lr.primary_influencer_only IS TRUE;

-- ============================================================================
\echo "=== Section 3: MIXED batch — valid edges alongside the conflict ==="
-- ============================================================================
-- The batch mixes two clean primary edges (Ctrl D->Target E, Ctrl F->Target G) with the
-- duplicate-primary conflict on Target C. This is the blast-radius test: tier-1 isolation
-- (STATBUS-178) imports the two valid edges while erroring ONLY the two conflicting C rows.
-- One dirty row no longer aborts the whole import (the pre-fix defect, STATBUS-120).
\echo "3: tier-1 isolation — D->E and F->G import; only the two Target C conflict rows error"

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT id, 'import_124_mixed', 'Test 124: Mixed valid + conflict', 'Two clean edges + duplicate-primary conflict', 'Test 124 mixed', false
FROM public.import_definition
WHERE slug = 'legal_relationship_source_dates';

INSERT INTO public.import_124_mixed_upload(valid_from, valid_to, influencing_tax_ident, influenced_tax_ident, rel_type_code, percentage) VALUES
    ('2020-01-01', 'infinity', '900000004', '900000005', 'HFOR', '100'),
    ('2020-01-01', 'infinity', '900000001', '900000003', 'HFOR', '100'),
    ('2020-01-01', 'infinity', '900000002', '900000003', 'HFOR', '100'),
    ('2020-01-01', 'infinity', '900000006', '900000007', 'HFOR', '100');

CALL worker.process_tasks(p_queue => 'import');

\echo "3: Import job final state:"
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_job_error
FROM public.import_job WHERE slug = 'import_124_mixed';

\echo "3: Per-row analysis (which rows imported vs. errored):"
SELECT row_id, influencing_tax_ident_raw AS influencing, influenced_tax_ident_raw AS influenced,
       state, action, operation,
       (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(errors) AS k) AS error_keys
FROM public.import_124_mixed_data
ORDER BY row_id;

\echo "3: Clean edges that landed in legal_relationship (Ctrl D->Target E, Ctrl F->Target G):"
SELECT a.name AS influencing, c.name AS influenced, t.code AS rel_type
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS a ON a.id = lr.influencing_id
JOIN public.legal_unit AS c ON c.id = lr.influenced_id
JOIN public.legal_rel_type AS t ON t.id = lr.type_id
WHERE c.name IN ('Target E', 'Target G')
ORDER BY a.name, c.name;

\echo "3: PRIMARY (HFOR) rows for Target C after mixed batch (expect at most 1):"
SELECT count(*) AS primary_rows_for_C
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS c ON c.id = lr.influenced_id AND c.name = 'Target C'
WHERE lr.primary_influencer_only IS TRUE;

\echo "=== Test 124: Duplicate Primary Controller Test Complete ==="

ROLLBACK;

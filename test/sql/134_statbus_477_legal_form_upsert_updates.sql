-- STATBUS-477 family A: legal_form upserts update existing rows, keyed on
-- (code, custom), so a system reload never overwrites a custom override.
--
-- The upsert triggers behind legal_form_custom_only (the getting-started
-- upload page), legal_form_custom and legal_form_system ended in
-- ON CONFLICT ... DO UPDATE ... WHERE legal_form.id = EXCLUDED.id, a no-op for
-- an identity id. Dropping only that predicate would conflict on
-- (enabled, code) and let a system reload overwrite the operator's custom
-- override; the fix conflicts on (code, custom).
--
-- Invariants checked, with a legal unit referencing the custom override:
--   1. Upload, correct, re-upload through legal_form_custom_only (the app
--      upload page): the correction lands on the same row and the statement
--      reports the row (RETURNING, COPY n).
--   2. The same through legal_form_custom.
--   3. A system reload (legal_form_system) of a code with an enabled custom
--      override updates the SYSTEM row only, leaves it disabled, and leaves
--      the custom override, its name and the legal unit's reference intact.
--   4. A system reload of a code without an override renames the system row
--      and does not re-enable it (the custom-only upload in 134.1 disabled
--      every system row on purpose; visibility is the operator's choice).
BEGIN;

\i test/setup.sql

\echo "Test 134: legal_form upserts update existing rows (STATBUS-477 family A)"

CALL test.set_user_from_email('test.admin@statbus.org');

\echo "134.1: the app upload view, legal_form_custom_only: upload, correct, re-upload"
INSERT INTO public.legal_form_custom_only(code, name)
VALUES ('ACO', 'Forening (first upload)')
RETURNING code, name;
INSERT INTO public.legal_form_custom_only(code, name)
VALUES ('ACO', 'Forening (corrected)')
RETURNING code, name;

CREATE TEMP TABLE probe AS
SELECT lf.id AS custom_aco_id
  FROM public.legal_form AS lf WHERE lf.code = 'ACO' AND lf.custom;

\copy public.legal_form_custom_only(code, name) FROM stdin WITH (FORMAT csv)
ACO,Forening (corrected via csv)
\.

SELECT lf.code, lf.custom, lf.enabled, lf.name
     , lf.id = (SELECT custom_aco_id FROM probe) AS same_row_as_first_upload
  FROM public.legal_form AS lf WHERE lf.code = 'ACO' ORDER BY lf.custom;

\echo "134.2: legal_form_custom: upload, correct, re-upload"
INSERT INTO public.legal_form_custom(code, name)
VALUES ('Q77', 'first')
RETURNING code, name;
INSERT INTO public.legal_form_custom(code, name)
VALUES ('Q77', 'second (corrected)')
RETURNING code, name;
SELECT lf.code, lf.custom, lf.enabled, lf.name
  FROM public.legal_form AS lf WHERE lf.code = 'Q77' ORDER BY lf.custom;

\echo "134.3: a system reload never overwrites the custom override (the wrong-key case)"
DO $$
DECLARE
    v_admin int; v_status int; v_ent int;
BEGIN
    SELECT id INTO v_admin FROM auth.user WHERE email = 'test.admin@statbus.org';
    SELECT id INTO v_status FROM public.status WHERE code = 'active';
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('E134', v_admin, now()) RETURNING id INTO v_ent;
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise,
                                   edit_by_user_id, edit_at, valid_from, legal_form_id)
    VALUES (v_ent, 'LU 134', v_status, true, v_admin, now(), '2023-01-01',
            (SELECT custom_aco_id FROM probe));
END $$;

RESET ROLE;
INSERT INTO public.legal_form_system(code, name)
VALUES ('ACO', 'Association/club/organisation (system reload)')
RETURNING code, name;

SELECT lf.code, lf.custom, lf.enabled, lf.name
     , lf.id = (SELECT custom_aco_id FROM probe) AS is_the_custom_override
  FROM public.legal_form AS lf WHERE lf.code = 'ACO' ORDER BY lf.custom;

SELECT lu.name AS legal_unit, lf.code, lf.custom, lf.name AS legal_form_name
  FROM public.legal_unit AS lu JOIN public.legal_form AS lf ON lf.id = lu.legal_form_id
 WHERE lu.name = 'LU 134';

SELECT lfo.code, lfo.name
  FROM public.legal_form_custom_only AS lfo WHERE lfo.code = 'ACO';

\echo "134.4: a system reload of a code without an override renames the system row, keeping it disabled"
INSERT INTO public.legal_form_system(code, name)
VALUES ('AUPS', 'Administrative Unit - Public Sector (renamed)')
RETURNING code, name;
SELECT lf.code, lf.custom, lf.enabled, lf.name
  FROM public.legal_form AS lf WHERE lf.code = 'AUPS' ORDER BY lf.custom;

\echo "134.5: one row per (code, custom)"
SELECT count(*) AS duplicate_keys
  FROM (SELECT code, custom FROM public.legal_form GROUP BY 1, 2 HAVING count(*) > 1) AS d;

ROLLBACK;

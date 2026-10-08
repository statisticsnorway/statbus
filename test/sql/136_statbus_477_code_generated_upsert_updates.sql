-- STATBUS-477 family B: code-generated upserts (data_source,
-- foreign_participation, unit_size, status) update existing rows on the real
-- key (code, custom), and the generator produces that shape for new tables.
--
-- Invariants checked:
--   1. Upload, correct, re-upload through data_source_custom (a getting-started
--      sample loads it): the correction lands and the statement reports rows.
--   2. With a legal unit referencing an operator's custom data_source
--      override, a system reload of that code (data_source_system) corrects
--      the SYSTEM row only, leaves it disabled, and leaves the override, its
--      name and the reference intact.
--   3. unit_size_system / foreign_participation_system reload an existing code
--      in place (no second system row); the custom views re-upload in place.
--   4. Each table has the (code, custom) key; status included (its views are
--      tested in STATBUS-478 once they accept inserts).
--   5. admin.generate_table_views_for_batch_api on a fresh code table produces
--      upserts that conflict on (code, custom) with no id predicate, the
--      (code, custom) key, and a working upload/correct/re-upload.
BEGIN;

\i test/setup.sql

\echo "Test 136: code-generated upserts update existing rows (STATBUS-477 family B)"

CALL test.set_user_from_email('test.admin@statbus.org');

\echo "136.1: data_source_custom: upload, correct, re-upload"
INSERT INTO public.data_source_custom(code, name) VALUES ('ntr', 'Skatteregisteret (first upload)') RETURNING code, name;
INSERT INTO public.data_source_custom(code, name) VALUES ('ntr', 'Skatteregisteret (corrected)') RETURNING code, name;
CREATE TEMP TABLE probe AS
SELECT ds.id AS custom_ntr_id FROM public.data_source AS ds WHERE ds.code = 'ntr' AND ds.custom;
\copy public.data_source_custom(code, name) FROM stdin WITH (FORMAT csv)
ntr,Skatteregisteret (corrected via csv)
\.
SELECT ds.code, ds.custom, ds.enabled, ds.name
     , ds.id = (SELECT custom_ntr_id FROM probe) AS same_row_as_first_upload
  FROM public.data_source AS ds WHERE ds.code = 'ntr' ORDER BY ds.custom;

\echo "136.2: a system reload never overwrites the custom override (the wrong-key case)"
DO $$
DECLARE
    v_admin int; v_status int; v_ent int;
BEGIN
    SELECT id INTO v_admin FROM auth.user WHERE email = 'test.admin@statbus.org';
    SELECT id INTO v_status FROM public.status WHERE code = 'active';
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('E136', v_admin, now()) RETURNING id INTO v_ent;
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise,
                                   edit_by_user_id, edit_at, valid_from, data_source_id)
    VALUES (v_ent, 'LU 136', v_status, true, v_admin, now(), '2023-01-01',
            (SELECT custom_ntr_id FROM probe));
END $$;
RESET ROLE;
INSERT INTO public.data_source_system(code, name) VALUES ('ntr', 'National Tax Registry (system reload)') RETURNING code, name;
SELECT ds.code, ds.custom, ds.enabled, ds.name
     , ds.id = (SELECT custom_ntr_id FROM probe) AS is_the_custom_override
  FROM public.data_source AS ds WHERE ds.code = 'ntr' ORDER BY ds.custom;
SELECT lu.name AS legal_unit, ds.code, ds.custom, ds.name AS data_source_name
  FROM public.legal_unit AS lu JOIN public.data_source AS ds ON ds.id = lu.data_source_id
 WHERE lu.name = 'LU 136';

\echo "136.3: unit_size and foreign_participation reload and re-upload in place"
SELECT us.code AS unit_size_code FROM public.unit_size AS us ORDER BY us.id LIMIT 1 \gset
INSERT INTO public.unit_size_system(code, name) VALUES (:'unit_size_code', 'Tiny (system reload)') RETURNING code, name;
INSERT INTO public.unit_size_custom(code, name) VALUES ('q136', 'first') RETURNING code, name;
INSERT INTO public.unit_size_custom(code, name) VALUES ('q136', 'second (corrected)') RETURNING code, name;
SELECT us.code, us.custom, us.enabled, us.name
  FROM public.unit_size AS us WHERE us.code IN (:'unit_size_code', 'q136') ORDER BY us.code, us.custom;
SELECT fp.code AS fp_code FROM public.foreign_participation AS fp ORDER BY fp.id LIMIT 1 \gset
INSERT INTO public.foreign_participation_system(code, name) VALUES (:'fp_code', 'renamed by system reload') RETURNING code, name;
SELECT fp.code, fp.custom, fp.enabled, fp.name
  FROM public.foreign_participation AS fp WHERE fp.code = :'fp_code' ORDER BY fp.custom;
INSERT INTO public.foreign_participation_custom(code, name) VALUES ('q136', 'first') RETURNING code, name;
INSERT INTO public.foreign_participation_custom(code, name) VALUES ('q136', 'second (corrected)') RETURNING code, name;
SELECT fp.code, fp.custom, fp.enabled, fp.name
  FROM public.foreign_participation AS fp WHERE fp.code = 'q136';

\echo "136.4: every family B table has the (code, custom) key"
SELECT con.conrelid::regclass AS table_name, pg_get_constraintdef(con.oid) AS key
  FROM pg_catalog.pg_constraint AS con
 WHERE con.contype = 'u'
   AND con.conrelid IN ('public.data_source'::regclass, 'public.foreign_participation'::regclass
                      , 'public.unit_size'::regclass, 'public.status'::regclass)
   AND con.conname LIKE '%\_code\_custom\_key'
 ORDER BY con.conrelid::regclass::text;

\echo "136.5: the generator produces the fixed shape for a new code table"
CREATE TABLE public.probe_477_code
    ( id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY
    , code text NOT NULL
    , name text NOT NULL
    , enabled boolean NOT NULL
    , custom boolean NOT NULL
    , created_at timestamptz NOT NULL DEFAULT statement_timestamp()
    , updated_at timestamptz NOT NULL DEFAULT statement_timestamp()
    );
SET client_min_messages TO WARNING;
SELECT admin.generate_table_views_for_batch_api('public.probe_477_code');
RESET client_min_messages;
SELECT v.variant
     , substring(pg_get_functiondef(v.fn) from 'ON CONFLICT \([^)]*\)') AS conflict_target
     , pg_get_functiondef(v.fn) ~ 'EXCLUDED\.id' AS has_id_predicate
     , pg_get_functiondef(v.fn) ~ 'RETURN NEW' AS reports_rows
  FROM (VALUES ('custom', 'admin.upsert_probe_477_code_custom()'::regprocedure)
             , ('system', 'admin.upsert_probe_477_code_system()'::regprocedure)) AS v(variant, fn)
 ORDER BY 1;
SELECT conname, pg_get_constraintdef(oid) AS key
  FROM pg_catalog.pg_constraint
 WHERE conrelid = 'public.probe_477_code'::regclass AND conname = 'probe_477_code_code_custom_key';
INSERT INTO public.probe_477_code_system(code, name) VALUES ('a', 'system a') RETURNING code, name;
INSERT INTO public.probe_477_code_custom(code, name) VALUES ('a', 'custom a') RETURNING code, name;
INSERT INTO public.probe_477_code_custom(code, name) VALUES ('a', 'custom a (corrected)') RETURNING code, name;
INSERT INTO public.probe_477_code_system(code, name) VALUES ('a', 'system a (reloaded)') RETURNING code, name;
SELECT p.code, p.custom, p.enabled, p.name FROM public.probe_477_code AS p ORDER BY p.custom;

ROLLBACK;

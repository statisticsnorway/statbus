-- STATBUS-477 family C and the key-aware generators.
--
-- legal_rel_type, legal_reorg_type, person_role, power_group_type and
-- region_version each carry UNIQUE (code): one row per code, owned by one
-- kind. Their generated upserts conflicted on (enabled, code) with an
-- id = EXCLUDED.id predicate. The generators now derive the conflict target
-- from the identity key the table actually has.
--
-- Invariants checked:
--   1. Upload, correct, re-upload through each family C custom view: the
--      correction lands, the row is enabled, the statement reports the row.
--   2. The wrong-key case: after a custom upload disables the system rows, a
--      system reload of an existing code corrects it in place.
--   3. A code owned by the other kind is refused with an actionable error.
--   4. A collision on the second unique key (person_role.name) is reported
--      with the code, the colliding value and what the operator can do.
--   5. Key-aware generator, both directions: a fresh code table keyed on
--      UNIQUE (code) gets ON CONFLICT (code); a fresh code table with custom
--      and no code key gets ON CONFLICT (code, custom) and that key, so the
--      family B fix holds; family B's tables still resolve (code, custom).
BEGIN;

\i test/setup.sql

\echo "Test 138: code-keyed upserts and key-aware generators (STATBUS-477 family C)"

CALL test.set_user_from_email('test.admin@statbus.org');

\echo "138.1: each family C custom view: upload, correct, re-upload"
INSERT INTO public.legal_rel_type_custom(code, name, description) VALUES ('q138', 'first', 'd1') RETURNING code, name, description;
INSERT INTO public.legal_rel_type_custom(code, name, description) VALUES ('q138', 'second (corrected)', 'd2') RETURNING code, name, description;
INSERT INTO public.legal_reorg_type_custom(code, name, description) VALUES ('q138', 'first', 'd1') RETURNING code, name;
INSERT INTO public.legal_reorg_type_custom(code, name, description) VALUES ('q138', 'second (corrected)', 'd2') RETURNING code, name;
INSERT INTO public.person_role_custom(code, name) VALUES ('q138', 'first role') RETURNING code, name;
INSERT INTO public.person_role_custom(code, name) VALUES ('q138', 'second role (corrected)') RETURNING code, name;
INSERT INTO public.power_group_type_custom(code, name) VALUES ('q138', 'first type') RETURNING code, name;
INSERT INTO public.power_group_type_custom(code, name) VALUES ('q138', 'second type (corrected)') RETURNING code, name;
INSERT INTO public.region_version_custom(code, name, description) VALUES ('q138', 'first', 'd1') RETURNING code, name;
\copy public.region_version_custom(code, name, description) FROM stdin WITH (FORMAT csv)
q138,second (corrected via csv),d2
\.
SELECT 'legal_rel_type' AS t, code, custom, enabled, name, description FROM public.legal_rel_type WHERE code = 'q138'
UNION ALL SELECT 'legal_reorg_type', code, custom, enabled, name, description FROM public.legal_reorg_type WHERE code = 'q138'
UNION ALL SELECT 'person_role', code, custom, enabled, name, NULL FROM public.person_role WHERE code = 'q138'
UNION ALL SELECT 'power_group_type', code, custom, enabled, name, NULL FROM public.power_group_type WHERE code = 'q138'
UNION ALL SELECT 'region_version', code, custom, enabled, name, description FROM public.region_version WHERE code = 'q138'
ORDER BY 1;

\echo "138.2: a system reload after the custom upload disabled the system rows (the wrong-key case)"
RESET ROLE;
SELECT pr.code AS pr_code FROM public.person_role AS pr WHERE NOT pr.custom ORDER BY pr.id LIMIT 1 \gset
SELECT pr.enabled AS system_row_enabled_before FROM public.person_role AS pr WHERE pr.code = :'pr_code';
INSERT INTO public.person_role_system(code, name) VALUES (:'pr_code', 'renamed by system reload') RETURNING code, name;
SELECT pr.code, pr.custom, pr.enabled, pr.name FROM public.person_role AS pr WHERE pr.code = :'pr_code';

\echo "138.3: a code owned by the other kind is refused with an actionable error"
SAVEPOINT cross_kind;
\set ON_ERROR_STOP off
INSERT INTO public.person_role_system(code, name) VALUES ('q138', 'system takeover attempt');
ROLLBACK TO SAVEPOINT cross_kind;
INSERT INTO public.person_role_custom(code, name) VALUES (:'pr_code', 'custom takeover attempt');
ROLLBACK TO SAVEPOINT cross_kind;

\echo "138.4: a collision on the second unique key (name) names the row and the value"
INSERT INTO public.person_role_custom(code, name) VALUES ('q139', 'second role (corrected)');
ROLLBACK TO SAVEPOINT cross_kind;
\set ON_ERROR_STOP on

\echo "138.5: the generator derives the conflict target from the table's identity key"
CREATE TABLE public.probe_477_code_only
    ( id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY
    , code text NOT NULL UNIQUE
    , name text NOT NULL
    , enabled boolean NOT NULL
    , custom boolean NOT NULL
    , created_at timestamptz NOT NULL DEFAULT statement_timestamp()
    , updated_at timestamptz NOT NULL DEFAULT statement_timestamp()
    );
CREATE TABLE public.probe_477_code_custom
    ( id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY
    , code text NOT NULL
    , name text NOT NULL
    , enabled boolean NOT NULL
    , custom boolean NOT NULL
    , created_at timestamptz NOT NULL DEFAULT statement_timestamp()
    , updated_at timestamptz NOT NULL DEFAULT statement_timestamp()
    );
SET client_min_messages TO WARNING;
SELECT admin.generate_table_views_for_batch_api('public.probe_477_code_only');
SELECT admin.generate_table_views_for_batch_api('public.probe_477_code_custom');
RESET client_min_messages;
SELECT v.table_name, v.variant
     , substring(pg_get_functiondef(v.fn) from 'ON CONFLICT \([^)]*\)') AS conflict_target
     , pg_get_functiondef(v.fn) ~ 'EXCLUDED\.id' AS has_id_predicate
     , pg_get_functiondef(v.fn) ~ 'RETURN NEW' AS reports_rows
  FROM (VALUES ('probe_477_code_only', 'custom', 'admin.upsert_probe_477_code_only_custom()'::regprocedure)
             , ('probe_477_code_only', 'system', 'admin.upsert_probe_477_code_only_system()'::regprocedure)
             , ('probe_477_code_custom', 'custom', 'admin.upsert_probe_477_code_custom_custom()'::regprocedure)
             , ('probe_477_code_custom', 'system', 'admin.upsert_probe_477_code_custom_system()'::regprocedure)) AS v(table_name, variant, fn)
 ORDER BY 1, 2;
SELECT conrelid::regclass AS table_name, pg_get_constraintdef(oid) AS unique_key
  FROM pg_catalog.pg_constraint
 WHERE conrelid IN ('public.probe_477_code_only'::regclass, 'public.probe_477_code_custom'::regclass)
   AND contype = 'u'
 ORDER BY conrelid::regclass::text, 2;
INSERT INTO public.probe_477_code_only_custom(code, name) VALUES ('a', 'custom a') RETURNING code, name;
INSERT INTO public.probe_477_code_only_custom(code, name) VALUES ('a', 'custom a (corrected)') RETURNING code, name;
INSERT INTO public.probe_477_code_custom_system(code, name) VALUES ('a', 'system a') RETURNING code, name;
INSERT INTO public.probe_477_code_custom_custom(code, name) VALUES ('a', 'custom a') RETURNING code, name;
INSERT INTO public.probe_477_code_custom_system(code, name) VALUES ('a', 'system a (reloaded)') RETURNING code, name;
SELECT 'code_only' AS t, code, custom, enabled, name FROM public.probe_477_code_only
UNION ALL SELECT 'code_custom', code, custom, enabled, name FROM public.probe_477_code_custom
ORDER BY 1, 3;

\echo "138.6: the identity key every generated table resolves to"
SELECT t.table_name
     , admin.batch_api_identity_key(admin.detect_batch_api_table_properties(format('public.%I', t.table_name)::regclass)) AS identity_key
  FROM (VALUES ('data_source'), ('foreign_participation'), ('legal_form'), ('legal_rel_type'), ('legal_reorg_type')
             , ('person_role'), ('power_group_type'), ('region_version'), ('sector'), ('status'), ('tag'), ('unit_size')) AS t(table_name)
 ORDER BY 1;

ROLLBACK;

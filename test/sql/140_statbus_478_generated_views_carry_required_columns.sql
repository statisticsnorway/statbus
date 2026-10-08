-- STATBUS-478: generated system/custom views carry every column an insert
-- needs, and the generated upserts write them.
--
-- status has assigned_by_default, used_for_counting and priority NOT NULL
-- without a default; status_custom/status_system exposed only (code, name,
-- priority) and the upserts wrote code and name only, so every insert failed.
--
-- Invariants checked:
--   1. status_custom: upload, correct, re-upload. code, name, priority,
--      assigned_by_default and used_for_counting are stored, and the
--      correction lands on the same row. (This closes STATBUS-477's recorded
--      AC#2 exception for status_custom.)
--   2. status_system: reload an existing status with corrected values.
--   3. The one-enabled-default rule (ix_status_only_one_assigned_by_default)
--      surfaces through the generated upsert's actionable message.
--   4. The generator: a fresh code table with a required column gets it in
--      its system/custom views and writes it.
BEGIN;

\i test/setup.sql

\echo "Test 140: generated views carry required columns (STATBUS-478)"

CALL test.set_user_from_email('test.admin@statbus.org');

\echo "140.1: status_custom: upload, correct, re-upload"
INSERT INTO public.status_custom(code, name, priority, assigned_by_default, used_for_counting)
VALUES ('q140', 'first', 10, true, true)
RETURNING code, name, priority, assigned_by_default, used_for_counting;
CREATE TEMP TABLE probe AS SELECT s.id AS custom_id FROM public.status AS s WHERE s.code = 'q140' AND s.custom;
INSERT INTO public.status_custom(code, name, priority, assigned_by_default, used_for_counting)
VALUES ('q140', 'second (corrected)', 20, true, false)
RETURNING code, name, priority, assigned_by_default, used_for_counting;
\copy public.status_custom(code, name, priority, assigned_by_default, used_for_counting) FROM stdin WITH (FORMAT csv)
q140,third (corrected via csv),30,true,false
\.
SELECT s.code, s.custom, s.enabled, s.name, s.priority, s.assigned_by_default, s.used_for_counting
     , s.id = (SELECT custom_id FROM probe) AS same_row_as_first_upload
  FROM public.status AS s WHERE s.code = 'q140';
SELECT sc.code, sc.name, sc.priority, sc.assigned_by_default, sc.used_for_counting
  FROM public.status_custom AS sc ORDER BY sc.code;

\echo "140.2: status_system: reload an existing status with corrected values"
RESET ROLE;
INSERT INTO public.status_system(code, name, priority, assigned_by_default, used_for_counting)
VALUES ('passive', 'Passive (renamed by reload)', 5, false, false)
RETURNING code, name, priority, assigned_by_default, used_for_counting;
SELECT s.code, s.custom, s.enabled, s.name, s.priority, s.assigned_by_default, s.used_for_counting
  FROM public.status AS s WHERE s.code = 'passive' ORDER BY s.custom;

\echo "140.3: a second enabled default status is refused with an actionable message"
SAVEPOINT second_default;
\set ON_ERROR_STOP off
INSERT INTO public.status_custom(code, name, priority, assigned_by_default, used_for_counting)
VALUES ('q141', 'another default', 40, true, true);
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT second_default;

\echo "140.4: the generator carries a required column of a fresh table"
CREATE TABLE public.probe_478_code
    ( id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY
    , code text NOT NULL
    , name text NOT NULL
    , weight integer NOT NULL
    , enabled boolean NOT NULL
    , custom boolean NOT NULL
    , created_at timestamptz NOT NULL DEFAULT statement_timestamp()
    , updated_at timestamptz NOT NULL DEFAULT statement_timestamp()
    );
SET client_min_messages TO WARNING;
SELECT admin.generate_table_views_for_batch_api('public.probe_478_code');
RESET client_min_messages;
SELECT a.attrelid::regclass AS view_name, string_agg(a.attname, ', ' ORDER BY a.attnum) AS columns
  FROM pg_catalog.pg_attribute AS a
 WHERE a.attrelid IN ('public.probe_478_code_custom'::regclass, 'public.probe_478_code_system'::regclass)
   AND a.attnum > 0
 GROUP BY 1 ORDER BY a.attrelid::regclass::text;
INSERT INTO public.probe_478_code_custom(code, name, weight) VALUES ('a', 'custom a', 1) RETURNING code, name, weight;
INSERT INTO public.probe_478_code_custom(code, name, weight) VALUES ('a', 'custom a (corrected)', 2) RETURNING code, name, weight;
SELECT p.code, p.custom, p.enabled, p.name, p.weight FROM public.probe_478_code AS p;

ROLLBACK;

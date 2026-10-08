-- STATBUS-477 family D: path-generated upserts (sector, tag) update existing
-- rows on their real key, path, and the generator produces that for new tables.
--
-- sector and tag carry UNIQUE (path): one row per path, owned by one kind.
-- Invariants checked:
--   1. sector_custom / tag_custom: upload, correct, re-upload. The custom row
--      lands ENABLED (visible in the custom view), and the correction lands,
--      description included.
--   2. The wrong-key case: after the app's sector_custom_only upload disables
--      every system sector, reloading the shipped sector list (sector_system)
--      corrects the system rows in place and keeps them disabled.
--   3. A path owned by the other kind is refused with an actionable error.
--   4. The generator, on a fresh path table: UNIQUE (path), conflict on
--      (path), no id predicate, rows reported, custom uploads land enabled,
--      a system reload never touches custom rows.
BEGIN;

\i test/setup.sql

\echo "Test 137: path-generated upserts update existing rows (STATBUS-477 family D)"

CALL test.set_user_from_email('test.admin@statbus.org');

\echo "137.1: sector_custom and tag_custom: upload, correct, re-upload; custom rows land enabled"
INSERT INTO public.sector_custom(path, name, description) VALUES ('q137', 'first', 'first description') RETURNING path, name, description;
INSERT INTO public.sector_custom(path, name, description) VALUES ('q137', 'second (corrected)', 'corrected description') RETURNING path, name, description;
SELECT s.path, s.custom, s.enabled, s.name, s.description FROM public.sector AS s WHERE s.path::text = 'q137';
SELECT sc.path, sc.name FROM public.sector_custom AS sc WHERE sc.path::text = 'q137';
INSERT INTO public.tag_custom(path, name) VALUES ('q137', 'first') RETURNING path, name;
\copy public.tag_custom(path, name) FROM stdin WITH (FORMAT csv)
q137,second (corrected via csv)
\.
SELECT t.path, t.custom, t.enabled, t.name FROM public.tag AS t WHERE t.path::text = 'q137';

\echo "137.2: reloading the shipped sector list after a custom-only upload (the wrong-key case)"
INSERT INTO public.sector_custom_only(path, name) VALUES ('zzop', 'operator sector');
SELECT count(*) FILTER (WHERE NOT custom) AS system_sectors
     , count(*) FILTER (WHERE NOT custom AND enabled) AS system_sectors_enabled
  FROM public.sector;
CREATE TEMP TABLE sector_before AS SELECT id, path FROM public.sector WHERE NOT custom;
RESET ROLE;
\copy public.sector_system(path, name) FROM 'dbseed/sector.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true)
INSERT INTO public.sector_system(path, name) VALUES ('domestic', 'Domestic sectors (renamed by reload)') RETURNING path, name;
SELECT count(*) FILTER (WHERE NOT custom) AS system_sectors
     , count(*) FILTER (WHERE NOT custom AND enabled) AS system_sectors_enabled
     , (SELECT count(*) FROM sector_before AS b JOIN public.sector AS s ON s.id = b.id AND s.path = b.path) AS kept_with_same_id
  FROM public.sector;
SELECT s.path, s.custom, s.enabled, s.name FROM public.sector AS s WHERE s.path::text IN ('domestic', 'zzop') ORDER BY s.path;

\echo "137.3: a path owned by the other kind is refused with an actionable error"
SAVEPOINT cross_kind;
\set ON_ERROR_STOP off
\set VERBOSITY default
INSERT INTO public.sector_system(path, name) VALUES ('zzop', 'system takeover attempt');
ROLLBACK TO SAVEPOINT cross_kind;
INSERT INTO public.sector_custom(path, name) VALUES ('domestic', 'custom takeover attempt');
ROLLBACK TO SAVEPOINT cross_kind;
\set ON_ERROR_STOP on
SELECT s.path, s.custom, s.name FROM public.sector AS s WHERE s.path::text IN ('domestic', 'zzop') ORDER BY s.path;

\echo "137.4: the generator produces the fixed shape for a new path table"
CREATE TABLE public.probe_477_path
    ( id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY
    , path public.ltree NOT NULL
    , parent_id integer REFERENCES public.probe_477_path(id)
    , name text NOT NULL
    , description text
    , enabled boolean NOT NULL
    , custom boolean NOT NULL
    , created_at timestamptz NOT NULL DEFAULT statement_timestamp()
    , updated_at timestamptz NOT NULL DEFAULT statement_timestamp()
    );
SET client_min_messages TO WARNING;
SELECT admin.generate_table_views_for_batch_api('public.probe_477_path');
RESET client_min_messages;
SELECT v.variant
     , substring(pg_get_functiondef(v.fn) from 'ON CONFLICT \([^)]*\)') AS conflict_target
     , pg_get_functiondef(v.fn) ~ 'EXCLUDED\.id' AS has_id_predicate
     , pg_get_functiondef(v.fn) ~ 'RETURN NEW' AS reports_rows
  FROM (VALUES ('custom', 'admin.upsert_probe_477_path_custom()'::regprocedure)
             , ('system', 'admin.upsert_probe_477_path_system()'::regprocedure)) AS v(variant, fn)
 ORDER BY 1;
SELECT conname, pg_get_constraintdef(oid) AS key
  FROM pg_catalog.pg_constraint
 WHERE conrelid = 'public.probe_477_path'::regclass AND conname = 'probe_477_path_path_key';
-- The custom uploads' prepare trigger disables the system rows (custom
-- replaces the standard list); the system reload then corrects 'a' in place
-- and leaves it disabled, and never touches the custom row 'b'.
INSERT INTO public.probe_477_path_system(path, name) VALUES ('a', 'system a') RETURNING path, name;
INSERT INTO public.probe_477_path_custom(path, name, description) VALUES ('b', 'custom b', 'custom description') RETURNING path, name;
INSERT INTO public.probe_477_path_custom(path, name, description) VALUES ('b', 'custom b (corrected)', 'corrected') RETURNING path, name;
INSERT INTO public.probe_477_path_system(path, name) VALUES ('a', 'system a (reloaded)') RETURNING path, name;
SELECT p.path, p.custom, p.enabled, p.name, p.description FROM public.probe_477_path AS p ORDER BY p.path;
SELECT pc.path, pc.name FROM public.probe_477_path_custom AS pc ORDER BY pc.path;

ROLLBACK;

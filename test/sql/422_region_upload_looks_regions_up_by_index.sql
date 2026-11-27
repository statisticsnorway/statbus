-- 7dw69p: a region file uploads in time proportional to its rows. admin.region_upload_upsert runs
-- once per row and looks up the row's parent and stored self in public.region, which the same upload
-- is filling, while the planner's statistics still describe the table as it was before the upload:
-- on a new installation, empty. Each lookup is one probe of region_version_path_key, however many
-- regions the upload has stored. Uganda (region vacuumed and analysed while empty) read every stored
-- region per row by a sequential scan, and its 58,000-region file met the 120 s statement_timeout.
BEGIN;
\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

-- A new installation's region table as the planner sees it: vacuumed and analysed while empty
-- (pg_class.reltuples 0, relpages 0). ANALYZE on the empty template table writes exactly that.
SET client_min_messages TO WARNING;
ANALYZE public.region;
RESET client_min_messages;
SELECT reltuples AS planner_believes_rows, relpages AS planner_believes_pages
  FROM pg_class WHERE oid = 'public.region'::regclass;

\echo "422.1 a file of 2,000 regions (1 top region, 40 below it, 49 below each of those) stores every row"
CREATE TEMP TABLE file_rows AS
SELECT '42'::text AS path, 'Region 42'::text AS name
UNION ALL
SELECT format('42.%s', b), format('District %s', b) FROM generate_series(10, 49) AS b
UNION ALL
SELECT format('42.%s.%s', b, c), format('Parish %s of district %s', c, b)
  FROM generate_series(10, 49) AS b, generate_series(10, 58) AS c
 WHERE (b - 10) * 49 + (c - 10) < 1959;

SELECT pg_stat_get_xact_numscans('public.region'::regclass) AS table_scans_before \gset

INSERT INTO public.region_upload (path, name) SELECT path, name FROM file_rows;

SELECT pg_stat_get_xact_numscans('public.region'::regclass) - :table_scans_before AS upload_table_scans,
       pg_stat_get_xact_numscans('public.region_version_path_key'::regclass) AS upload_path_probes \gset

SELECT (SELECT count(*) FROM file_rows) AS rows_in_file,
       count(*) AS regions_stored,
       count(*) FILTER (WHERE parent_id IS NOT NULL) AS regions_with_parent
  FROM public.region
 WHERE path <@ '42';

\echo "422.2 the upload looked regions up through the index on (version_id, path): no table scan read the stored regions"
SELECT :upload_table_scans AS region_table_scans_by_the_upload,
       :upload_path_probes >= (SELECT count(*) FROM file_rows) AS each_row_probed_the_path_index;

ROLLBACK;

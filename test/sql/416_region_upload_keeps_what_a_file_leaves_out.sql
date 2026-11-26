BEGIN;

\i test/setup.sql

-- 5yxn4w: a region file changes only what it gives (admin.region_upload_upsert). The list is
-- uploaded once with path and name; centres can come later in their own file of path and centre
-- columns, and a later path,name file (a corrected name) keeps the centres placed since.

SET client_min_messages TO warning;

\echo "The region list, with one centre placed"
\copy public.region_upload(path,name) FROM stdin WITH (FORMAT csv, DELIMITER ',');
03,Oslo
11,Rogaland
11.01,Eigersund
11.03,Stavanger
\.
\copy public.region_upload(path,name,latitude,longitude,altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
11.03,Stavanger,58.979290,5.707019,10
\.

\echo "A file of path and centre columns adds centres to listed regions and keeps their names"
\copy public.region_upload(path,latitude,longitude,altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
03,59.913868,10.752245,23
11.01,58.463409,5.975909,
\.
SELECT path, name, latitude, longitude, altitude
  FROM public.region WHERE path IN ('03', '11.01') ORDER BY path;

\echo "A path,name file corrects a name and keeps the centre"
\copy public.region_upload(path,name) FROM stdin WITH (FORMAT csv, DELIMITER ',');
11.03,Stavanger kommune
\.
SELECT path, name, latitude, longitude, altitude
  FROM public.region WHERE path = '11.03';

\echo "A row with a name but empty centre cells keeps the centre too"
\copy public.region_upload(path,name,latitude,longitude,altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
03,Oslo,,,
\.
SELECT path, name, latitude, longitude, altitude
  FROM public.region WHERE path = '03';

\echo "A new centre without an altitude drops the old point's altitude"
\copy public.region_upload(path,latitude,longitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
11.03,58.97,5.73
\.
SELECT path, latitude, longitude, altitude
  FROM public.region WHERE path = '11.03';

\echo "Storing the regions as they are writes no region, so no unit is re-derived; one change writes one"
CREATE TEMP TABLE regions_as_stored AS SELECT * FROM public.region_upload;
CREATE TEMP TABLE updates_before AS SELECT pg_stat_get_xact_tuples_updated('public.region'::regclass) AS n;
INSERT INTO public.region_upload SELECT * FROM regions_as_stored;
SELECT pg_stat_get_xact_tuples_updated('public.region'::regclass) - n AS regions_written_by_unchanged_file
  FROM updates_before;
UPDATE regions_as_stored SET altitude = '12' WHERE path = '11.03';
UPDATE updates_before SET n = pg_stat_get_xact_tuples_updated('public.region'::regclass) WHERE true;
INSERT INTO public.region_upload SELECT * FROM regions_as_stored;
SELECT pg_stat_get_xact_tuples_updated('public.region'::regclass) - n AS regions_written_by_one_change
  FROM updates_before;
SELECT path, latitude, longitude, altitude
  FROM public.region WHERE path = '11.03';

\echo "A region not yet listed needs a name"
SAVEPOINT new_without_name;
\copy public.region_upload(path,latitude,longitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
11.98,58.0,6.0
\.
ROLLBACK TO new_without_name;
SELECT count(*) AS regions_at_11_98 FROM public.region WHERE path = '11.98';

ROLLBACK;

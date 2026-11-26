BEGIN;

\i test/setup.sql

-- jbc5bs: coordinates have one plain name, latitude, longitude, altitude, for
-- regions and units. A region file and a unit import with those headers store
-- the point. The old headers (center_* for regions, physical_* for units) are a
-- hard cut (owner 2026-11-27): no code names them, so they meet the ordinary
-- handling of any unknown column and store no point.

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

SET client_min_messages TO warning;

\echo "A region file with latitude, longitude, altitude stores each region's point"
\copy public.region_upload(path,name,latitude,longitude,altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
91,Coordinate Region,59.913868,10.752245,23
91.1,Coordinate Subregion,60.391263,5.322054,
\.
SELECT path, name, latitude, longitude, altitude
  FROM public.region
 WHERE path <@ '91'
 ORDER BY path;

\echo "A region file with the old center_* headers is refused as unknown columns and stores nothing"
SAVEPOINT before_center_headers;
\set ON_ERROR_STOP off
\copy public.region_upload(path,name,center_latitude,center_longitude,center_altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
92,Old Header Region,61.0,9.0,10
\.
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_center_headers;
SELECT count(*) AS regions_stored_from_old_headers FROM public.region WHERE path <@ '92';

\echo "An import of a legal unit with latitude, longitude, altitude stores the point"
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
       'import_415_lu', 'Legal unit with a point (415)', 'Test 415', false;
SELECT public.import_job_accept_upload_columns(
           (SELECT id FROM public.import_job WHERE slug = 'import_415_lu'),
           ARRAY['valid_from', 'valid_to', 'tax_ident', 'name', 'physical_region_code', 'latitude', 'longitude', 'altitude']
       ) AS kept_as_ignored;
INSERT INTO public.import_415_lu_upload(valid_from, valid_to, tax_ident, name, physical_region_code, physical_country_iso_2, primary_activity_category_code, sector_code, legal_form_code, data_source_code, latitude, longitude, altitude) VALUES
('2024-01-01', 'infinity', '415000001', 'Point Legal Unit', '225602', 'UN', '1410', '4500', '1', 'nlr', '59.913868', '10.752245', '23');
CALL worker.process_tasks(p_queue => 'import');
SELECT state, error IS NULL AS no_error FROM public.import_job WHERE slug = 'import_415_lu';
SELECT state, action, errors, latitude, longitude, altitude FROM public.import_415_lu_data;

SELECT l.type, l.latitude, l.longitude, l.altitude
  FROM public.location AS l
  JOIN public.legal_unit AS lu ON lu.id = l.legal_unit_id
 WHERE lu.name = 'Point Legal Unit'
 ORDER BY l.type;

CALL worker.process_tasks(p_queue => 'analytics');
SELECT su.unit_type, su.name, su.latitude, su.longitude, su.altitude
  FROM public.statistical_unit AS su
 WHERE su.name = 'Point Legal Unit'
 ORDER BY su.unit_type;

\echo "An import with the old physical_* headers keeps them as ignored columns: no point is stored from them"
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
       'import_415_old', 'Legal unit with old headers (415)', 'Test 415', false;
SELECT public.import_job_accept_upload_columns(
           (SELECT id FROM public.import_job WHERE slug = 'import_415_old'),
           ARRAY['valid_from', 'valid_to', 'tax_ident', 'name', 'physical_latitude', 'physical_longitude', 'physical_altitude']
       ) AS kept_as_ignored;
SELECT dc->>'column_name' AS column_name, dc->>'purpose' AS purpose
  FROM public.import_job AS j,
       jsonb_array_elements(j.definition_snapshot->'import_data_column_list') AS dc
 WHERE j.slug = 'import_415_old'
   AND dc->>'column_name' ~ 'latitude|longitude|altitude'
 ORDER BY 1;

\echo "The postal location step takes no coordinates; the physical step takes the plain names"
SELECT s.code, dc.column_name, dc.purpose
  FROM public.import_data_column AS dc
  JOIN public.import_step AS s ON s.id = dc.step_id
 WHERE s.code IN ('physical_location', 'postal_location')
   AND dc.column_name ~ '(latitude|longitude|altitude)'
 ORDER BY s.code, dc.priority;

ROLLBACK;

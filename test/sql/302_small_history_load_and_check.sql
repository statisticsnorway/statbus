BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Setting up Statbus for Norway"
\i samples/norway/getting-started.sql

\echo "Creating import definitions for BRREG Hovedenhet and Underenhet 2024"
\i samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
\i samples/norway/brreg/create-import-definition-underenhet-2024.sql

-- Display summary of created definitions
SELECT slug, name, note, valid_time_from, strategy, valid, validation_error
FROM public.import_definition
WHERE slug LIKE 'brreg_%_2024'
ORDER BY slug;

-- Per year jobs for hovedenhet (Legal Units)
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_10_lu_2015_sht', '2015-01-01', 'infinity', 'Import Job for BRREG Hovedenhet 2015 Small History Test (Test 10)', 'This job handles the import of BRREG Hovedenhet small history test data for 2015 (Test 10).', 'BRREG Hovedenhet 2015 (SHT Test 10)'
FROM def;

\echo '--- Debugging Schema for Job import_10_lu_2015_sht ---'
\d+ public.import_10_lu_2015_sht_data
\echo '------------------------------------------'

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_10_lu_2016_sht', '2016-01-01', 'infinity', 'Import Job for BRREG Hovedenhet 2016 Small History Test (Test 10)', 'This job handles the import of BRREG Hovedenhet small history test data for 2016 (Test 10).', 'BRREG Hovedenhet 2016 (SHT Test 10)'
FROM def;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_10_lu_2017_sht', '2017-01-01', 'infinity', 'Import Job for BRREG Hovedenhet 2017 Small History Test (Test 10)', 'This job handles the import of BRREG Hovedenhet small history test data for 2017 (Test 10).', 'BRREG Hovedenhet 2017 (SHT Test 10)'
FROM def;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_10_lu_2018_sht', '2018-01-01', 'infinity', 'Import Job for BRREG Hovedenhet 2018 Small History Test (Test 10)', 'This job handles the import of BRREG Hovedenhet small history test data for 2018 (Test 10).', 'BRREG Hovedenhet 2018 (SHT Test 10)'
FROM def;

-- Per year jobs for underenhet (Establishments)
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_10_es_2015_sht', '2015-01-01', 'infinity', 'Import Job for BRREG Underenhet 2015 Small History Test (Test 10)', 'This job handles the import of BRREG Underenhet small history test data for 2015 (Test 10).', 'BRREG Underenhet 2015 (SHT Test 10)'
FROM def;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_10_es_2016_sht', '2016-01-01', 'infinity', 'Import Job for BRREG Underenhet 2016 Small History Test (Test 10)', 'This job handles the import of BRREG Underenhet small history test data for 2016 (Test 10).', 'BRREG Underenhet 2016 (SHT Test 10)'
FROM def;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_10_es_2017_sht', '2017-01-01', 'infinity', 'Import Job for BRREG Underenhet 2017 Small History Test (Test 10)', 'This job handles the import of BRREG Underenhet small history test data for 2017 (Test 10).', 'BRREG Underenhet 2017 (SHT Test 10)'
FROM def;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_10_es_2018_sht', '2018-01-01', 'infinity', 'Import Job for BRREG Underenhet 2018 Small History Test (Test 10)', 'This job handles the import of BRREG Underenhet small history test data for 2018 (Test 10).', 'BRREG Underenhet 2018 (SHT Test 10)'
FROM def;

\echo "Loading historical units into respective job upload tables"
\copy public.import_10_lu_2015_sht_upload FROM 'samples/norway/small-history/2015-enheter.csv' WITH CSV HEADER;
\copy public.import_10_lu_2016_sht_upload FROM 'samples/norway/small-history/2016-enheter.csv' WITH CSV HEADER;
\copy public.import_10_lu_2017_sht_upload FROM 'samples/norway/small-history/2017-enheter.csv' WITH CSV HEADER;
\copy public.import_10_lu_2018_sht_upload FROM 'samples/norway/small-history/2018-enheter.csv' WITH CSV HEADER;
\copy public.import_10_es_2015_sht_upload FROM 'samples/norway/small-history/2015-underenheter.csv' WITH CSV HEADER;
\copy public.import_10_es_2016_sht_upload FROM 'samples/norway/small-history/2016-underenheter.csv' WITH CSV HEADER;
\copy public.import_10_es_2017_sht_upload FROM 'samples/norway/small-history/2017-underenheter.csv' WITH CSV HEADER;
\copy public.import_10_es_2018_sht_upload FROM 'samples/norway/small-history/2018-underenheter.csv' WITH CSV HEADER;

\echo Run worker processing for import jobs
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo Check import job states after import
SELECT slug, state, total_rows, imported_rows, error IS NOT NULL AS has_error
FROM public.import_job
WHERE slug LIKE 'import_10_%_sht'
ORDER BY slug;

-- Note: Use 'SELECT * FROM ...' instead of 'PERFORM' for function calls at the top level in psql.
-- 'PERFORM' is a PL/pgSQL statement and cannot be used directly in SQL.
SELECT * FROM public.timesegments_refresh();
SELECT * FROM public.timeline_establishment_refresh();
SELECT * FROM public.timeline_legal_unit_refresh();
SELECT * FROM public.timeline_enterprise_refresh(); -- Ensure enterprise timeline is refreshed
SELECT * FROM public.statistical_unit_refresh();

\echo "Checking for multiple primary legal units for the same enterprise and overlapping time"
SELECT
    e.id AS enterprise_id,
    lu1.id AS lu1_id,
    lu1.valid_after AS lu1_valid_after,
    lu1.valid_to AS lu1_valid_to,
    lu1.name AS lu1_name,
    lu2.id AS lu2_id,
    lu2.valid_after AS lu2_valid_after,
    lu2.valid_to AS lu2_valid_to,
    lu2.name AS lu2_name,
    public.after_to_overlaps(lu1.valid_after, lu1.valid_to, lu2.valid_after, lu2.valid_to) AS overlap_period
FROM public.enterprise e
JOIN public.legal_unit lu1 ON lu1.enterprise_id = e.id AND lu1.primary_for_enterprise = TRUE
JOIN public.legal_unit lu2 ON lu2.enterprise_id = e.id AND lu2.primary_for_enterprise = TRUE AND lu1.id < lu2.id -- lu1.id < lu2.id to avoid self-join and duplicate pairs
WHERE public.after_to_overlaps(lu1.valid_after, lu1.valid_to, lu2.valid_after, lu2.valid_to)
ORDER BY 
    (SELECT xei.ident FROM public.external_ident xei WHERE xei.legal_unit_id = lu1.id AND xei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident') LIMIT 1), 
    lu1.valid_after, 
    lu1.name, 
    (SELECT xei.ident FROM public.external_ident xei WHERE xei.legal_unit_id = lu2.id AND xei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident') LIMIT 1), 
    lu2.valid_after,
    lu2.name;

\echo "Checking for multiple primary establishments for the same enterprise and overlapping time"
SELECT
    e.id AS enterprise_id,
    est1.id AS est1_id,
    est1.valid_after AS est1_valid_after,
    est1.valid_to AS est1_valid_to,
    est1.name AS est1_name,
    est2.id AS est2_id,
    est2.valid_after AS est2_valid_after,
    est2.valid_to AS est2_valid_to,
    est2.name AS est2_name,
    public.after_to_overlaps(est1.valid_after, est1.valid_to, est2.valid_after, est2.valid_to) AS overlap_period
FROM public.enterprise e
JOIN public.establishment est1 ON est1.enterprise_id = e.id AND est1.primary_for_enterprise = TRUE
JOIN public.establishment est2 ON est2.enterprise_id = e.id AND est2.primary_for_enterprise = TRUE AND est1.id < est2.id -- est1.id < est2.id to avoid self-join and duplicate pairs
WHERE public.after_to_overlaps(est1.valid_after, est1.valid_to, est2.valid_after, est2.valid_to)
ORDER BY 
    (SELECT xei.ident FROM public.external_ident xei WHERE xei.establishment_id = est1.id AND xei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident') LIMIT 1), 
    est1.valid_after, 
    est1.name, 
    (SELECT xei.ident FROM public.external_ident xei WHERE xei.establishment_id = est2.id AND xei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident') LIMIT 1), 
    est2.valid_after,
    est2.name;

\echo "Checking for duplicates in timeline_enterprise_def before running analytics"
\echo "Duplicate (unit_type, unit_id, valid_after) in timeline_enterprise_def that would cause ON CONFLICT error:"
SELECT unit_type, unit_id, valid_after, COUNT(*)
FROM public.timeline_enterprise_def
GROUP BY unit_type, unit_id, valid_after
HAVING COUNT(*) > 1
ORDER BY 
    unit_type, 
    (SELECT xei.ident FROM public.external_ident xei WHERE xei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident') AND CASE unit_type WHEN 'enterprise' THEN xei.enterprise_id = unit_id WHEN 'legal_unit' THEN xei.legal_unit_id = unit_id WHEN 'establishment' THEN xei.establishment_id = unit_id ELSE FALSE END ORDER BY xei.ident LIMIT 1),
    valid_after;

\echo "Detailed duplicate rows from timeline_enterprise_def causing ON CONFLICT errors:"
WITH DuplicatedKeys AS (
    SELECT unit_type, unit_id, valid_after
    FROM public.timeline_enterprise_def
    GROUP BY unit_type, unit_id, valid_after
    HAVING COUNT(*) > 1
)
SELECT ted.unit_id, ted.valid_after, ted.valid_from, ted.valid_to,
       ted.name,
       ted.primary_activity_category_code,
       ted.sector_code,
       ted.legal_form_code,
       ted.last_edit_comment,
       ted.last_edit_at,
       ted.primary_legal_unit_id,
       ted.primary_establishment_id
FROM public.timeline_enterprise_def ted
JOIN DuplicatedKeys dk ON ted.unit_type = dk.unit_type AND ted.unit_id = dk.unit_id AND ted.valid_after = dk.valid_after
ORDER BY 
    ted.unit_type, 
    (SELECT xei.ident FROM public.external_ident xei WHERE xei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident') AND CASE ted.unit_type WHEN 'enterprise' THEN xei.enterprise_id = ted.unit_id WHEN 'legal_unit' THEN xei.legal_unit_id = ted.unit_id WHEN 'establishment' THEN xei.establishment_id = ted.unit_id ELSE FALSE END ORDER BY xei.ident LIMIT 1),
    ted.valid_after, 
    ted.valid_from NULLS FIRST, 
    ted.valid_to NULLS FIRST, 
    ted.name NULLS FIRST, 
    ted.last_edit_at NULLS FIRST;

\echo Run worker processing for analytics tasks before EXPLAIN ANALYZE
CALL worker.process_tasks(p_queue => 'analytics'); -- This will call all of the refresh functions above.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

SELECT test.sudo_exec($sql$
  CREATE INDEX IF NOT EXISTS tidx_establishment_valid_after_valid_to ON establishment (valid_after, valid_to);
  CREATE INDEX IF NOT EXISTS tidx_stat_for_unit_establishment_id ON stat_for_unit (establishment_id);
  CREATE INDEX IF NOT EXISTS tidx_activity_establishment_id ON activity (establishment_id);
  CREATE INDEX IF NOT EXISTS tidx_legal_unit_valid_after_valid_to ON legal_unit (valid_after, valid_to);
  CREATE INDEX IF NOT EXISTS tidx_stat_for_unit_legal_unit_id ON stat_for_unit (legal_unit_id);
  CREATE INDEX IF NOT EXISTS tidx_location_legal_unit_id ON location (legal_unit_id);
  CREATE INDEX IF NOT EXISTS tidx_legal_activity_date ON legal_unit (id, valid_after, valid_to);
$sql$);

SELECT test.sudo_exec($sql$
  ANALYZE establishment;
  ANALYZE stat_for_unit;
  ANALYZE activity;
  ANALYZE legal_unit;
  ANALYZE location;
$sql$);

-- Check the query efficiency of the views used for building statistical_unit.
\a
\t
SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/timepoints.log
EXPLAIN ANALYZE SELECT * FROM public.timepoints;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.timepoints%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/timesegments.log
EXPLAIN ANALYZE SELECT * FROM public.timesegments_def;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.timesegments%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/timeline_establishment.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_establishment_def;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.timeline_establishment%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/timeline_legal_unit.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_legal_unit_def;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.timeline_legal_unit%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/timeline_enterprise.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_enterprise_def;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.timeline_enterprise%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\o tmp/statistical_unit_def.log
EXPLAIN ANALYZE SELECT * FROM public.statistical_unit_def;
SELECT queryid, calls, total_exec_time, rows
FROM pg_stat_monitor
WHERE query LIKE '%SELECT * FROM public.statistical_unit_def%';
\o

SELECT test.sudo_exec('SELECT pg_stat_monitor_reset()');

\a
\t

\o tmp/top_used_indices.log
-- Get top used indices with additional information from pg_stat_monitor
SELECT
    indexrelid::regclass AS index_name,
    relid::regclass AS table_name,
    idx_scan,
    idx_tup_fetch AS tuples_fetched,
    (SELECT substr(query, 0, 100) FROM pg_stat_monitor 
     WHERE relations::text LIKE '%' || relid::regclass::text || '%' 
     ORDER BY total_exec_time DESC LIMIT 1) AS sample_query
FROM
    pg_stat_user_indexes
WHERE
    idx_scan > 0  -- Focus on indexes that have been used
ORDER BY
    idx_scan DESC
LIMIT 20;  -- Display top used indexes, adjust if necessary
\o

-- The main analytics processing was done before EXPLAIN ANALYZE.
-- This call might process any remaining or newly queued tasks if necessary.
\echo Run worker processing for any remaining analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo "High-level check of statistical units after import"
\x
SELECT valid_after
     , valid_from
     , valid_to
     , unit_type
     , external_idents
     , jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
          to_jsonb(statistical_unit.*)
          -'stats'
          -'stats_summary'
          -'valid_after'
          -'valid_from'
          -'valid_to'
          -'unit_type'
          -'external_idents'
          )
     ) AS statistical_unit_data
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
 FROM public.statistical_unit
 ORDER BY unit_type, external_idents->>'tax_ident', valid_from, valid_to;
\x


ROLLBACK;

BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
\i samples/norway/brreg/create-import-definition-underenhet-2024.sql

-- Display summary of created definitions
SELECT slug, name, note, time_context_ident, strategy, valid, validation_error
FROM public.import_definition
WHERE slug LIKE 'brreg_%_2024'
ORDER BY slug;

-- Per year jobs for hovedenhet
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_lu_2015_sht', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2015 Small History Test', 'This job handles the import of BRREG Hovedenhet small history test data for 2015.', 'BRREG Hovedenhet 2015 (SHT)'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_lu_2016_sht', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2016 Small History Test', 'This job handles the import of BRREG Hovedenhet small history test data for 2016.', 'BRREG Hovedenhet 2016 (SHT)'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_lu_2017_sht', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2017 Small History Test', 'This job handles the import of BRREG Hovedenhet small history test data for 2017.', 'BRREG Hovedenhet 2017 (SHT)'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_lu_2018_sht', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2018 Small History Test', 'This job handles the import of BRREG Hovedenhet small history test data for 2018.', 'BRREG Hovedenhet 2018 (SHT)'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

-- Per year jobs for underenhet
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_es_2015_sht', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2015 Small History Test', 'This job handles the import of BRREG Underenhet small history test data for 2015.', 'BRREG Underenhet 2015 (SHT)'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_es_2016_sht', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2016 Small History Test', 'This job handles the import of BRREG Underenhet small history test data for 2016.', 'BRREG Underenhet 2016 (SHT)'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_es_2017_sht', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2017 Small History Test', 'This job handles the import of BRREG Underenhet small history test data for 2017.', 'BRREG Underenhet 2017 (SHT)'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note,edit_comment)
SELECT  def.id, 'import_es_2018_sht', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2018 Small History Test', 'This job handles the import of BRREG Underenhet small history test data for 2018.', 'BRREG Underenhet 2018 (SHT)'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

\echo Verify the concrete tables of one import job
\d public.import_lu_2015_sht_upload
\d public.import_lu_2015_sht_data

\echo 'Definition snapshot for import_lu_2015_sht:'
SELECT jsonb_pretty(public.remove_ephemeral_data_from_hierarchy(definition_snapshot)) FROM public.import_job WHERE slug = 'import_lu_2015_sht';

\d public.import_es_2015_sht_upload
\d public.import_es_2015_sht_data

\echo 'Definition snapshot for import_es_2015_sht:'
SELECT jsonb_pretty(public.remove_ephemeral_data_from_hierarchy(definition_snapshot)) FROM public.import_job WHERE slug = 'import_es_2015_sht';
-- 
-- Display the definition snapshot for one job (optional, can be large)
-- SELECT slug, definition_snapshot FROM public.import_job WHERE slug = 'import_lu_2015_sht';

\echo "Setting up Statbus for Norway"
\i samples/norway/getting-started.sql

-- Verify user context is set correctly for import jobs
\echo "Verifying user context for import jobs"
SELECT slug,
       (SELECT email FROM public.user WHERE id = user_id) AS user_email
FROM public.import_job
WHERE slug = 'import_lu_2015_sht';

\echo "Loading historical units"

\copy public.import_lu_2015_sht_upload FROM 'samples/norway/small-history/2015-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2016_sht_upload FROM 'samples/norway/small-history/2016-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2017_sht_upload FROM 'samples/norway/small-history/2017-enheter.csv' WITH CSV HEADER;
\copy public.import_lu_2018_sht_upload FROM 'samples/norway/small-history/2018-enheter.csv' WITH CSV HEADER;
\copy public.import_es_2015_sht_upload FROM 'samples/norway/small-history/2015-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2016_sht_upload FROM 'samples/norway/small-history/2016-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2017_sht_upload FROM 'samples/norway/small-history/2017-underenheter.csv' WITH CSV HEADER;
\copy public.import_es_2018_sht_upload FROM 'samples/norway/small-history/2018-underenheter.csv' WITH CSV HEADER;

\echo Check import job state before import
SELECT state, count(*) FROM import_job GROUP BY state;

\echo Check data row state before import (should be empty as worker hasn't run prepare)
SELECT state, count(*) FROM public.import_lu_2015_sht_data GROUP BY state;

\echo Check data row state before import (should be empty as worker hasn't run prepare)
SELECT state, count(*) FROM public.import_es_2015_sht_data GROUP BY state;

\echo Process import jobs
-- SET client_min_messages TO debug1;
SET client_min_messages TO NOTICE;
CALL worker.process_tasks(p_queue => 'import');

\echo Check the states of the import job tasks.
select queue,t.command,state,error from worker.tasks as t join worker.command_registry as c on t.command = c.command where t.command = 'import_job_process' order by priority;
select slug, state, error is not null as failed,total_rows,imported_rows, import_completed_pct from public.import_job order by id;

\echo Check import job state after import
SELECT state, count(*) FROM import_job GROUP BY state;

\echo Check data row state after import (should be 'processed' or 'error')
SELECT state, count(*) FROM public.import_lu_2015_sht_data GROUP BY state;
SELECT state, count(*) FROM public.import_lu_2016_sht_data GROUP BY state;
SELECT state, count(*) FROM public.import_lu_2017_sht_data GROUP BY state;
SELECT state, count(*) FROM public.import_lu_2018_sht_data GROUP BY state;

SELECT state, count(*) FROM public.import_es_2015_sht_data GROUP BY state;
SELECT state, count(*) FROM public.import_es_2016_sht_data GROUP BY state;
SELECT state, count(*) FROM public.import_es_2017_sht_data GROUP BY state;
SELECT state, count(*) FROM public.import_es_2018_sht_data GROUP BY state;

\echo "Row-level errors for import_es_2016_sht (if any):"
SELECT row_id, state, error, tax_ident, name, legal_unit_tax_ident
FROM public.import_es_2016_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo "Row-level errors for import_es_2017_sht (if any):"
SELECT row_id, state, error, tax_ident, name, legal_unit_tax_ident
FROM public.import_es_2017_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo "Row-level errors for import_es_2018_sht (if any):"
SELECT row_id, state, error, tax_ident, name, legal_unit_tax_ident
FROM public.import_es_2018_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo Check the state of all tasks before running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo "Explicitly refreshing timesegments before checking timeline_establishment_def"
SELECT public.timesegments_refresh();

\echo "Duplicate (unit_type, unit_id, timepoint) in public.timepoints for establishments:"
SELECT unit_type, unit_id, timepoint, COUNT(*)
FROM public.timepoints
WHERE unit_type = 'establishment'
GROUP BY unit_type, unit_id, timepoint
HAVING COUNT(*) > 1
ORDER BY unit_id, timepoint;

\echo "Duplicate (unit_type, unit_id, valid_after) in timeline_establishment_def that would cause ON CONFLICT error:"
SELECT unit_type, unit_id, valid_after, COUNT(*)
FROM public.timeline_establishment_def
GROUP BY unit_type, unit_id, valid_after
HAVING COUNT(*) > 1
ORDER BY unit_id, valid_after;

\echo "Duplicates from timeline_establishment_def that would cause INSERT ON CONFLICT to fail"
SELECT unit_type, unit_id, valid_after, COUNT(*)
FROM public.timeline_establishment_def
GROUP BY unit_type, unit_id, valid_after
HAVING COUNT(*) > 1
ORDER BY unit_id, valid_after;

\echo "Detailed duplicate rows from timeline_establishment_def causing ON CONFLICT errors:"
WITH DuplicatedKeys AS (
    SELECT unit_type, unit_id, valid_after
    FROM public.timeline_establishment_def
    GROUP BY unit_type, unit_id, valid_after
    HAVING COUNT(*) > 1
)
SELECT ted.unit_id, ted.valid_after, ted.valid_from, ted.valid_to,
       ted.name,
       ted.primary_activity_category_id, ted.primary_activity_category_code,
       ted.secondary_activity_category_id, ted.secondary_activity_category_code,
       array_length(ted.activity_category_paths, 1) as num_activity_paths,
       phl.id as physical_location_id, ted.physical_address_part1, ted.physical_postcode,
       pol.id as postal_location_id, ted.postal_address_part1, ted.postal_postcode,
       c.id as contact_id, ted.web_address,
       ted.last_edit_at
FROM public.timeline_establishment_def ted
JOIN DuplicatedKeys dk ON ted.unit_type = dk.unit_type AND ted.unit_id = dk.unit_id AND ted.valid_after = dk.valid_after
LEFT JOIN public.location phl ON phl.establishment_id = ted.unit_id AND phl.type = 'physical' AND after_to_overlaps(ted.valid_after, ted.valid_to, phl.valid_after, phl.valid_to)
LEFT JOIN public.location pol ON pol.establishment_id = ted.unit_id AND pol.type = 'postal' AND after_to_overlaps(ted.valid_after, ted.valid_to, pol.valid_after, pol.valid_to)
LEFT JOIN public.contact c ON c.establishment_id = ted.unit_id AND after_to_overlaps(ted.valid_after, ted.valid_to, c.valid_after, c.valid_to)
ORDER BY ted.unit_id, ted.valid_after,
         ted.primary_activity_category_id NULLS FIRST,
         ted.secondary_activity_category_id NULLS FIRST,
         phl.id NULLS FIRST,
         pol.id NULLS FIRST,
         c.id NULLS FIRST;

-- Once the Imports are finished, then all the analytics can be processed, but only once.
CALL worker.process_tasks(p_queue => 'analytics');

\echo Check the state of all tasks after running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo Run any remaining tasks, there should be none.
CALL worker.process_tasks();

\echo Check the state of all tasks after running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

\echo Overview of statistical units, but not details, there are too many units.
SELECT valid_from
     , valid_to
     , name
     , external_idents ->> 'tax_ident' AS tax_ident
     , unit_type
 FROM public.statistical_unit
 ORDER BY name, unit_type, valid_from, valid_to, external_idents ->> 'tax_ident', unit_id;


\echo Getting statistical_units after upload
\x
SELECT valid_after
     , valid_from
     , valid_to
     , unit_type
     , external_idents
     , jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
          to_jsonb(statistical_unit.*)
          -'valid_after'
          -'valid_from'
          -'valid_to'
          -'unit_type'
          -'external_idents'
          -'stats'
          -'stats_summary'
          )
     ) AS statistical_unit_data
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
 FROM public.statistical_unit
 ORDER BY valid_from, valid_to, unit_type, external_idents ->> 'tax_ident', unit_id;
\x


\echo Generate traces of indices used to build the history, analysis with tools such as shipped "/pev2" aka "postgres explain visualizer pev2 query performance"
\o tmp/50_import_jobs_for_norway_small_history-timepoints.log
EXPLAIN ANALYZE SELECT * FROM public.timepoints;
\o tmp/50_import_jobs_for_norway_small_history-timesegments_def.log
EXPLAIN ANALYZE SELECT * FROM public.timesegments_def;
\o tmp/50_import_jobs_for_norway_small_history-timeline_establishment_def.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_establishment_def;
\o tmp/50_import_jobs_for_norway_small_history-timeline_legal_unit_def.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_legal_unit_def;
\o tmp/50_import_jobs_for_norway_small_history-timeline_enterprise_def.log
EXPLAIN ANALYZE SELECT * FROM public.timeline_enterprise_def;
\o tmp/50_import_jobs_for_norway_small_history-statistical_unit_def.log
EXPLAIN ANALYZE SELECT * FROM public.statistical_unit_def;
\o


RESET client_min_messages;

ROLLBACK;

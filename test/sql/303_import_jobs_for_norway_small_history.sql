BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Setting up Statbus for Norway"
\i samples/norway/getting-started.sql

\i samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
\i samples/norway/brreg/create-import-definition-underenhet-2024.sql

-- Display summary of created definitions
SELECT slug, name, note, valid_time_from, strategy, valid, validation_error
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
SELECT jsonb_pretty(public.remove_ephemeral_data_from_hierarchy(definition_snapshot)) FROM public.import_job WHERE slug = 'import_lu_2015_sht' ORDER BY slug;

\d public.import_es_2015_sht_upload
\d public.import_es_2015_sht_data

\echo 'Definition snapshot for import_es_2015_sht:'
SELECT jsonb_pretty(public.remove_ephemeral_data_from_hierarchy(definition_snapshot)) FROM public.import_job WHERE slug = 'import_es_2015_sht' ORDER BY slug;
-- 
-- Display the definition snapshot for one job (optional, can be large)
-- SELECT slug, definition_snapshot FROM public.import_job WHERE slug = 'import_lu_2015_sht' ORDER BY slug;

-- Verify user context is set correctly for import jobs
\echo "Verifying user context for import jobs"
SELECT slug,
       (SELECT email FROM public.user WHERE id = user_id) AS user_email
FROM public.import_job
WHERE slug = 'import_lu_2015_sht'
ORDER BY slug;

\echo "Loading historical units"

\copy public.import_lu_2015_sht_upload FROM 'samples/norway/small-history/2015-enheter.csv' WITH CSV HEADER;

\echo Processing tasks for import_lu_2015_sht
CALL worker.process_tasks(p_queue => 'import');
\copy public.import_lu_2016_sht_upload FROM 'samples/norway/small-history/2016-enheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_lu_2016_sht with DEBUG1
CALL worker.process_tasks(p_queue => 'import');

\copy public.import_lu_2017_sht_upload FROM 'samples/norway/small-history/2017-enheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_lu_2017_sht
CALL worker.process_tasks(p_queue => 'import');

\copy public.import_lu_2018_sht_upload FROM 'samples/norway/small-history/2018-enheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_lu_2018_sht
CALL worker.process_tasks(p_queue => 'import');

\copy public.import_es_2015_sht_upload FROM 'samples/norway/small-history/2015-underenheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_es_2015_sht
CALL worker.process_tasks(p_queue => 'import');

\copy public.import_es_2016_sht_upload FROM 'samples/norway/small-history/2016-underenheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_es_2016_sht
CALL worker.process_tasks(p_queue => 'import');

\copy public.import_es_2017_sht_upload FROM 'samples/norway/small-history/2017-underenheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_es_2017_sht
CALL worker.process_tasks(p_queue => 'import');

\copy public.import_es_2018_sht_upload FROM 'samples/norway/small-history/2018-underenheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_es_2018_sht
CALL worker.process_tasks(p_queue => 'import');

\echo Check import job state before import
SELECT state, count(*) FROM import_job GROUP BY state;

\echo Check data row state before import (should be empty as worker hasn't run prepare)
SELECT state, count(*) FROM public.import_lu_2015_sht_data GROUP BY state;

\echo Check data row state before import (should be empty as worker hasn't run prepare)
SELECT state, count(*) FROM public.import_es_2015_sht_data GROUP BY state;

\echo Check the states of the import job tasks.
select queue,t.command,state,error from worker.tasks as t join worker.command_registry as c on t.command = c.command where t.command = 'import_job_process' order by priority;
select slug, state, error is not null as failed,total_rows,imported_rows, import_completed_pct from public.import_job ORDER BY slug;

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

\echo "Debug: BOBILER AS - Legal Unit (tax_ident 876278812) segments in public.legal_unit"
WITH target_lu_base AS (
    SELECT xi.legal_unit_id AS id
    FROM public.external_ident xi
    JOIN public.external_ident_type xit ON xi.type_id = xit.id
    WHERE xit.code = 'tax_ident' AND xi.ident = '876278812' AND xi.legal_unit_id IS NOT NULL
    LIMIT 1
)
SELECT
    lu.valid_from, lu.valid_to, lu.name,
    sec.code AS sector_code,
    lf.code AS legal_form_code,
    lu.edit_comment,
    lu.primary_for_enterprise
FROM public.legal_unit lu
JOIN target_lu_base tlb ON lu.id = tlb.id
LEFT JOIN public.sector sec ON lu.sector_id = sec.id
LEFT JOIN public.legal_form lf ON lu.legal_form_id = lf.id
ORDER BY lu.valid_from;

\echo "Debug: BOBILER AS - Establishment (tax_ident 929895711) segments in public.establishment"
WITH target_est_base AS (
    SELECT xi.establishment_id AS id
    FROM public.external_ident xi
    JOIN public.external_ident_type xit ON xi.type_id = xit.id
    WHERE xit.code = 'tax_ident' AND xi.ident = '929895711' AND xi.establishment_id IS NOT NULL
    LIMIT 1
)
SELECT
    est.valid_from, est.valid_to, est.name,
    (SELECT lu_ei.ident FROM public.legal_unit lu JOIN public.external_ident lu_ei ON lu.id = lu_ei.legal_unit_id JOIN public.external_ident_type lu_eit ON lu_ei.type_id = lu_eit.id WHERE lu.id = est.legal_unit_id AND lu_eit.code = 'tax_ident' LIMIT 1) AS legal_unit_tax_ident,
    est.primary_for_legal_unit,
    est.primary_for_enterprise,
    est.edit_comment
FROM public.establishment est
JOIN target_est_base teb ON est.id = teb.id
ORDER BY est.valid_from;

\echo "Debug: BOBILER AS - Activity segments for Establishment (tax_ident 929895711) in public.activity"
WITH target_est_base AS (
    SELECT xi.establishment_id AS id
    FROM public.external_ident xi
    JOIN public.external_ident_type xit ON xi.type_id = xit.id
    WHERE xit.code = 'tax_ident' AND xi.ident = '929895711' AND xi.establishment_id IS NOT NULL
    LIMIT 1
)
SELECT
    act.valid_from, act.valid_to,
    ac.code AS activity_category_code,
    ac.path AS activity_category_path,
    act.type, act.edit_comment
FROM public.activity act
JOIN target_est_base teb ON act.establishment_id = teb.id
JOIN public.activity_category ac ON act.category_id = ac.id
ORDER BY act.valid_from, act.type;

\echo "Checking for Row-level errors for all import jobs:"

\echo "Row-level errors for job import_es_2015_sht (table import_es_2015_sht_data):"
SELECT row_id, state, errors, invalid_codes, merge_status,
       tax_ident_raw::TEXT AS tax_ident,
       name_raw::TEXT AS name,
       legal_unit_tax_ident_raw::TEXT AS legal_unit_tax_ident
FROM public.import_es_2015_sht_data
WHERE state = 'error' OR errors IS DISTINCT FROM '{}'::jsonb
ORDER BY row_id;

\echo "Row-level errors for job import_es_2016_sht (table import_es_2016_sht_data):"
SELECT row_id, state, errors, invalid_codes, merge_status,
       tax_ident_raw::TEXT AS tax_ident,
       name_raw::TEXT AS name,
       legal_unit_tax_ident_raw::TEXT AS legal_unit_tax_ident
FROM public.import_es_2016_sht_data
WHERE state = 'error' OR errors IS DISTINCT FROM '{}'::jsonb
ORDER BY row_id;

\echo "Row-level errors for job import_es_2017_sht (table import_es_2017_sht_data):"
SELECT row_id, state, errors, invalid_codes, merge_status,
       tax_ident_raw::TEXT AS tax_ident,
       name_raw::TEXT AS name,
       legal_unit_tax_ident_raw::TEXT AS legal_unit_tax_ident
FROM public.import_es_2017_sht_data
WHERE state = 'error' OR errors IS DISTINCT FROM '{}'::jsonb
ORDER BY row_id;

\echo "Row-level errors for job import_es_2018_sht (table import_es_2018_sht_data):"
SELECT row_id, state, errors, invalid_codes, merge_status,
       tax_ident_raw::TEXT AS tax_ident,
       name_raw::TEXT AS name,
       legal_unit_tax_ident_raw::TEXT AS legal_unit_tax_ident
FROM public.import_es_2018_sht_data
WHERE state = 'error' OR errors IS DISTINCT FROM '{}'::jsonb
ORDER BY row_id;

\echo "Row-level errors for job import_lu_2015_sht (table import_lu_2015_sht_data):"
SELECT row_id, state, errors, invalid_codes, merge_status,
       tax_ident_raw::TEXT AS tax_ident,
       name_raw::TEXT AS name
FROM public.import_lu_2015_sht_data
WHERE state = 'error' OR errors IS DISTINCT FROM '{}'::jsonb
ORDER BY row_id;

\echo "Row-level errors for job import_lu_2016_sht (table import_lu_2016_sht_data):"
SELECT row_id, state, errors, invalid_codes, merge_status,
       tax_ident_raw::TEXT AS tax_ident,
       name_raw::TEXT AS name
FROM public.import_lu_2016_sht_data
WHERE state = 'error' OR errors IS DISTINCT FROM '{}'::jsonb
ORDER BY row_id;

\echo "Row-level errors for job import_lu_2017_sht (table import_lu_2017_sht_data):"
SELECT row_id, state, errors, invalid_codes, merge_status,
       tax_ident_raw::TEXT AS tax_ident,
       name_raw::TEXT AS name
FROM public.import_lu_2017_sht_data
WHERE state = 'error' OR errors IS DISTINCT FROM '{}'::jsonb
ORDER BY row_id;

\echo "Row-level errors for job import_lu_2018_sht (table import_lu_2018_sht_data):"
SELECT row_id, state, errors, invalid_codes, merge_status,
       tax_ident_raw::TEXT AS tax_ident,
       name_raw::TEXT AS name
FROM public.import_lu_2018_sht_data
WHERE state = 'error' OR errors IS DISTINCT FROM '{}'::jsonb
ORDER BY row_id;

\echo Check the state of all tasks before running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

-- Once the Imports are finished, then all the analytics can be processed, but only once.
CALL worker.process_tasks(p_queue => 'analytics');

\echo Check the state of all tasks after running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo Run any remaining tasks, there should be none.
CALL worker.process_tasks();

\echo Check the state of all tasks after running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

\echo Overview of statistical units, but not details, there are too many units.
SELECT valid_from
     , valid_to
     , name
     , external_idents ->> 'tax_ident' AS tax_ident
     , unit_type
 FROM public.statistical_unit
 ORDER BY name, unit_type, valid_from, valid_to, external_idents ->> 'tax_ident';


\echo Getting statistical_units after upload
\x
SELECT valid_from
     , valid_to
     , valid_until
     , unit_type
     , external_idents
     , jsonb_pretty(
          public.remove_ephemeral_data_from_hierarchy(
          to_jsonb(statistical_unit.*)
          -'valid_from'
          -'valid_to'
          -'unit_type'
          -'external_idents'
          -'stats'
          -'stats_summary'
          -'report_partition_seq'
          )
     ) AS statistical_unit_data
     , jsonb_pretty(stats) AS stats
     , jsonb_pretty(stats_summary) AS stats_summary
 FROM public.statistical_unit
 ORDER BY valid_from, valid_to, unit_type, external_idents ->> 'tax_ident';
\x


\echo '--- Generating query plans for review ---'
SET client_min_messages = error;
ANALYZE;
RESET client_min_messages;
\o test/expected/explain/303_import_jobs_for_norway_small_history-timepoints.txt
EXPLAIN (COSTS FALSE) SELECT * FROM public.timepoints;
\o test/expected/explain/303_import_jobs_for_norway_small_history-timesegments_def.txt
EXPLAIN (COSTS FALSE) SELECT * FROM public.timesegments_def;
\o test/expected/explain/303_import_jobs_for_norway_small_history-timeline_establishment_def.txt
EXPLAIN (COSTS FALSE) SELECT * FROM public.timeline_establishment_def;
\o test/expected/explain/303_import_jobs_for_norway_small_history-timeline_legal_unit_def.txt
EXPLAIN (COSTS FALSE) SELECT * FROM public.timeline_legal_unit_def;
\o test/expected/explain/303_import_jobs_for_norway_small_history-timeline_enterprise_def.txt
EXPLAIN (COSTS FALSE) SELECT * FROM public.timeline_enterprise_def;
\o test/expected/explain/303_import_jobs_for_norway_small_history-statistical_unit_def.txt
EXPLAIN (COSTS FALSE) SELECT * FROM public.statistical_unit_def;
\o

RESET client_min_messages;

\i test/rollback_unless_persist_is_specified.sql

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
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

\copy public.import_lu_2017_sht_upload FROM 'samples/norway/small-history/2017-enheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_lu_2017_sht
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

\copy public.import_lu_2018_sht_upload FROM 'samples/norway/small-history/2018-enheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_lu_2018_sht
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

\copy public.import_es_2015_sht_upload FROM 'samples/norway/small-history/2015-underenheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_es_2015_sht
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

\copy public.import_es_2016_sht_upload FROM 'samples/norway/small-history/2016-underenheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_es_2016_sht
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

\copy public.import_es_2017_sht_upload FROM 'samples/norway/small-history/2017-underenheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_es_2017_sht
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

\copy public.import_es_2018_sht_upload FROM 'samples/norway/small-history/2018-underenheter.csv' WITH CSV HEADER;
\echo Processing tasks for import_es_2018_sht
--SET client_min_messages TO DEBUG1;
CALL worker.process_tasks(p_queue => 'import');
--SET client_min_messages TO NOTICE;

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
    lu.valid_from, lu.valid_to, lu.valid_after, lu.name,
    sec.code AS sector_code,
    lf.code AS legal_form_code,
    lu.edit_comment, lu.active,
    lu.primary_for_enterprise
FROM public.legal_unit lu
JOIN target_lu_base tlb ON lu.id = tlb.id
LEFT JOIN public.sector sec ON lu.sector_id = sec.id
LEFT JOIN public.legal_form lf ON lu.legal_form_id = lf.id
ORDER BY lu.valid_after;

\echo "Debug: BOBILER AS - Establishment (tax_ident 929895711) segments in public.establishment"
WITH target_est_base AS (
    SELECT xi.establishment_id AS id
    FROM public.external_ident xi
    JOIN public.external_ident_type xit ON xi.type_id = xit.id
    WHERE xit.code = 'tax_ident' AND xi.ident = '929895711' AND xi.establishment_id IS NOT NULL
    LIMIT 1
)
SELECT
    est.valid_from, est.valid_to, est.valid_after, est.name,
    (SELECT lu_ei.ident FROM public.legal_unit lu JOIN public.external_ident lu_ei ON lu.id = lu_ei.legal_unit_id JOIN public.external_ident_type lu_eit ON lu_ei.type_id = lu_eit.id WHERE lu.id = est.legal_unit_id AND lu_eit.code = 'tax_ident' LIMIT 1) AS legal_unit_tax_ident,
    est.primary_for_legal_unit,
    est.primary_for_enterprise,
    est.edit_comment, est.active
FROM public.establishment est
JOIN target_est_base teb ON est.id = teb.id
ORDER BY est.valid_after;

\echo "Debug: BOBILER AS - Activity segments for Establishment (tax_ident 929895711) in public.activity"
WITH target_est_base AS (
    SELECT xi.establishment_id AS id
    FROM public.external_ident xi
    JOIN public.external_ident_type xit ON xi.type_id = xit.id
    WHERE xit.code = 'tax_ident' AND xi.ident = '929895711' AND xi.establishment_id IS NOT NULL
    LIMIT 1
)
SELECT
    act.valid_from, act.valid_to, act.valid_after,
    ac.code AS activity_category_code,
    ac.path AS activity_category_path,
    act.type, act.edit_comment
FROM public.activity act
JOIN target_est_base teb ON act.establishment_id = teb.id
JOIN public.activity_category ac ON act.category_id = ac.id
ORDER BY act.valid_after, act.type;

\echo "Checking for Row-level errors for all import jobs:"

\echo "Row-level errors for job import_es_2015_sht (table import_es_2015_sht_data):"
SELECT row_id, state, error,
       tax_ident::TEXT AS tax_ident,
       name::TEXT AS name,
       legal_unit_tax_ident::TEXT AS legal_unit_tax_ident
FROM public.import_es_2015_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo "Row-level errors for job import_es_2016_sht (table import_es_2016_sht_data):"
SELECT row_id, state, error,
       tax_ident::TEXT AS tax_ident,
       name::TEXT AS name,
       legal_unit_tax_ident::TEXT AS legal_unit_tax_ident
FROM public.import_es_2016_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo "Row-level errors for job import_es_2017_sht (table import_es_2017_sht_data):"
SELECT row_id, state, error,
       tax_ident::TEXT AS tax_ident,
       name::TEXT AS name,
       legal_unit_tax_ident::TEXT AS legal_unit_tax_ident
FROM public.import_es_2017_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo "Row-level errors for job import_es_2018_sht (table import_es_2018_sht_data):"
SELECT row_id, state, error,
       tax_ident::TEXT AS tax_ident,
       name::TEXT AS name,
       legal_unit_tax_ident::TEXT AS legal_unit_tax_ident
FROM public.import_es_2018_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo "Row-level errors for job import_lu_2015_sht (table import_lu_2015_sht_data):"
SELECT row_id, state, error,
       tax_ident::TEXT AS tax_ident,
       name::TEXT AS name
FROM public.import_lu_2015_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo "Row-level errors for job import_lu_2016_sht (table import_lu_2016_sht_data):"
SELECT row_id, state, error,
       tax_ident::TEXT AS tax_ident,
       name::TEXT AS name
FROM public.import_lu_2016_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo "Row-level errors for job import_lu_2017_sht (table import_lu_2017_sht_data):"
SELECT row_id, state, error,
       tax_ident::TEXT AS tax_ident,
       name::TEXT AS name
FROM public.import_lu_2017_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo "Row-level errors for job import_lu_2018_sht (table import_lu_2018_sht_data):"
SELECT row_id, state, error,
       tax_ident::TEXT AS tax_ident,
       name::TEXT AS name
FROM public.import_lu_2018_sht_data
WHERE state = 'error' OR error IS NOT NULL
ORDER BY row_id;

\echo Check the state of all tasks before running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command WHERE c.queue != 'maintenance' GROUP BY queue,state ORDER BY queue,state;

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

\echo "Checking for duplicates from enterprise_with_primary_legal_unit stage (within timeline_enterprise_def logic):"
WITH timesegments_enterprise AS (
    SELECT ts.*, en.id AS enterprise_id
    FROM public.timesegments AS ts
    INNER JOIN public.enterprise AS en
        ON ts.unit_type = 'enterprise' AND ts.unit_id = en.id
)
SELECT ten.enterprise_id, ten.valid_after AS segment_valid_after, ten.valid_to AS segment_valid_to, COUNT(*) as num_primary_lu_matches
FROM timesegments_enterprise AS ten
INNER JOIN public.timeline_legal_unit AS tlu
    ON tlu.enterprise_id = ten.enterprise_id
    AND tlu.primary_for_enterprise = true
    AND public.after_to_overlaps(ten.valid_after, ten.valid_to, tlu.valid_after, tlu.valid_to)
GROUP BY ten.enterprise_id, ten.valid_after, ten.valid_to
HAVING COUNT(*) > 1
ORDER BY ten.enterprise_id, segment_valid_after;

\echo "Checking for duplicates from enterprise_with_primary_establishment stage (within timeline_enterprise_def logic):"
WITH timesegments_enterprise AS (
    SELECT ts.*, en.id AS enterprise_id
    FROM public.timesegments AS ts
    INNER JOIN public.enterprise AS en
        ON ts.unit_type = 'enterprise' AND ts.unit_id = en.id
)
SELECT ten.enterprise_id, ten.valid_after AS segment_valid_after, ten.valid_to AS segment_valid_to, COUNT(*) as num_primary_es_matches
FROM timesegments_enterprise AS ten
INNER JOIN public.timeline_establishment AS tes
    ON tes.enterprise_id = ten.enterprise_id
    AND tes.primary_for_enterprise = true
    AND public.after_to_overlaps(ten.valid_after, ten.valid_to, tes.valid_after, tes.valid_to)
GROUP BY ten.enterprise_id, ten.valid_after, ten.valid_to
HAVING COUNT(*) > 1
ORDER BY ten.enterprise_id, segment_valid_after;

\echo "Duplicate (unit_type, unit_id, valid_after) in timeline_enterprise_def that would cause ON CONFLICT error:"
SELECT unit_type, unit_id, valid_after, COUNT(*)
FROM public.timeline_enterprise_def
GROUP BY unit_type, unit_id, valid_after
HAVING COUNT(*) > 1
ORDER BY unit_id, valid_after;

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
ORDER BY ted.unit_id, ted.valid_after, ted.valid_from NULLS FIRST, ted.valid_to NULLS FIRST, ted.name NULLS FIRST, ted.last_edit_at NULLS FIRST;

\echo "Checking for duplicates in the data that would be inserted into timeline_enterprise (simulating temp_timeline_enterprise):"
CREATE TEMP TABLE debug_temp_timeline_enterprise AS
SELECT * FROM public.timeline_enterprise_def
WHERE public.after_to_overlaps(valid_after, valid_to, '2014-12-31'::date, 'infinity'::date);

\echo "Duplicate (unit_type, unit_id, valid_after) in simulated debug_temp_timeline_enterprise:"
SELECT unit_type, unit_id, valid_after, COUNT(*)
FROM debug_temp_timeline_enterprise
GROUP BY unit_type, unit_id, valid_after
HAVING COUNT(*) > 1
ORDER BY unit_id, valid_after;

\echo "Detailed duplicate rows from simulated debug_temp_timeline_enterprise:"
WITH DuplicatedKeysInTemp AS (
    SELECT unit_type, unit_id, valid_after
    FROM debug_temp_timeline_enterprise
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
FROM debug_temp_timeline_enterprise ted
JOIN DuplicatedKeysInTemp dk ON ted.unit_type = dk.unit_type AND ted.unit_id = dk.unit_id AND ted.valid_after = dk.valid_after
ORDER BY ted.unit_id, ted.valid_after, ted.valid_from NULLS FIRST, ted.valid_to NULLS FIRST, ted.name NULLS FIRST, ted.last_edit_at NULLS FIRST;

DROP TABLE debug_temp_timeline_enterprise;

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
 ORDER BY valid_from, valid_to, unit_type, external_idents ->> 'tax_ident';
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

\i test/rollback_unless_persist_is_specified.sql

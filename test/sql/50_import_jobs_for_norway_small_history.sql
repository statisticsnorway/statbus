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
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2015_sht', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2015 Small History Test', 'This job handles the import of BRREG Hovedenhet small history test data for 2015.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2016_sht', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2016 Small History Test', 'This job handles the import of BRREG Hovedenhet small history test data for 2016.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2017_sht', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2017 Small History Test', 'This job handles the import of BRREG Hovedenhet small history test data for 2017.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_lu_2018_sht', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Hovedenhet 2018 Small History Test', 'This job handles the import of BRREG Hovedenhet small history test data for 2018.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

-- Per year jobs for underenhet
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2015_sht', '2015-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2015 Small History Test', 'This job handles the import of BRREG Underenhet small history test data for 2015.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2016_sht', '2016-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2016 Small History Test', 'This job handles the import of BRREG Underenhet small history test data for 2016.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2017_sht', '2017-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2017 Small History Test', 'This job handles the import of BRREG Underenhet small history test data for 2017.'
FROM def RETURNING slug, description, note, default_valid_from, default_valid_to, upload_table_name, data_table_name, state;

WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id,slug,default_valid_from,default_valid_to,description,note)
SELECT  def.id, 'import_es_2018_sht', '2018-01-01'::DATE, 'infinity'::DATE, 'Import Job for BRREG Underenhet 2018 Small History Test', 'This job handles the import of BRREG Underenhet small history test data for 2018.'
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

\echo "Starting manual state machine drive for job import_lu_2015_sht"
DO $$
DECLARE
    v_job_id INT;
    v_job_slug TEXT := 'import_lu_2015_sht';
    v_job_rec public.import_job;
    v_data_table_name TEXT;
    v_max_iterations INT := 30; -- Safety break for the loop
    v_iteration INT := 0;
    data_state_rec RECORD;
BEGIN
    SELECT * INTO v_job_rec FROM public.import_job WHERE slug = v_job_slug;
    IF NOT FOUND THEN
        RAISE WARNING 'Job % not found, skipping manual processing loop.', v_job_slug;
        RETURN;
    END IF;
    v_job_id := v_job_rec.id;
    v_data_table_name := v_job_rec.data_table_name;

    RAISE NOTICE 'Starting manual processing for job % (ID: %)', v_job_slug, v_job_id;
    SET client_min_messages TO DEBUG1; -- Enable DEBUG messages

    LOOP
        v_iteration := v_iteration + 1;
        IF v_iteration > v_max_iterations THEN
            RAISE WARNING 'Max iterations reached for job %, aborting loop.', v_job_slug;
            EXIT;
        END IF;

        -- Refresh job record
        SELECT * INTO v_job_rec FROM public.import_job WHERE id = v_job_id;
        RAISE NOTICE '----------------------------------------------------------------------';
        RAISE NOTICE 'Iteration % for Job % (ID: %)', v_iteration, v_job_slug, v_job_id;
        RAISE NOTICE 'Current Job State: %', v_job_rec.state;
        RAISE NOTICE 'Total Rows: %, Imported Rows: %, Error: %', v_job_rec.total_rows, v_job_rec.imported_rows, v_job_rec.error;

        RAISE NOTICE 'Data table (%): states:', v_data_table_name;
        BEGIN
            FOR data_state_rec IN EXECUTE format('SELECT state, count(*) as count FROM public.%I GROUP BY state ORDER BY state', v_data_table_name)
            LOOP
                RAISE NOTICE '  Data State %: %', data_state_rec.state, data_state_rec.count;
            END LOOP;
        EXCEPTION WHEN undefined_table THEN
            RAISE NOTICE '  Data table % not created yet.', v_data_table_name;
        WHEN others THEN
             RAISE NOTICE '  Could not query data table % states.', v_data_table_name;
        END;

        IF v_job_rec.state IN ('finished', 'rejected') THEN
            RAISE NOTICE 'Job % reached terminal state: %', v_job_slug, v_job_rec.state;
            EXIT;
        END IF;
        
        IF v_job_rec.state = 'waiting_for_review' AND v_job_rec.review THEN
             RAISE NOTICE 'Job % is waiting_for_review. Test would need manual/auto approval here.', v_job_slug;
             EXIT; 
        END IF;

        RAISE NOTICE 'Calling admin.import_job_process(%) for job %', v_job_id, v_job_slug;
        CALL admin.import_job_process(v_job_id);
        RAISE NOTICE 'Returned from admin.import_job_process for job %', v_job_slug;

        -- Display some rows from the data table for debugging
        DECLARE
            data_row RECORD;
            row_display_count INT := 0;
            max_rows_to_display INT := 5; -- Adjust as needed
            v_has_lu_col BOOLEAN := FALSE;
            v_has_est_col BOOLEAN := FALSE;
            v_select_list TEXT;
        BEGIN
            RAISE NOTICE 'Sample data from % (max % rows):', v_data_table_name, max_rows_to_display;

            -- Check if legal_unit_id column exists
            SELECT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = v_data_table_name AND column_name = 'legal_unit_id'
            ) INTO v_has_lu_col;

            -- Check if establishment_id column exists
            SELECT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = v_data_table_name AND column_name = 'establishment_id'
            ) INTO v_has_est_col;

            -- Select row_id instead of ctid
            v_select_list := 'row_id, state, last_completed_priority, error, tax_ident, name';
            IF v_has_lu_col THEN
                v_select_list := v_select_list || ', legal_unit_id';
            ELSE
                v_select_list := v_select_list || ', NULL::INTEGER AS legal_unit_id';
            END IF;

            IF v_has_est_col THEN
                v_select_list := v_select_list || ', establishment_id';
            ELSE
                v_select_list := v_select_list || ', NULL::INTEGER AS establishment_id';
            END IF;

            FOR data_row IN EXECUTE format(
                'SELECT %s FROM public.%I ORDER BY row_id LIMIT %s', -- Order by row_id
                 v_select_list, v_data_table_name, max_rows_to_display
            )
            LOOP
                RAISE NOTICE '  Row %: row_id=%, state=%, lcp=%, error=%, tax_ident=%, name=%, lu_id=%, est_id=%', -- Changed ctid to row_id
                             row_display_count, data_row.row_id, data_row.state, data_row.last_completed_priority,
                             data_row.error, data_row.tax_ident, data_row.name, data_row.legal_unit_id, data_row.establishment_id;
                row_display_count := row_display_count + 1;
            END LOOP;
            IF row_display_count = 0 THEN
                RAISE NOTICE '  No rows found in % or table does not exist yet for detailed display.', v_data_table_name;
            END IF;
        EXCEPTION
            WHEN undefined_table THEN
                RAISE NOTICE '  Data table % not created yet for detailed row display.', v_data_table_name;
            WHEN others THEN
                RAISE NOTICE '  Could not query detailed rows from data table %: %', v_data_table_name, SQLERRM;
        END;

    END LOOP;
    
    SET client_min_messages TO NOTICE; -- Reset log level

    -- After manually processing one job, run the worker for the rest
    RAISE NOTICE 'Manually processed job % (ID: %). Now running worker for other jobs.', v_job_slug, v_job_id;
    CALL worker.process_tasks(p_queue => 'import');

END;
$$;

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

\echo Check the state of all tasks before running analytics.
SELECT queue, state, count(*) FROM worker.tasks AS t JOIN worker.command_registry AS c ON t.command = c.command GROUP BY queue,state ORDER BY queue,state;

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
 ORDER BY valid_from, valid_to, name, external_idents ->> 'tax_ident', unit_type, unit_id;


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

ROLLBACK;

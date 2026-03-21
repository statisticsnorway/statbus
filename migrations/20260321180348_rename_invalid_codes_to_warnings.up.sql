BEGIN;

-- Step 1: Update import_data_column spec so new tables get 'warnings' instead of 'invalid_codes'
UPDATE public.import_data_column
SET column_name = 'warnings'
WHERE column_name = 'invalid_codes';

-- Step 2: Rename the column on all existing data tables
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT data_table_name FROM public.import_job
           WHERE data_table_name IS NOT NULL
  LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = r.data_table_name
        AND column_name = 'invalid_codes'
    ) THEN
      EXECUTE format('ALTER TABLE public.%I RENAME COLUMN invalid_codes TO warnings', r.data_table_name);
    END IF;
  END LOOP;
END $$;

-- Step 3: Update definition_snapshot JSONB in existing jobs
UPDATE public.import_job
SET definition_snapshot = jsonb_set(
  definition_snapshot,
  '{import_data_column_list}',
  (SELECT jsonb_agg(
    CASE WHEN elem->>'column_name' = 'invalid_codes'
         THEN jsonb_set(elem, '{column_name}', '"warnings"')
         ELSE elem
    END
  ) FROM jsonb_array_elements(definition_snapshot->'import_data_column_list') AS elem)
)
WHERE definition_snapshot->'import_data_column_list' @> '[{"column_name": "invalid_codes"}]';

-- Step 4: Recreate all functions with invalid_codes -> warnings

-- 4a: admin.import_job_process(integer, jsonb) - references invalid_codes column on data tables
CREATE OR REPLACE PROCEDURE admin.import_job_process(IN job_id integer, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    job public.import_job;
    next_state public.import_job_state;
    should_reschedule BOOLEAN := FALSE;
    -- Baseline captures for delta reporting
    v_old_state public.import_job_state;
    v_error_count_before integer;
    v_warning_count_before integer;
BEGIN
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', job_id;
    END IF;

    -- Capture baseline for delta calculation
    v_old_state := job.state;
    v_error_count_before := COALESCE(job.error_count, 0);
    v_warning_count_before := COALESCE(job.warning_count, 0);

    PERFORM admin.set_import_job_user_context(job_id);

    RAISE DEBUG '[Job %] Processing job in state: %', job_id, job.state;

    IF job.state NOT IN ('waiting_for_review', 'approved', 'rejected') THEN
        PERFORM id FROM public.import_job
        WHERE state = 'waiting_for_review'
          AND id <> job_id
        LIMIT 1;
        IF FOUND THEN
            RAISE DEBUG '[Job %] Blocked: another job is waiting_for_review. Will resume when review resolves.', job_id;
            RETURN;
        END IF;
    END IF;

    CASE job.state
        WHEN 'waiting_for_upload' THEN
            RAISE DEBUG '[Job %] Waiting for upload.', job_id;
            should_reschedule := FALSE;

        WHEN 'upload_completed' THEN
            RAISE DEBUG '[Job %] Transitioning to preparing_data.', job_id;
            job := admin.import_job_set_state(job, 'preparing_data');
            should_reschedule := TRUE;

        WHEN 'preparing_data' THEN
            DECLARE
                v_data_row_count BIGINT;
            BEGIN
                RAISE DEBUG '[Job %] Calling import_job_prepare.', job_id;
                PERFORM admin.import_job_prepare(job);

                EXECUTE format('SELECT COUNT(*) FROM public.%I', job.data_table_name) INTO v_data_row_count;

                UPDATE public.import_job
                SET
                    total_rows = v_data_row_count,
                    total_analysis_steps_weighted = v_data_row_count * max_analysis_priority
                WHERE id = job.id
                RETURNING * INTO job;

                RAISE DEBUG '[Job %] Recounted total_rows to % and updated total_analysis_steps_weighted.', job.id, job.total_rows;

                RAISE DEBUG '[Job %] Assigning batch_seq and transitioning rows to analysing in table %', job_id, job.data_table_name;
                PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.analysis_batch_size, FALSE, 'analysing'::public.import_data_state);

                RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                EXECUTE format('ANALYZE public.%I', job.data_table_name);

                job := admin.import_job_set_state(job, 'analysing_data');
                should_reschedule := TRUE;
            END;

        WHEN 'analysing_data' THEN
            DECLARE
                v_completed_steps_weighted BIGINT;
                v_old_step_code TEXT;
                v_error_count INTEGER;
                v_warning_count INTEGER;
            BEGIN
                RAISE DEBUG '[Job %] Starting analysis phase.', job_id;

                v_old_step_code := job.current_step_code;

                should_reschedule := admin.import_job_analysis_phase(job);

                SELECT * INTO job FROM public.import_job WHERE id = job.id;

                IF job.max_analysis_priority IS NOT NULL AND (
                    job.current_step_code IS DISTINCT FROM v_old_step_code
                    OR NOT should_reschedule
                ) THEN
                    EXECUTE format($$ SELECT COALESCE(SUM(last_completed_priority), 0) FROM public.%I WHERE state IN ('analysing', 'analysed', 'error') $$,
                        job.data_table_name)
                    INTO v_completed_steps_weighted;

                    UPDATE public.import_job
                    SET completed_analysis_steps_weighted = v_completed_steps_weighted
                    WHERE id = job.id;

                    RAISE DEBUG '[Job %] Recounted progress (step changed or phase complete): completed_analysis_steps_weighted=%', job.id, v_completed_steps_weighted;
                END IF;

                IF job.error IS NOT NULL THEN
                    RAISE WARNING '[Job %] Error detected during analysis phase: %. Transitioning to finished.', job_id, job.error;
                    job := admin.import_job_set_state(job, 'finished');
                    should_reschedule := FALSE;
                ELSIF NOT should_reschedule THEN
                    EXECUTE format($$
                      SELECT
                        COUNT(*) FILTER (WHERE state = 'error'),
                        COUNT(*) FILTER (WHERE action = 'use' AND warnings IS NOT NULL AND warnings <> '{}'::jsonb)
                      FROM public.%I
                    $$, job.data_table_name) INTO v_error_count, v_warning_count;

                    UPDATE public.import_job
                    SET error_count = v_error_count, warning_count = v_warning_count
                    WHERE id = job.id;

                    RAISE DEBUG '[Job %] Analysis complete. error_count=%, warning_count=%', job.id, v_error_count, v_warning_count;

                    IF job.review IS TRUE
                       OR (job.review IS NULL AND v_error_count > 0)
                    THEN
                        RAISE DEBUG '[Job %] Updating data rows from analysing to analysed in table % for review', job_id, job.data_table_name;
                        EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L AND action = 'use'$$, job.data_table_name, 'analysed'::public.import_data_state, 'analysing'::public.import_data_state);
                        job := admin.import_job_set_state(job, 'waiting_for_review');
                        RAISE DEBUG '[Job %] Analysis complete, waiting for review.', job_id;
                    ELSE
                        RAISE DEBUG '[Job %] Assigning batch_seq and transitioning rows to processing in table %', job_id, job.data_table_name;
                        PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.processing_batch_size, TRUE, 'processing'::public.import_data_state, TRUE);

                        RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                        EXECUTE format('ANALYZE public.%I', job.data_table_name);

                        job := admin.import_job_set_state(job, 'processing_data');
                        RAISE DEBUG '[Job %] Analysis complete, proceeding to processing.', job_id;
                        should_reschedule := TRUE;
                    END IF;
                END IF;
            END;

        WHEN 'waiting_for_review' THEN
            RAISE DEBUG '[Job %] Waiting for user review.', job_id;
            should_reschedule := FALSE;

        WHEN 'approved' THEN
            BEGIN
                RAISE DEBUG '[Job %] Approved, transitioning to processing_data.', job_id;
                RAISE DEBUG '[Job %] Assigning batch_seq and transitioning rows to processing in table % after approval', job_id, job.data_table_name;
                PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.processing_batch_size, TRUE, 'processing'::public.import_data_state, TRUE);

                RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                EXECUTE format('ANALYZE public.%I', job.data_table_name);

                job := admin.import_job_set_state(job, 'processing_data');
                should_reschedule := TRUE;
            END;

        WHEN 'rejected' THEN
            RAISE DEBUG '[Job %] Rejected, transitioning to finished.', job_id;
            job := admin.import_job_set_state(job, 'finished');
            should_reschedule := FALSE;

        WHEN 'processing_data' THEN
            BEGIN
                RAISE DEBUG '[Job %] Starting processing phase.', job_id;

                should_reschedule := admin.import_job_processing_phase(job);

                SELECT * INTO job FROM public.import_job WHERE id = job.id;

                RAISE DEBUG '[Job %] Processing phase batch complete. imported_rows: %', job.id, job.imported_rows;

                IF job.error IS NOT NULL THEN
                    RAISE WARNING '[Job %] Error detected during processing phase: %. Job already transitioned to finished.', job.id, job.error;
                    should_reschedule := FALSE;
                ELSIF NOT should_reschedule THEN
                    job := admin.import_job_set_state(job, 'finished');
                    RAISE DEBUG '[Job %] Processing complete, transitioning to finished.', job_id;
                END IF;
            END;

        WHEN 'finished' THEN
            RAISE DEBUG '[Job %] Already finished.', job_id;
            should_reschedule := FALSE;

        WHEN 'failed' THEN
            RAISE DEBUG '[Job %] Job has failed.', job_id;
            should_reschedule := FALSE;

        ELSE
            RAISE EXCEPTION 'Unexpected job state: %', job.state;
    END CASE;

    -- Info Principle: report only what THIS invocation contributed (deltas)
    SELECT * INTO job FROM public.import_job WHERE id = job_id;

    -- Always report state (non-numeric, last-value wins at parent)
    p_info := jsonb_build_object('job_state', job.state::text);

    -- Report total_rows only on the preparing_data->analysing_data transition (once per job)
    IF job.state = 'analysing_data' AND v_old_state = 'preparing_data'
       AND job.total_rows IS NOT NULL THEN
        p_info := p_info || jsonb_build_object('total_rows', job.total_rows);
    END IF;

    -- Report current_step during analysis (free from job row, differentiates children)
    IF job.current_step_code IS NOT NULL THEN
        p_info := p_info || jsonb_build_object('current_step', job.current_step_code);
    END IF;

    -- Report rows_processed at finished transition (complete summary in last step)
    IF job.state = 'finished' AND v_old_state = 'processing_data' THEN
        p_info := p_info || jsonb_build_object('rows_processed', COALESCE(job.imported_rows, 0));
    END IF;

    -- Report errors/warnings delta (set once at end of analysis)
    IF COALESCE(job.error_count, 0) > v_error_count_before THEN
        p_info := p_info || jsonb_build_object(
            'errors_found', job.error_count - v_error_count_before
        );
    END IF;
    IF COALESCE(job.warning_count, 0) > v_warning_count_before THEN
        p_info := p_info || jsonb_build_object(
            'warnings_found', job.warning_count - v_warning_count_before
        );
    END IF;

    IF should_reschedule THEN
        PERFORM admin.reschedule_import_job_process(job_id);
    END IF;
END;
$procedure$;

-- 4b: import.analyse_activity
CREATE OR REPLACE PROCEDURE import.analyse_activity(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[];
    v_job_mode public.import_mode;
    v_source_code_col_name TEXT;
    v_resolved_id_col_name_in_lookup_cte TEXT;
    v_json_key TEXT;
    v_lookup_failed_condition_sql TEXT;
    v_error_json_expr_sql TEXT;
    v_warning_json_expr_sql TEXT;
    v_parent_unit_missing_error_key TEXT;
    v_parent_unit_missing_error_message TEXT;
    v_prelim_update_count INT := 0;
    v_parent_id_check_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_activity (Batch) for step_code %: Starting analysis for batch_seq %', p_job_id, p_step_code, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    -- Get the specific step details using p_step_code from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_activity: Step with code % not found in snapshot. This should not happen if called by import_job_process_phase.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_activity: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;

    -- Determine column names and JSON key based on the step being processed
    IF p_step_code = 'primary_activity' THEN
        v_source_code_col_name := 'primary_activity_category_code_raw';
        v_resolved_id_col_name_in_lookup_cte := 'resolved_primary_activity_category_id';
        v_json_key := 'primary_activity_category_code_raw';
    ELSIF p_step_code = 'secondary_activity' THEN
        v_source_code_col_name := 'secondary_activity_category_code_raw';
        v_resolved_id_col_name_in_lookup_cte := 'resolved_secondary_activity_category_id';
        v_json_key := 'secondary_activity_category_code_raw';
    ELSE
        RAISE EXCEPTION '[Job %] analyse_activity: Invalid p_step_code provided: %. Expected ''primary_activity'' or ''secondary_activity''.', p_job_id, p_step_code;
    END IF;
    v_error_keys_to_clear_arr := ARRAY[v_json_key];

    -- SQL condition string for when the lookup for the current activity type fails
    v_lookup_failed_condition_sql := format('dt.%1$I IS NOT NULL AND l.%2$I IS NULL', v_source_code_col_name, v_resolved_id_col_name_in_lookup_cte);

    -- SQL expression string for constructing the error JSON object for the current activity type
    v_error_json_expr_sql := format('jsonb_build_object(%1$L, ''Not found'')', v_json_key);

    -- SQL expression string for constructing the warnings JSON object for the current activity type
    v_warning_json_expr_sql := format('jsonb_build_object(%1$L, dt.%2$I)', v_json_key, v_source_code_col_name);

    -- PERF: Removed IS NOT NULL from join conditions to enable hash join optimization.
    -- NULL codes won't match any category code anyway (NULL = 'x' evaluates to NULL/false).
    -- This reduces query time from O(n^2) nested loop to O(n) hash join.
    v_sql := format($$
        WITH lookups AS (
            SELECT
                dt_sub.row_id AS data_row_id,
                pac.id as resolved_primary_activity_category_id,
                sac.id as resolved_secondary_activity_category_id
            FROM public.%1$I dt_sub -- Target data table
            LEFT JOIN public.activity_category_enabled pac ON pac.code = dt_sub.primary_activity_category_code_raw
            LEFT JOIN public.activity_category_enabled sac ON sac.code = dt_sub.secondary_activity_category_code_raw
            WHERE dt_sub.batch_seq = $1
        )
        UPDATE public.%1$I dt SET -- Target data table
            primary_activity_category_id = CASE
                                               WHEN %2$L = 'primary_activity' THEN l.resolved_primary_activity_category_id
                                               ELSE dt.primary_activity_category_id
                                           END,
            secondary_activity_category_id = CASE
                                                 WHEN %2$L = 'secondary_activity' THEN l.resolved_secondary_activity_category_id
                                                 ELSE dt.secondary_activity_category_id
                                             END,
            state = 'analysing'::public.import_data_state,
            errors = dt.errors - %3$L::TEXT[],
            warnings = CASE
                                WHEN (%4$s) THEN
                                    dt.warnings || jsonb_strip_nulls(%5$s)
                                ELSE
                                    dt.warnings - %3$L::TEXT[]
                            END,
            last_completed_priority = %6$L::INTEGER
        FROM lookups l
        WHERE dt.row_id = l.data_row_id AND dt.action IS DISTINCT FROM 'skip';
    $$,
        v_data_table_name,
        p_step_code,
        v_error_keys_to_clear_arr,
        v_lookup_failed_condition_sql,
        v_warning_json_expr_sql,
        v_step.priority
    );

    RAISE DEBUG '[Job %] analyse_activity: Single-pass batch update for non-skipped rows for step % (activity issues now non-fatal for all modes): %', p_job_id, p_step_code, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_activity: Updated % non-skipped rows in single pass for step %.', p_job_id, v_update_count, p_step_code;

        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_activity: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_activity: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_activity: Error during single-pass batch update for step %: %', p_job_id, p_step_code, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_activity_batch_error', SQLERRM, 'step_code', p_step_code)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_activity: Marked job as failed due to error in step %: %', p_job_id, p_step_code, SQLERRM;
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $$, v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_activity: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_activity: Advanced last_completed_priority for % total rows in batch for step %.', p_job_id, v_skipped_update_count, p_step_code;

    RAISE DEBUG '[Job %] analyse_activity (Batch): Finished analysis for batch for step %. Errors newly marked in this step: %', p_job_id, p_step_code, v_error_count;
END;
$procedure$;

-- 4c: import.analyse_legal_unit
CREATE OR REPLACE PROCEDURE import.analyse_legal_unit(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
    v_data_table_name TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name_raw', 'legal_form_code_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw', 'status_code_raw', 'legal_unit'];
    v_warning_keys_arr TEXT[] := ARRAY['legal_form_code_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw']; -- Keys that go into warnings
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] legal_unit target step not found in snapshot', p_job_id; END IF;

    v_sql := format($$
        UPDATE %1$I dt SET
            action = 'skip'::public.import_row_action_type,
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip'
          AND NULLIF(dt.name_raw, '') IS NULL
          AND NULLIF(dt.legal_form_code_raw, '') IS NULL
          AND NULLIF(dt.sector_code_raw, '') IS NULL
          AND NULLIF(dt.unit_size_code_raw, '') IS NULL
          AND NULLIF(dt.birth_date_raw, '') IS NULL
          AND NULLIF(dt.death_date_raw, '') IS NULL
          AND dt.status_id IS NULL; -- status_id is resolved from status_code_raw in a prior step
    $$, v_data_table_name, v_step.priority);
    EXECUTE v_sql USING p_batch_seq;

    -- Step 1: Materialize the batch data into a temp table for performance.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
        SELECT dt.row_id, dt.operation, dt.name_raw, dt.status_id, dt.legal_unit_id,
               dt.legal_form_code_raw, dt.sector_code_raw, dt.unit_size_code_raw,
               dt.birth_date_raw, dt.death_date_raw
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;

    ANALYZE t_batch_data;

    -- Step 2: Resolve all distinct codes and dates from the batch in separate temp tables.
    IF to_regclass('pg_temp.t_resolved_codes') IS NOT NULL THEN DROP TABLE t_resolved_codes; END IF;
    CREATE TEMP TABLE t_resolved_codes ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT legal_form_code_raw AS code, 'legal_form' AS type FROM t_batch_data WHERE NULLIF(legal_form_code_raw, '') IS NOT NULL
        UNION SELECT sector_code_raw AS code, 'sector' AS type FROM t_batch_data WHERE NULLIF(sector_code_raw, '') IS NOT NULL
        UNION SELECT unit_size_code_raw AS code, 'unit_size' AS type FROM t_batch_data WHERE NULLIF(unit_size_code_raw, '') IS NOT NULL
    )
    SELECT
        dc.code, dc.type, COALESCE(lf.id, s.id, us.id) AS resolved_id
    FROM distinct_codes dc
    LEFT JOIN public.legal_form_enabled lf ON dc.type = 'legal_form' AND dc.code = lf.code
    LEFT JOIN public.sector_enabled s ON dc.type = 'sector' AND dc.code = s.code
    LEFT JOIN public.unit_size_enabled us ON dc.type = 'unit_size' AND dc.code = us.code;

    IF to_regclass('pg_temp.t_resolved_dates') IS NOT NULL THEN DROP TABLE t_resolved_dates; END IF;
    CREATE TEMP TABLE t_resolved_dates ON COMMIT DROP AS
    WITH distinct_dates AS (
        SELECT birth_date_raw AS date_string FROM t_batch_data WHERE NULLIF(birth_date_raw, '') IS NOT NULL
        UNION SELECT death_date_raw AS date_string FROM t_batch_data WHERE NULLIF(death_date_raw, '') IS NOT NULL
    )
    SELECT dd.date_string, sc.p_value, sc.p_error_message
    FROM distinct_dates dd
    LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE;

    ANALYZE t_resolved_codes;
    ANALYZE t_resolved_dates;

    -- Step 3: Perform the main update using the pre-resolved lookup tables.
    v_sql := format($SQL$
        WITH lookups AS (
            SELECT
                bd.row_id as data_row_id,
                bd.operation, bd.name_raw as name, bd.status_id, bd.legal_unit_id,
                bd.legal_form_code_raw as legal_form_code,
                bd.sector_code_raw as sector_code,
                bd.unit_size_code_raw as unit_size_code,
                bd.birth_date_raw as birth_date,
                bd.death_date_raw as death_date,
                lf.resolved_id as resolved_legal_form_id,
                s.resolved_id as resolved_sector_id,
                us.resolved_id as resolved_unit_size_id,
                b_date.p_value as resolved_typed_birth_date,
                b_date.p_error_message as birth_date_error_msg,
                d_date.p_value as resolved_typed_death_date,
                d_date.p_error_message as death_date_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes lf ON bd.legal_form_code_raw = lf.code AND lf.type = 'legal_form'
            LEFT JOIN t_resolved_codes s ON bd.sector_code_raw = s.code AND s.type = 'sector'
            LEFT JOIN t_resolved_codes us ON bd.unit_size_code_raw = us.code AND us.type = 'unit_size'
            LEFT JOIN t_resolved_dates b_date ON bd.birth_date_raw = b_date.date_string
            LEFT JOIN t_resolved_dates d_date ON bd.death_date_raw = d_date.date_string
        )
        UPDATE public.%1$I dt SET
            name = NULLIF(trim(l.name), ''),
            legal_form_id = l.resolved_legal_form_id,
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            birth_date = l.resolved_typed_birth_date,
            death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN l.legal_unit_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'error'::public.import_data_state
                        WHEN l.status_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN l.legal_unit_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'skip'::public.import_row_action_type
                        WHEN l.status_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN l.legal_unit_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN
                            dt.errors || jsonb_build_object('name_raw', 'Missing required name for legal unit.')
                        WHEN l.status_id IS NULL THEN
                            dt.errors || jsonb_build_object('status_code_raw', 'Status code could not be resolved and is required for this operation.')
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            warnings = CASE
                                WHEN (l.operation = 'update' OR NULLIF(trim(l.name), '') IS NOT NULL) AND l.status_id IS NOT NULL THEN
                                    jsonb_strip_nulls(
                                     (dt.warnings - %3$L::TEXT[]) ||
                                     jsonb_build_object('legal_form_code_raw', CASE WHEN NULLIF(l.legal_form_code, '') IS NOT NULL AND l.resolved_legal_form_id IS NULL THEN l.legal_form_code ELSE NULL END) ||
                                     jsonb_build_object('sector_code_raw', CASE WHEN NULLIF(l.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN l.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code_raw', CASE WHEN NULLIF(l.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN l.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date_raw', CASE WHEN NULLIF(l.birth_date, '') IS NOT NULL AND l.birth_date_error_msg IS NOT NULL THEN l.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date_raw', CASE WHEN NULLIF(l.death_date, '') IS NOT NULL AND l.death_date_error_msg IS NOT NULL THEN l.death_date ELSE NULL END)
                                    )
                                ELSE dt.warnings
                            END
        FROM lookups l
        WHERE dt.row_id = l.data_row_id;
    $SQL$,
        v_data_table_name,             -- %1$I
        v_error_keys_to_clear_arr,     -- %2$L
        v_warning_keys_arr            -- %3$L
    );

    BEGIN
        RAISE DEBUG '[Job %] analyse_legal_unit: Updating batch data with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_unit: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_legal_unit_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L',
                    v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_legal_unit: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    BEGIN
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_legal_unit: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_legal_unit: Estimated errors in this step for batch: %', p_job_id, v_error_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Error during error count: %', p_job_id, SQLERRM;
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_legal_unit');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    -- Resolve primary_for_enterprise conflicts (best-effort)
    BEGIN
        RAISE DEBUG '[Job %] analyse_legal_unit: Resolving primary_for_enterprise conflicts within the batch in %s.', p_job_id, v_data_table_name;
        v_sql := format($$
            WITH BatchPrimaries AS (
                SELECT
                    src.row_id,
                    FIRST_VALUE(src.row_id) OVER (
                        PARTITION BY src.enterprise_id, daterange(src.valid_from, src.valid_until, '[)')
                        ORDER BY src.legal_unit_id ASC NULLS LAST, src.row_id ASC
                    ) as winner_row_id
                FROM public.%1$I src
                WHERE src.batch_seq = $1
                  AND src.primary_for_enterprise = true
                  AND src.enterprise_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET primary_for_enterprise = false
            FROM BatchPrimaries bp
            WHERE dt.row_id = bp.row_id
              AND dt.row_id != bp.winner_row_id
              AND dt.primary_for_enterprise = true;
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] analyse_legal_unit: Resolving primary conflicts with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Non-fatal error during primary conflict resolution: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Finished analysis for batch.', p_job_id;
END;
$procedure$;

-- 4d: import.analyse_establishment
CREATE OR REPLACE PROCEDURE import.analyse_establishment(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw', 'status_code_raw', 'establishment'];
    v_warning_keys_arr TEXT[] := ARRAY['sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_establishment (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'establishment';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] establishment target not found in snapshot', p_job_id; END IF;

    -- Step 1: Materialize the batch data into a temp table for performance.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
        SELECT dt.row_id, dt.operation, dt.name_raw, dt.status_id, establishment_id,
               dt.sector_code_raw, dt.unit_size_code_raw, dt.birth_date_raw, dt.death_date_raw
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;

    ANALYZE t_batch_data;

    -- Step 2: Resolve all distinct codes and dates from the batch in separate temp tables.
    IF to_regclass('pg_temp.t_resolved_codes') IS NOT NULL THEN DROP TABLE t_resolved_codes; END IF;
    CREATE TEMP TABLE t_resolved_codes ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT sector_code_raw AS code, 'sector' AS type FROM t_batch_data WHERE NULLIF(sector_code_raw, '') IS NOT NULL
        UNION SELECT unit_size_code_raw AS code, 'unit_size' AS type FROM t_batch_data WHERE NULLIF(unit_size_code_raw, '') IS NOT NULL
    )
    SELECT
        dc.code, dc.type, COALESCE(s.id, us.id) AS resolved_id
    FROM distinct_codes dc
    LEFT JOIN public.sector_enabled s ON dc.type = 'sector' AND dc.code = s.code
    LEFT JOIN public.unit_size_enabled us ON dc.type = 'unit_size' AND dc.code = us.code;

    IF to_regclass('pg_temp.t_resolved_dates') IS NOT NULL THEN DROP TABLE t_resolved_dates; END IF;
    CREATE TEMP TABLE t_resolved_dates ON COMMIT DROP AS
    WITH distinct_dates AS (
        SELECT birth_date_raw AS date_string FROM t_batch_data WHERE NULLIF(birth_date_raw, '') IS NOT NULL
        UNION SELECT death_date_raw AS date_string FROM t_batch_data WHERE NULLIF(death_date_raw, '') IS NOT NULL
    )
    SELECT dd.date_string, sc.p_value, sc.p_error_message
    FROM distinct_dates dd
    LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE;

    ANALYZE t_resolved_codes;
    ANALYZE t_resolved_dates;

    -- Step 3: Perform the main update using the pre-resolved lookup tables.
    v_sql := format($SQL$
        WITH lookups AS (
            SELECT
                bd.row_id as data_row_id,
                bd.operation, bd.name_raw as name, bd.status_id, bd.establishment_id,
                bd.sector_code_raw as sector_code, bd.unit_size_code_raw as unit_size_code,
                bd.birth_date_raw as birth_date, bd.death_date_raw as death_date,
                s.resolved_id as resolved_sector_id,
                us.resolved_id as resolved_unit_size_id,
                b_date.p_value as resolved_typed_birth_date,
                b_date.p_error_message as birth_date_error_msg,
                d_date.p_value as resolved_typed_death_date,
                d_date.p_error_message as death_date_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes s ON bd.sector_code_raw = s.code AND s.type = 'sector'
            LEFT JOIN t_resolved_codes us ON bd.unit_size_code_raw = us.code AND us.type = 'unit_size'
            LEFT JOIN t_resolved_dates b_date ON bd.birth_date_raw = b_date.date_string
            LEFT JOIN t_resolved_dates d_date ON bd.death_date_raw = d_date.date_string
        )
        UPDATE public.%1$I dt SET
            name = NULLIF(trim(l.name), ''),
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            birth_date = l.resolved_typed_birth_date,
            death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN l.establishment_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'error'::public.import_data_state
                        WHEN l.status_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN l.establishment_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'skip'::public.import_row_action_type
                        WHEN l.status_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN l.establishment_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN
                            dt.errors || jsonb_build_object('name_raw', 'Missing required name')
                        WHEN l.status_id IS NULL THEN
                            dt.errors || jsonb_build_object('status_code_raw', 'Status code could not be resolved and is required for this operation.')
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            warnings = CASE
                                WHEN (l.operation = 'update' OR NULLIF(trim(l.name), '') IS NOT NULL) AND l.status_id IS NOT NULL THEN
                                    jsonb_strip_nulls(
                                     (dt.warnings - %3$L::TEXT[]) ||
                                     jsonb_build_object('sector_code_raw', CASE WHEN NULLIF(l.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN l.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code_raw', CASE WHEN NULLIF(l.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN l.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date_raw', CASE WHEN NULLIF(l.birth_date, '') IS NOT NULL AND l.birth_date_error_msg IS NOT NULL THEN l.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date_raw', CASE WHEN NULLIF(l.death_date, '') IS NOT NULL AND l.death_date_error_msg IS NOT NULL THEN l.death_date ELSE NULL END)
                                    )
                                ELSE dt.warnings
                            END
        FROM lookups l
        WHERE dt.row_id = l.data_row_id;
    $SQL$,
        v_data_table_name,            -- %1$I
        v_error_keys_to_clear_arr,    -- %2$L
        v_warning_keys_arr            -- %3$L
    );

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_establishment: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_establishment: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_establishment_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L',
                    v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_establishment: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    BEGIN
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_establishment: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_establishment: Estimated errors in this step for batch: %', p_job_id, v_error_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_establishment: Error during error count: %', p_job_id, SQLERRM;
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_establishment');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_establishment: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    -- Resolve primary conflicts (best-effort)
    BEGIN
        IF v_job.definition_snapshot->'import_definition'->>'mode' = 'establishment_formal' THEN
            v_sql := format($$
                WITH BatchPrimaries AS (
                    SELECT src.row_id, FIRST_VALUE(src.row_id) OVER (PARTITION BY src.legal_unit_id, daterange(src.valid_from, src.valid_until, '[)') ORDER BY src.establishment_id ASC NULLS LAST, src.row_id ASC) as winner_row_id
                    FROM public.%1$I src WHERE src.batch_seq = $1 AND src.primary_for_legal_unit = true AND src.legal_unit_id IS NOT NULL
                )
                UPDATE public.%1$I dt SET primary_for_legal_unit = false FROM BatchPrimaries bp
                WHERE dt.row_id = bp.row_id AND dt.row_id != bp.winner_row_id AND dt.primary_for_legal_unit = true;
            $$, v_data_table_name);
            RAISE DEBUG '[Job %] analyse_establishment: Resolving primary conflicts (formal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;
        ELSIF v_job.definition_snapshot->'import_definition'->>'mode' = 'establishment_informal' THEN
            v_sql := format($$
                WITH BatchPrimaries AS (
                    SELECT src.row_id, FIRST_VALUE(src.row_id) OVER (PARTITION BY src.enterprise_id, daterange(src.valid_from, src.valid_until, '[)') ORDER BY src.establishment_id ASC NULLS LAST, src.row_id ASC) as winner_row_id
                    FROM public.%1$I src WHERE src.batch_seq = $1 AND src.primary_for_enterprise = true AND src.enterprise_id IS NOT NULL
                )
                UPDATE public.%1$I dt SET primary_for_enterprise = false FROM BatchPrimaries bp
                WHERE dt.row_id = bp.row_id AND dt.row_id != bp.winner_row_id AND dt.primary_for_enterprise = true;
            $$, v_data_table_name);
            RAISE DEBUG '[Job %] analyse_establishment: Resolving primary conflicts (informal) with SQL: %', p_job_id, v_sql;
            EXECUTE v_sql USING p_batch_seq;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_establishment: Non-fatal error during primary conflict resolution: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_establishment (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$procedure$;

-- 4e: import.analyse_location
CREATE OR REPLACE PROCEDURE import.analyse_location(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_error_json_expr_sql TEXT; -- For dt.error (fatal) - though this step makes them non-fatal
    v_warnings_json_expr_sql TEXT; -- For dt.warnings (non-fatal)
    v_error_keys_to_clear_arr TEXT[];
    v_warning_keys_to_clear_arr TEXT[];
    v_skipped_update_count INT;
    error_message TEXT;
    v_error_condition_sql TEXT; -- For non-fatal warnings
    v_fatal_error_condition_sql TEXT; -- For fatal errors like missing country
    v_fatal_error_json_expr_sql TEXT; -- For fatal error messages
    v_address_present_condition_sql TEXT; -- To check if any address part is present
    v_default_country_id INT; -- Default country from settings for region validation

    -- For coordinate validation
    v_coord_cast_error_json_expr_sql TEXT;
    v_coord_range_error_json_expr_sql TEXT;
    v_postal_coord_present_error_json_expr_sql TEXT := $$'{}'::jsonb$$; -- Default to SQL literal for empty JSONB
    v_coord_invalid_value_json_expr_sql TEXT;
    v_any_coord_error_condition_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_location (Batch) for step_code %: Starting analysis for batch_seq %', p_job_id, p_step_code, p_batch_seq;

    -- Load default country from settings for region validation - FAIL FAST if not configured
    SELECT country_id INTO v_default_country_id FROM public.settings LIMIT 1;
    IF v_default_country_id IS NULL THEN
        RAISE EXCEPTION '[Job %] analyse_location: No country_id configured in settings table. System must be configured with a default country before processing location data. Run getting-started setup first.', p_job_id;
    END IF;

    -- Validate that the country_id actually exists in the country table
    IF NOT EXISTS (SELECT 1 FROM public.country WHERE id = v_default_country_id) THEN
        RAISE EXCEPTION '[Job %] analyse_location: Invalid country_id % in settings table. Country does not exist in country table.', p_job_id, v_default_country_id;
    END IF;

    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_location: Step with code % not found in snapshot.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_location: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;

    IF p_step_code = 'physical_location' THEN
        v_error_keys_to_clear_arr := ARRAY[
            'physical_region_code_raw',
            'physical_country_iso_2_raw',
            'physical_latitude_raw', -- Error key for latitude issues
            'physical_longitude_raw', -- Error key for longitude issues
            'physical_altitude_raw' -- Error key for altitude issues
        ];
        v_warning_keys_to_clear_arr := ARRAY['physical_region_code_raw', 'physical_country_iso_2_raw', 'physical_latitude_raw', 'physical_longitude_raw', 'physical_altitude_raw'];
        v_address_present_condition_sql := $$
            (NULLIF(dt.physical_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.physical_address_part2_raw, '') IS NOT NULL OR NULLIF(dt.physical_address_part3_raw, '') IS NOT NULL OR
             NULLIF(dt.physical_postcode_raw, '') IS NOT NULL OR NULLIF(dt.physical_postplace_raw, '') IS NOT NULL OR NULLIF(dt.physical_region_code_raw, '') IS NOT NULL)
        $$;
        v_fatal_error_condition_sql := format($$
            (%s AND (NULLIF(dt.physical_country_iso_2_raw, '') IS NULL OR l.resolved_physical_country_id IS NULL))
        $$, v_address_present_condition_sql);
        v_fatal_error_json_expr_sql := $$
            jsonb_build_object('physical_country_iso_2_raw', 'Country is required and must be valid when other physical address details are provided.')
        $$;
        v_error_condition_sql := format($$
            -- Invalid region codes for any country (both domestic and foreign)
            (dt.physical_region_code_raw IS NOT NULL AND l.resolved_physical_region_id IS NULL) OR
            -- Missing region warnings for domestic countries (when country is present and domestic)
            (dt.physical_region_code_raw IS NULL AND l.resolved_physical_country_id IS NOT DISTINCT FROM %1$L AND l.resolved_physical_country_id IS NOT NULL) OR
            -- Country check is now fatal if address parts are present, otherwise non-fatal for warnings
            (dt.physical_country_iso_2_raw IS NOT NULL AND l.resolved_physical_country_id IS NULL AND NOT (%2$s)) OR
            (dt.physical_latitude_raw IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL) OR
            (dt.physical_longitude_raw IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL) OR
            (dt.physical_altitude_raw IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL)
        $$, v_default_country_id, v_address_present_condition_sql); -- Format with default_country_id and address_present check

        v_warnings_json_expr_sql := format($$
            CASE
                WHEN dt.physical_region_code_raw IS NOT NULL AND l.resolved_physical_region_id IS NULL THEN jsonb_build_object('physical_region_code_raw', dt.physical_region_code_raw)  -- Invalid region code
                WHEN dt.physical_region_code_raw IS NULL AND dt.physical_country_iso_2_raw IS NOT NULL AND l.resolved_physical_country_id IS NOT DISTINCT FROM %1$L AND l.resolved_physical_country_id IS NOT NULL THEN jsonb_build_object('physical_region_code_raw', NULL)  -- Missing region for domestic country (include key with NULL)
                ELSE '{}'::jsonb
            END ||
            CASE WHEN dt.physical_country_iso_2_raw IS NOT NULL AND l.resolved_physical_country_id IS NULL THEN jsonb_build_object('physical_country_iso_2_raw', dt.physical_country_iso_2_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.physical_latitude_raw IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL THEN jsonb_build_object('physical_latitude_raw', dt.physical_latitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.physical_longitude_raw IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL THEN jsonb_build_object('physical_longitude_raw', dt.physical_longitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.physical_altitude_raw IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL THEN jsonb_build_object('physical_altitude_raw', dt.physical_altitude_raw) ELSE '{}'::jsonb END
        $$, v_default_country_id);

        -- Coordinate error expressions for physical location
        v_coord_cast_error_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude_raw', l.physical_latitude_error_msg) ||
                jsonb_build_object('physical_longitude_raw', l.physical_longitude_error_msg) ||
                jsonb_build_object('physical_altitude_raw', l.physical_altitude_error_msg)
            )
        $$;
        v_coord_range_error_json_expr_sql := $jsonb_expr$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude_raw', CASE WHEN l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90) THEN format($$Value %1$s out of range. Expected -90 to 90.$$, l.resolved_typed_physical_latitude::TEXT /* %1$s */) ELSE NULL END) ||
                jsonb_build_object('physical_longitude_raw', CASE WHEN l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180) THEN format($$Value %1$s out of range. Expected -180 to 180.$$, l.resolved_typed_physical_longitude::TEXT /* %1$s */) ELSE NULL END) ||
                jsonb_build_object('physical_altitude_raw', CASE WHEN l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0 THEN format($$Value %1$s cannot be negative. Expected >= 0.$$, l.resolved_typed_physical_altitude::TEXT /* %1$s */) ELSE NULL END)
            )
        $jsonb_expr$;
        v_coord_invalid_value_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude_raw', CASE WHEN (dt.physical_latitude_raw IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90)) THEN dt.physical_latitude_raw ELSE NULL END) ||
                jsonb_build_object('physical_longitude_raw', CASE WHEN (dt.physical_longitude_raw IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180)) THEN dt.physical_longitude_raw ELSE NULL END) ||
                jsonb_build_object('physical_altitude_raw', CASE WHEN (dt.physical_altitude_raw IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0) THEN dt.physical_altitude_raw ELSE NULL END)
            )
        $$;
        v_any_coord_error_condition_sql := $$
            (l.physical_latitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90)) OR
            (l.physical_longitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180)) OR
            (l.physical_altitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0)
        $$;

    ELSIF p_step_code = 'postal_location' THEN
        v_error_keys_to_clear_arr := ARRAY[
            'postal_region_code_raw',
            'postal_country_iso_2_raw',
            'postal_latitude_raw', -- Error key for latitude issues
            'postal_longitude_raw', -- Error key for longitude issues
            'postal_altitude_raw', -- Error key for altitude issues
            'postal_location_has_coordinates_error' -- Specific error for postal having coords, keep this one
        ];
        v_warning_keys_to_clear_arr := ARRAY['postal_region_code_raw', 'postal_country_iso_2_raw', 'postal_latitude_raw', 'postal_longitude_raw', 'postal_altitude_raw'];
        v_address_present_condition_sql := $$
            (NULLIF(dt.postal_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.postal_address_part2_raw, '') IS NOT NULL OR NULLIF(dt.postal_address_part3_raw, '') IS NOT NULL OR
             NULLIF(dt.postal_postcode_raw, '') IS NOT NULL OR NULLIF(dt.postal_postplace_raw, '') IS NOT NULL OR NULLIF(dt.postal_region_code_raw, '') IS NOT NULL)
        $$;
        v_fatal_error_condition_sql := format($$
            (%s AND (NULLIF(dt.postal_country_iso_2_raw, '') IS NULL OR l.resolved_postal_country_id IS NULL))
        $$, v_address_present_condition_sql);
        v_fatal_error_json_expr_sql := $$
            jsonb_build_object('postal_country_iso_2_raw', 'Country is required and must be valid when other postal address details are provided.')
        $$;
        v_error_condition_sql := format($$
            -- Invalid region codes for any country (both domestic and foreign)
            (dt.postal_region_code_raw IS NOT NULL AND l.resolved_postal_region_id IS NULL) OR
            -- Missing region warnings only for domestic countries (whenever domestic country is present)
            (dt.postal_region_code_raw IS NULL AND l.resolved_postal_country_id IS NOT DISTINCT FROM %1$L AND l.resolved_postal_country_id IS NOT NULL) OR
            (dt.postal_country_iso_2_raw IS NOT NULL AND l.resolved_postal_country_id IS NULL AND NOT (%2$s)) OR
            (dt.postal_latitude_raw IS NOT NULL AND l.postal_latitude_error_msg IS NOT NULL) OR
            (dt.postal_longitude_raw IS NOT NULL AND l.postal_longitude_error_msg IS NOT NULL) OR
            (dt.postal_altitude_raw IS NOT NULL AND l.postal_altitude_error_msg IS NOT NULL)
        $$, v_default_country_id, v_address_present_condition_sql); -- Format with default_country_id and address_present check

        v_warnings_json_expr_sql := format($$
            CASE
                WHEN dt.postal_region_code_raw IS NOT NULL AND l.resolved_postal_region_id IS NULL THEN jsonb_build_object('postal_region_code_raw', dt.postal_region_code_raw)  -- Invalid region code
                WHEN dt.postal_region_code_raw IS NULL AND dt.postal_country_iso_2_raw IS NOT NULL AND l.resolved_postal_country_id IS NOT DISTINCT FROM %1$L AND l.resolved_postal_country_id IS NOT NULL THEN jsonb_build_object('postal_region_code_raw', NULL)  -- Missing region for domestic country (include key with NULL)
                ELSE '{}'::jsonb
            END ||
            CASE WHEN dt.postal_country_iso_2_raw IS NOT NULL AND l.resolved_postal_country_id IS NULL THEN jsonb_build_object('postal_country_iso_2_raw', dt.postal_country_iso_2_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.postal_latitude_raw IS NOT NULL AND l.postal_latitude_error_msg IS NOT NULL THEN jsonb_build_object('postal_latitude_raw', dt.postal_latitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.postal_longitude_raw IS NOT NULL AND l.postal_longitude_error_msg IS NOT NULL THEN jsonb_build_object('postal_longitude_raw', dt.postal_longitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.postal_altitude_raw IS NOT NULL AND l.postal_altitude_error_msg IS NOT NULL THEN jsonb_build_object('postal_altitude_raw', dt.postal_altitude_raw) ELSE '{}'::jsonb END
        $$, v_default_country_id);

        -- Coordinate error expressions for postal location
        v_coord_cast_error_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('postal_latitude_raw', l.postal_latitude_error_msg) ||
                jsonb_build_object('postal_longitude_raw', l.postal_longitude_error_msg) ||
                jsonb_build_object('postal_altitude_raw', l.postal_altitude_error_msg)
            )
        $$;
        -- Range errors are not applicable here as the primary error is their presence.
        v_coord_range_error_json_expr_sql := $$'{}'::jsonb$$; -- Use SQL literal for empty JSONB.
        v_postal_coord_present_error_json_expr_sql := $$
            jsonb_build_object('postal_location_has_coordinates_error', -- This is a general error, not tied to a specific input coord column.
                CASE WHEN l.resolved_typed_postal_latitude IS NOT NULL OR l.resolved_typed_postal_longitude IS NOT NULL OR l.resolved_typed_postal_altitude IS NOT NULL
                THEN 'Postal locations cannot have coordinates (latitude, longitude, altitude).'
                ELSE NULL END
            )
        $$;
        v_coord_invalid_value_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('postal_latitude_raw', CASE WHEN dt.postal_latitude_raw IS NOT NULL AND (l.postal_latitude_error_msg IS NOT NULL OR l.resolved_typed_postal_latitude IS NOT NULL) THEN dt.postal_latitude_raw ELSE NULL END) || -- Log if provided, regardless of cast success for this error type
                jsonb_build_object('postal_longitude_raw', CASE WHEN dt.postal_longitude_raw IS NOT NULL AND (l.postal_longitude_error_msg IS NOT NULL OR l.resolved_typed_postal_longitude IS NOT NULL) THEN dt.postal_longitude_raw ELSE NULL END) ||
                jsonb_build_object('postal_altitude_raw', CASE WHEN dt.postal_altitude_raw IS NOT NULL AND (l.postal_altitude_error_msg IS NOT NULL OR l.resolved_typed_postal_altitude IS NOT NULL) THEN dt.postal_altitude_raw ELSE NULL END)
            )
        $$;
        v_any_coord_error_condition_sql := $$
            (l.postal_latitude_error_msg IS NOT NULL) OR
            (l.postal_longitude_error_msg IS NOT NULL) OR
            (l.postal_altitude_error_msg IS NOT NULL) OR
            (l.resolved_typed_postal_latitude IS NOT NULL OR l.resolved_typed_postal_longitude IS NOT NULL OR l.resolved_typed_postal_altitude IS NOT NULL) -- This covers the "postal has coords" error
        $$;

    ELSE
        RAISE EXCEPTION '[Job %] analyse_location: Invalid p_step_code provided: %. Expected ''physical_location'' or ''postal_location''.', p_job_id, p_step_code;
    END IF;

    -- Step 1: Materialize the batch data into a temp table for performance.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
        SELECT
            dt.row_id,
            dt.physical_region_code_raw, dt.physical_country_iso_2_raw,
            dt.postal_region_code_raw, dt.postal_country_iso_2_raw,
            dt.physical_latitude_raw, dt.physical_longitude_raw, dt.physical_altitude_raw,
            dt.postal_latitude_raw, dt.postal_longitude_raw, dt.postal_altitude_raw
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;

    ANALYZE t_batch_data;

    -- Step 2: Resolve all distinct codes and numerics from the batch in separate temp tables.
    IF to_regclass('pg_temp.t_resolved_codes') IS NOT NULL THEN DROP TABLE t_resolved_codes; END IF;
    CREATE TEMP TABLE t_resolved_codes ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT physical_region_code_raw AS code, 'region' AS type FROM t_batch_data WHERE NULLIF(physical_region_code_raw, '') IS NOT NULL
        UNION SELECT physical_country_iso_2_raw AS code, 'country' AS type FROM t_batch_data WHERE NULLIF(physical_country_iso_2_raw, '') IS NOT NULL
        UNION SELECT postal_region_code_raw AS code, 'region' AS type FROM t_batch_data WHERE NULLIF(postal_region_code_raw, '') IS NOT NULL
        UNION SELECT postal_country_iso_2_raw AS code, 'country' AS type FROM t_batch_data WHERE NULLIF(postal_country_iso_2_raw, '') IS NOT NULL
    )
    SELECT dc.code, dc.type, COALESCE(r.id, c.id) as resolved_id
    FROM distinct_codes dc
    LEFT JOIN public.region r ON dc.type = 'region' AND dc.code = r.code
    LEFT JOIN public.country c ON dc.type = 'country' AND dc.code = c.iso_2;

    IF to_regclass('pg_temp.t_resolved_numerics') IS NOT NULL THEN DROP TABLE t_resolved_numerics; END IF;
    CREATE TEMP TABLE t_resolved_numerics ON COMMIT DROP AS
    WITH distinct_numerics AS (
        SELECT physical_latitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(physical_latitude_raw, '') IS NOT NULL
        UNION SELECT physical_longitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(physical_longitude_raw, '') IS NOT NULL
        UNION SELECT physical_altitude_raw AS num_string, 'NUMERIC(6,1)' AS num_type FROM t_batch_data WHERE NULLIF(physical_altitude_raw, '') IS NOT NULL
        UNION SELECT postal_latitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(postal_latitude_raw, '') IS NOT NULL
        UNION SELECT postal_longitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(postal_longitude_raw, '') IS NOT NULL
        UNION SELECT postal_altitude_raw AS num_string, 'NUMERIC(6,1)' AS num_type FROM t_batch_data WHERE NULLIF(postal_altitude_raw, '') IS NOT NULL
    )
    SELECT
        dn.num_string, dn.num_type,
        cast_result.p_value, cast_result.p_error_message
    FROM distinct_numerics dn
    LEFT JOIN LATERAL import.try_cast_to_numeric_specific(dn.num_string, dn.num_type) AS cast_result ON TRUE;

    ANALYZE t_resolved_codes;
    ANALYZE t_resolved_numerics;

    v_sql := format($SQL$
        WITH
        lookups AS (
            SELECT
                bd.row_id AS data_row_id,
                -- Enhanced region resolution: always look for region by code, but validate context later
                (SELECT r.id FROM public.region r WHERE r.code = bd.physical_region_code_raw AND r.version_id = (SELECT region_version_id FROM public.settings LIMIT 1)) as resolved_physical_region_id,
                phys_c.resolved_id as resolved_physical_country_id,
                -- Enhanced region resolution: always look for region by code, but validate context later
                (SELECT r.id FROM public.region r WHERE r.code = bd.postal_region_code_raw AND r.version_id = (SELECT region_version_id FROM public.settings LIMIT 1)) as resolved_postal_region_id,
                post_c.resolved_id as resolved_postal_country_id,
                phys_lat.p_value as resolved_typed_physical_latitude,
                phys_lat.p_error_message as physical_latitude_error_msg,
                phys_lon.p_value as resolved_typed_physical_longitude,
                phys_lon.p_error_message as physical_longitude_error_msg,
                phys_alt.p_value as resolved_typed_physical_altitude,
                phys_alt.p_error_message as physical_altitude_error_msg,
                post_lat.p_value as resolved_typed_postal_latitude,
                post_lat.p_error_message as postal_latitude_error_msg,
                post_lon.p_value as resolved_typed_postal_longitude,
                post_lon.p_error_message as postal_longitude_error_msg,
                post_alt.p_value as resolved_typed_postal_altitude,
                post_alt.p_error_message as postal_altitude_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes phys_c ON bd.physical_country_iso_2_raw = phys_c.code AND phys_c.type = 'country'
            LEFT JOIN t_resolved_codes post_c ON bd.postal_country_iso_2_raw = post_c.code AND post_c.type = 'country'
            LEFT JOIN t_resolved_numerics phys_lat ON bd.physical_latitude_raw = phys_lat.num_string AND phys_lat.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics phys_lon ON bd.physical_longitude_raw = phys_lon.num_string AND phys_lon.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics phys_alt ON bd.physical_altitude_raw = phys_alt.num_string AND phys_alt.num_type = 'NUMERIC(6,1)'
            LEFT JOIN t_resolved_numerics post_lat ON bd.postal_latitude_raw = post_lat.num_string AND post_lat.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics post_lon ON bd.postal_longitude_raw = post_lon.num_string AND post_lon.num_type = 'NUMERIC(6,1)'
            LEFT JOIN t_resolved_numerics post_alt ON bd.postal_altitude_raw = post_alt.num_string AND post_alt.num_type = 'NUMERIC(6,1)'
        )
        UPDATE public.%1$I dt SET
            physical_address_part1 = NULLIF(dt.physical_address_part1_raw, ''),
            physical_address_part2 = NULLIF(dt.physical_address_part2_raw, ''),
            physical_address_part3 = NULLIF(dt.physical_address_part3_raw, ''),
            physical_postcode = NULLIF(dt.physical_postcode_raw, ''),
            physical_postplace = NULLIF(dt.physical_postplace_raw, ''),
            physical_region_id = l.resolved_physical_region_id,
            physical_country_id = l.resolved_physical_country_id,
            physical_latitude = l.resolved_typed_physical_latitude,
            physical_longitude = l.resolved_typed_physical_longitude,
            physical_altitude = l.resolved_typed_physical_altitude,
            postal_address_part1 = NULLIF(dt.postal_address_part1_raw, ''),
            postal_address_part2 = NULLIF(dt.postal_address_part2_raw, ''),
            postal_address_part3 = NULLIF(dt.postal_address_part3_raw, ''),
            postal_postcode = NULLIF(dt.postal_postcode_raw, ''),
            postal_postplace = NULLIF(dt.postal_postplace_raw, ''),
            postal_region_id = l.resolved_postal_region_id,
            postal_country_id = l.resolved_postal_country_id,
            postal_latitude = l.resolved_typed_postal_latitude,
            postal_longitude = l.resolved_typed_postal_longitude,
            postal_altitude = l.resolved_typed_postal_altitude,
            action = CASE
                        WHEN (%6$s) OR (%10$s) THEN 'skip'::public.import_row_action_type -- Fatal error: set action to skip
                        ELSE dt.action -- Preserve existing action otherwise
                     END,
            state = CASE
                        WHEN (%6$s) OR (%10$s) THEN 'error'::public.import_data_state -- Fatal country error OR any coordinate error
                        ELSE 'analysing'::public.import_data_state
                    END,
            errors = jsonb_strip_nulls(
                        (dt.errors - %3$L::text[]) -- Start with existing errors, clearing old ones for this step
                        || CASE WHEN (%6$s) THEN (%7$s) ELSE '{}'::jsonb END -- Add Fatal country error message
                        || (%11$s) -- Add Coordinate cast error messages
                        || (%12$s) -- Add Coordinate range error messages
                        || (%13$s) -- Add Postal coordinate present error message
                    ),
            warnings = (
                        (dt.warnings - %8$L::text[]) -- Start with existing warnings, clearing old ones for this step
                        || CASE WHEN (%4$s) AND NOT ((%6$s) OR (%10$s)) THEN (%5$s) ELSE '{}'::jsonb END -- Add Non-fatal region/country codes (if no fatal/coord error)
                        || CASE WHEN (%10$s) THEN jsonb_strip_nulls(%14$s) ELSE '{}'::jsonb END -- Add Original invalid coordinate values (strip nulls here)
                    ),
            last_completed_priority = %9$L::INTEGER -- Always v_step.priority
        FROM lookups l
        WHERE dt.row_id = l.data_row_id;
    $SQL$,
        v_data_table_name,                          /* %1$I (target table) */
        v_default_country_id,                       /* %2$L (default country for region resolution) */
        v_error_keys_to_clear_arr,                  /* %3$L (for clearing error keys) */
        v_error_condition_sql,                      /* %4$s (non-fatal region/country error condition) */
        v_warnings_json_expr_sql,                   /* %5$s (for adding non-fatal region/country warnings) */
        v_fatal_error_condition_sql,                /* %6$s (fatal country error condition) */
        v_fatal_error_json_expr_sql,                /* %7$s (for adding fatal country error message) */
        v_warning_keys_to_clear_arr,                /* %8$L (for clearing warnings keys) */
        v_step.priority,                            /* %9$L (for last_completed_priority) */
        v_any_coord_error_condition_sql,            /* %10$s (any coordinate error condition) */
        v_coord_cast_error_json_expr_sql,           /* %11$s (coordinate cast error JSON) */
        v_coord_range_error_json_expr_sql,          /* %12$s (coordinate range error JSON) */
        v_postal_coord_present_error_json_expr_sql, /* %13$s (postal has coords error JSON) */
        v_coord_invalid_value_json_expr_sql        /* %14$s (original invalid coordinate values JSON) */
    );

    RAISE DEBUG '[Job %] analyse_location: Single-pass batch update for non-skipped rows for step %: %', p_job_id, p_step_code, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_location: Updated % non-skipped rows in single pass for step %.', p_job_id, v_update_count, p_step_code;

        -- Unconditionally advance priority for all rows in batch to ensure progress
        v_sql := format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
        RAISE DEBUG '[Job %] analyse_location: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_location: Advanced last_completed_priority for % total rows in batch for step %.', p_job_id, v_skipped_update_count, p_step_code;

        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */);
        RAISE DEBUG '[Job %] analyse_location: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_location: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION
        WHEN PROGRAM_LIMIT_EXCEEDED THEN -- e.g. statement too complex, or other similar limit errors
            error_message := SQLERRM;
            RAISE WARNING '[Job %] analyse_location: Program limit exceeded during single-pass batch update for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
            -- Fallback or simplified error marking might be needed here if the main query is too complex
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_location_error', format($$Program limit error for step %1$s: %2$s$$, p_step_code /* %1$s */, error_message /* %2$s */))::TEXT,
                state = 'failed'
            WHERE id = p_job_id;
            -- Don't re-throw - job is marked as failed
        WHEN OTHERS THEN
            error_message := SQLERRM;
            RAISE WARNING '[Job %] analyse_location: Unexpected error during single-pass batch update for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
            -- Attempt to mark individual data rows as error (best effort)
            BEGIN
                v_sql := format($$
                    UPDATE public.%1$I dt SET
                        state = %2$L,
                        errors = dt.errors || jsonb_build_object('location_batch_error', 'Unexpected error during update for step %3$s: ' || %4$L),
                        last_completed_priority = dt.last_completed_priority -- Do not advance priority on unexpected error, use existing LCP
                    WHERE dt.batch_seq = $1;
                $$, v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, p_step_code /* %3$s */, error_message /* %4$L */);
                RAISE DEBUG '[Job %] analyse_location: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
                EXECUTE v_sql USING p_batch_seq;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING '[Job %] analyse_location: Could not mark individual data rows as error after unexpected error: %', p_job_id, SQLERRM;
            END;
            -- Mark the job as failed
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_location_error', format($SQL$Unexpected error for step %1$s: %2$s$SQL$, p_step_code /* %1$s */, error_message /* %2$s */))::TEXT,
                state = 'failed'
            WHERE id = p_job_id;
            RAISE DEBUG '[Job %] analyse_location: Marked job as failed due to unexpected error for step %: %', p_job_id, p_step_code, error_message;
            -- Don't re-throw - job is marked as failed
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, p_step_code);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_location: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_location (Batch): Finished analysis for batch for step %. Errors newly marked in this step: %', p_job_id, p_step_code, v_error_count;
END;
$procedure$;

-- 4f: import.analyse_status
CREATE OR REPLACE PROCEDURE import.analyse_status(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_error_count INT := 0;
    v_default_status_id INT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['status_code_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_status (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'status';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] status step not found in snapshot', p_job_id;
    END IF;

    -- Get default status_id
    SELECT id INTO v_default_status_id FROM public.status WHERE assigned_by_default = true AND enabled = true LIMIT 1;
    RAISE DEBUG '[Job %] analyse_status: Default status_id found: %', p_job_id, v_default_status_id;

    v_sql := format($$
        WITH
        batch_data AS (
            SELECT dt.row_id, dt.status_code_raw AS status_code
            FROM public.%1$I dt
            WHERE dt.batch_seq = $1
              AND dt.action IS DISTINCT FROM 'skip'
        ),
        distinct_codes AS (
            SELECT status_code AS code
            FROM batch_data
            WHERE NULLIF(status_code, '') IS NOT NULL
            GROUP BY 1
        ),
        resolved_codes AS (
            SELECT
                dc.code,
                s.id as resolved_id
            FROM distinct_codes dc
            LEFT JOIN public.status s ON s.code = dc.code AND s.enabled = true
        ),
        status_lookup AS (
            SELECT
                bd.row_id as data_row_id,
                rc.resolved_id as resolved_status_id_by_code
            FROM batch_data bd
            LEFT JOIN resolved_codes rc ON bd.status_code = rc.code
        )
        UPDATE public.%1$I dt SET
            status_id = CASE
                            WHEN NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NOT NULL THEN sl.resolved_status_id_by_code
                            WHEN NULLIF(dt.status_code_raw, '') IS NULL THEN %2$L::INTEGER -- Use default if no code provided
                            WHEN NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL THEN %2$L::INTEGER -- Use default if code provided but not found/inactive
                            ELSE dt.status_id -- Keep existing if no condition met (should not happen if logic is complete)
                        END,
            action = CASE
                        WHEN (NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %2$L::INTEGER IS NULL) OR
                             (NULLIF(dt.status_code_raw, '') IS NULL AND %2$L::INTEGER IS NULL)
                        THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            state = CASE
                        WHEN (NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %2$L::INTEGER IS NULL) OR
                             (NULLIF(dt.status_code_raw, '') IS NULL AND %2$L::INTEGER IS NULL)
                        THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            errors = CASE
                        WHEN NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %2$L::INTEGER IS NULL THEN
                            dt.errors || jsonb_build_object('status_code_raw', 'Provided status_code ''' || dt.status_code_raw || ''' not found/active and no default available')
                        WHEN NULLIF(dt.status_code_raw, '') IS NULL AND %2$L::INTEGER IS NULL THEN
                            dt.errors || jsonb_build_object('status_code_raw', 'Status code not provided and no active default status found')
                        ELSE
                            dt.errors - %3$L::TEXT[]
                    END,
            warnings =
                CASE
                    -- Soft error: Invalid code provided, but default is available and used.
                    WHEN NULLIF(dt.status_code_raw, '') IS NOT NULL AND sl.resolved_status_id_by_code IS NULL AND %2$L::INTEGER IS NOT NULL THEN
                        dt.warnings || jsonb_build_object('status_code_raw', dt.status_code_raw)
                    -- Default case: clear 'status_code_raw' from warnings if it exists (e.g. if code is valid or hard error occurs for status_code).
                    ELSE
                        dt.warnings - 'status_code_raw'
                END,
            last_completed_priority = %4$L::INTEGER -- Always v_step.priority
        FROM status_lookup sl
        WHERE dt.row_id = sl.data_row_id;
    $$,
        v_data_table_name /* %1$I */,            -- Table used in both CTE and UPDATE
        v_default_status_id /* %2$L */,          -- Default status_id (reused in many places)
        v_error_keys_to_clear_arr /* %3$L */,    -- Keys to clear from error JSON
        v_step.priority /* %4$L */               -- last_completed_priority
    );

    RAISE DEBUG '[Job %] analyse_status: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_status: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */);
        RAISE DEBUG '[Job %] analyse_status: Counting errors in batch with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_status: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_status: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_status_batch_error', SQLERRM)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_status: Marked job as failed due to error: %', p_job_id, SQLERRM;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    RAISE DEBUG '[Job %] analyse_status: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_status: Advanced last_completed_priority for % total rows in batch.', p_job_id, v_skipped_update_count;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_status');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_status: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_status (Batch): Finished analysis for batch. Errors newly marked: %', p_job_id, v_error_count;
END;
$procedure$;

-- 4g: import.analyse_data_source
CREATE OR REPLACE PROCEDURE import.analyse_data_source(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_sql TEXT;
    v_update_count INT;
    v_skipped_update_count INT;
BEGIN
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Starting analysis for batch_seq %.', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] Step % not found in snapshot', p_job_id, p_step_code; END IF;

    v_sql := format($SQL$
        WITH
        batch_data AS (
            SELECT dt.row_id, dt.data_source_code_raw AS data_source_code
            FROM public.%1$I dt
            WHERE dt.batch_seq = $1 AND dt.action IS DISTINCT FROM 'skip'
        ),
        distinct_codes AS (
            SELECT data_source_code AS code
            FROM batch_data
            WHERE NULLIF(data_source_code, '') IS NOT NULL
            GROUP BY 1
        ),
        resolved_codes AS (
            SELECT
                dc.code,
                ds.id as resolved_id
            FROM distinct_codes dc
            LEFT JOIN public.data_source_enabled ds ON ds.code = dc.code
        ),
        lookups AS (
            SELECT
                bd.row_id,
                rc.resolved_id as resolved_data_source_id
            FROM batch_data bd
            LEFT JOIN resolved_codes rc ON bd.data_source_code = rc.code
        )
        UPDATE public.%1$I dt SET
            data_source_id = COALESCE(l.resolved_data_source_id, dt.data_source_id), -- Only update if resolved, don't nullify
            warnings = jsonb_strip_nulls(
                (COALESCE(dt.warnings, '{}'::jsonb) - 'data_source_code_raw') ||
                jsonb_build_object('data_source_code_raw',
                    CASE
                        WHEN NULLIF(dt.data_source_code_raw, '') IS NOT NULL AND l.resolved_data_source_id IS NULL THEN dt.data_source_code_raw
                        ELSE NULL
                    END
                )
            ),
            last_completed_priority = %2$L
        FROM lookups l
        WHERE dt.row_id = l.row_id;
    $SQL$, v_job.data_table_name, v_step.priority);

    RAISE DEBUG '[Job %] analyse_data_source (Batch): Updating non-skipped rows with SQL: %', p_job_id, v_sql;
    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_data_source (Batch): Updated % non-skipped rows.', p_job_id, v_update_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_data_source: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_data_source_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format('UPDATE public.%I dt SET last_completed_priority = %s WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %s', v_job.data_table_name, v_step.priority, v_step.priority);
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Advanced last_completed_priority for % total rows in batch.', p_job_id, v_skipped_update_count;
END;
$procedure$;

-- 4h: import.analyse_tags
CREATE OR REPLACE PROCEDURE import.analyse_tags(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['tag_path_raw'];
    -- v_warning_keys_to_clear_arr is removed as tag errors are now fatal
BEGIN
    RAISE DEBUG '[Job %] analyse_tags (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately

    -- Find the target details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'tags';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] tags target not found in snapshot', p_job_id;
    END IF;

    -- Single-pass batch update for casting, lookup, state, error, and priority
    v_sql := format($$
        WITH
        batch_data AS (
            SELECT dt.row_id, dt.tag_path_raw AS tag_path
            FROM public.%1$I dt
            WHERE dt.batch_seq = $1
              AND dt.tag_path_raw IS NOT NULL AND dt.action IS DISTINCT FROM 'skip'
        ),
        distinct_paths AS (
            SELECT tag_path
            FROM batch_data
            GROUP BY 1
        ),
        casted_paths AS (
            SELECT
                dp.tag_path,
                (import.safe_cast_to_ltree(dp.tag_path)).p_value AS casted_ltree_path,
                (import.safe_cast_to_ltree(dp.tag_path)).p_error_message AS ltree_error_msg
            FROM distinct_paths dp
        ),
        resolved_tags AS (
            SELECT
                cp.tag_path,
                cp.casted_ltree_path,
                cp.ltree_error_msg,
                t.id as resolved_tag_id
            FROM casted_paths cp
            LEFT JOIN public.tag t ON t.path = cp.casted_ltree_path
        ),
        lookups AS (
            SELECT
                bd.row_id,
                rt.casted_ltree_path,
                rt.ltree_error_msg,
                rt.resolved_tag_id
            FROM batch_data bd
            LEFT JOIN resolved_tags rt ON bd.tag_path = rt.tag_path
        )
        UPDATE public.%1$I dt SET
            tag_path = l.casted_ltree_path,
            tag_id = l.resolved_tag_id,
            state = CASE
                        WHEN dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NOT NULL THEN 'error'::public.import_data_state
                        WHEN dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NULL AND l.resolved_tag_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN (dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NOT NULL) OR (dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NULL AND l.resolved_tag_id IS NULL) THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                    END,
            errors = CASE
                        WHEN dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NOT NULL THEN
                            dt.errors || jsonb_build_object('tag_path_raw', l.ltree_error_msg)
                        WHEN dt.tag_path_raw IS NOT NULL AND l.ltree_error_msg IS NULL AND l.resolved_tag_id IS NULL THEN
                            dt.errors || jsonb_build_object('tag_path_raw', 'Tag not found for path: ' || dt.tag_path_raw)
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            warnings = dt.warnings,
            last_completed_priority = %3$L
        FROM lookups l
        WHERE dt.row_id = l.row_id;
    $$,
        v_data_table_name,          /* %1$I */
        v_error_keys_to_clear_arr,  /* %2$L */
        v_step.priority             /* %3$L */
    );
    RAISE DEBUG '[Job %] analyse_tags: Single-pass batch update for non-skipped rows (tag errors are fatal): %', p_job_id, v_sql;
    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_tags: Logic update affected % rows.', p_job_id, v_update_count;

        -- Estimate error count
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */);
        RAISE DEBUG '[Job %] analyse_tags: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_tags: Estimated errors in this step for batch: %', p_job_id, v_error_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_tags: Error during single-pass batch update: %', p_job_id, SQLERRM;
        -- Mark the job itself as failed
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_tags_batch_error', SQLERRM)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_tags: Marked job as failed due to error: %', p_job_id, SQLERRM;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance the priority for all rows in the batch that have not yet completed this step.
    -- This is crucial to ensure progress, as it covers rows that were skipped OR had no data for this step.
    v_sql := format($$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    RAISE DEBUG '[Job %] analyse_tags: Unconditionally advancing priority with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_tags: Advanced last_completed_priority for % total rows in batch.', p_job_id, v_skipped_update_count;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_tags');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_tags: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_tags (Batch): Finished analysis for batch.', p_job_id; -- Simplified final message
END;
$procedure$;

-- 4i: import.analyse_legal_relationship
CREATE OR REPLACE PROCEDURE import.analyse_legal_relationship(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY[
        'missing_influencing_tax_ident',
        'unknown_influencing_tax_ident',
        'missing_influenced_tax_ident',
        'unknown_influenced_tax_ident',
        'missing_rel_type_code',
        'unknown_rel_type_code',
        'invalid_percentage'
    ];
    v_warning_keys_arr TEXT[] := ARRAY['rel_type_code'];
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_relationship (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = 'legal_relationship';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] legal_relationship target step not found in snapshot', p_job_id; END IF;

    -- STEP 1: Materialize batch data into temp table
    IF to_regclass('pg_temp.t_lr_batch_data') IS NOT NULL THEN DROP TABLE t_lr_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_lr_batch_data ON COMMIT DROP AS
        SELECT dt.row_id,
               dt.influencing_tax_ident_raw,
               dt.influenced_tax_ident_raw,
               dt.rel_type_code_raw,
               dt.percentage_raw,
               dt.valid_from,
               dt.valid_until
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;
    ANALYZE t_lr_batch_data;

    -- STEP 2: Resolve distinct tax_idents to legal_unit IDs
    IF to_regclass('pg_temp.t_lr_influencing_ids') IS NOT NULL THEN DROP TABLE t_lr_influencing_ids; END IF;
    CREATE TEMP TABLE t_lr_influencing_ids ON COMMIT DROP AS
    WITH distinct_idents AS (
        SELECT DISTINCT NULLIF(TRIM(influencing_tax_ident_raw), '') AS tax_ident
        FROM t_lr_batch_data
        WHERE NULLIF(TRIM(influencing_tax_ident_raw), '') IS NOT NULL
    )
    SELECT
        di.tax_ident,
        lu.id AS legal_unit_id
    FROM distinct_idents AS di
    LEFT JOIN public.external_ident AS ei
        ON ei.ident = di.tax_ident
        AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
    LEFT JOIN public.legal_unit AS lu
        ON lu.id = ei.legal_unit_id
        AND lu.valid_range @> CURRENT_DATE;
    ANALYZE t_lr_influencing_ids;

    IF to_regclass('pg_temp.t_lr_influenced_ids') IS NOT NULL THEN DROP TABLE t_lr_influenced_ids; END IF;
    CREATE TEMP TABLE t_lr_influenced_ids ON COMMIT DROP AS
    WITH distinct_idents AS (
        SELECT DISTINCT NULLIF(TRIM(influenced_tax_ident_raw), '') AS tax_ident
        FROM t_lr_batch_data
        WHERE NULLIF(TRIM(influenced_tax_ident_raw), '') IS NOT NULL
    )
    SELECT
        di.tax_ident,
        lu.id AS legal_unit_id
    FROM distinct_idents AS di
    LEFT JOIN public.external_ident AS ei
        ON ei.ident = di.tax_ident
        AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
    LEFT JOIN public.legal_unit AS lu
        ON lu.id = ei.legal_unit_id
        AND lu.valid_range @> CURRENT_DATE;
    ANALYZE t_lr_influenced_ids;

    -- Resolve rel_type codes
    IF to_regclass('pg_temp.t_lr_type_ids') IS NOT NULL THEN DROP TABLE t_lr_type_ids; END IF;
    CREATE TEMP TABLE t_lr_type_ids ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT DISTINCT NULLIF(TRIM(rel_type_code_raw), '') AS code
        FROM t_lr_batch_data
        WHERE NULLIF(TRIM(rel_type_code_raw), '') IS NOT NULL
    )
    SELECT
        dc.code,
        lrt.id AS type_id
    FROM distinct_codes AS dc
    LEFT JOIN public.legal_rel_type AS lrt ON lrt.code = dc.code AND lrt.enabled;
    ANALYZE t_lr_type_ids;

    -- STEP 3: Main update with resolved values and existing relationship lookup
    v_sql := format($SQL$
        WITH lookups AS (
            SELECT
                bd.row_id AS data_row_id,
                infl.legal_unit_id AS influencing_id,
                infld.legal_unit_id AS influenced_id,
                tp.type_id,
                CASE
                    WHEN NULLIF(TRIM(bd.percentage_raw), '') IS NOT NULL THEN
                        CASE
                            WHEN bd.percentage_raw ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' THEN
                                TRIM(bd.percentage_raw)::numeric(5,2)
                            ELSE NULL
                        END
                    ELSE NULL
                END AS percentage,
                NULLIF(TRIM(bd.influencing_tax_ident_raw), '') IS NULL AS missing_influencing,
                NULLIF(TRIM(bd.influenced_tax_ident_raw), '') IS NULL AS missing_influenced,
                NULLIF(TRIM(bd.rel_type_code_raw), '') IS NULL AS missing_rel_type,
                NULLIF(TRIM(bd.influencing_tax_ident_raw), '') IS NOT NULL AND infl.legal_unit_id IS NULL AS unknown_influencing,
                NULLIF(TRIM(bd.influenced_tax_ident_raw), '') IS NOT NULL AND infld.legal_unit_id IS NULL AS unknown_influenced,
                NULLIF(TRIM(bd.rel_type_code_raw), '') IS NOT NULL AND tp.type_id IS NULL AS unknown_rel_type,
                NULLIF(TRIM(bd.percentage_raw), '') IS NOT NULL
                    AND NOT (bd.percentage_raw ~ '^\s*[0-9]+(\.[0-9]+)?\s*$')
                    AS invalid_percentage,
                -- Look up existing legal_relationship by natural key with overlapping time range
                lr.id AS existing_legal_relationship_id
            FROM t_lr_batch_data AS bd
            LEFT JOIN t_lr_influencing_ids AS infl ON infl.tax_ident = NULLIF(TRIM(bd.influencing_tax_ident_raw), '')
            LEFT JOIN t_lr_influenced_ids AS infld ON infld.tax_ident = NULLIF(TRIM(bd.influenced_tax_ident_raw), '')
            LEFT JOIN t_lr_type_ids AS tp ON tp.code = NULLIF(TRIM(bd.rel_type_code_raw), '')
            LEFT JOIN public.legal_relationship AS lr
                ON lr.influencing_id = infl.legal_unit_id
                AND lr.influenced_id = infld.legal_unit_id
                AND lr.type_id = tp.type_id
                AND lr.valid_range && daterange(bd.valid_from, bd.valid_until, '[)')
        ),
        -- Deduplicate: if multiple existing relationships match (e.g., split ranges),
        -- pick the one with the earliest valid_from
        deduped AS (
            SELECT DISTINCT ON (data_row_id) *
            FROM lookups
            ORDER BY data_row_id, existing_legal_relationship_id ASC NULLS LAST
        )
        UPDATE public.%1$I dt SET
            influencing_id = l.influencing_id,
            influenced_id = l.influenced_id,
            type_id = l.type_id,
            percentage = l.percentage,
            legal_relationship_id = l.existing_legal_relationship_id,
            state = CASE
                WHEN l.missing_influencing OR l.unknown_influencing
                  OR l.missing_influenced OR l.unknown_influenced
                  OR l.missing_rel_type OR l.unknown_rel_type
                  OR l.invalid_percentage
                THEN 'error'::public.import_data_state
                ELSE 'analysing'::public.import_data_state
            END,
            action = CASE
                WHEN l.missing_influencing OR l.unknown_influencing
                  OR l.missing_influenced OR l.unknown_influenced
                  OR l.missing_rel_type OR l.unknown_rel_type
                  OR l.invalid_percentage
                THEN 'skip'::public.import_row_action_type
                ELSE 'use'::public.import_row_action_type
            END,
            operation = CASE
                WHEN l.missing_influencing OR l.unknown_influencing
                  OR l.missing_influenced OR l.unknown_influenced
                  OR l.missing_rel_type OR l.unknown_rel_type
                  OR l.invalid_percentage
                THEN NULL
                WHEN l.existing_legal_relationship_id IS NOT NULL
                THEN CASE %4$L::public.import_strategy
                    WHEN 'insert_or_update' THEN 'update'::public.import_row_operation_type
                    WHEN 'update_only' THEN 'update'::public.import_row_operation_type
                    ELSE 'replace'::public.import_row_operation_type
                END
                ELSE 'insert'::public.import_row_operation_type
            END,
            errors = (dt.errors - %2$L::TEXT[])
                || CASE WHEN l.missing_influencing THEN jsonb_build_object('missing_influencing_tax_ident', 'influencing_tax_ident is required') ELSE '{}'::jsonb END
                || CASE WHEN l.unknown_influencing THEN jsonb_build_object('unknown_influencing_tax_ident', 'No legal unit found for influencing_tax_ident') ELSE '{}'::jsonb END
                || CASE WHEN l.missing_influenced THEN jsonb_build_object('missing_influenced_tax_ident', 'influenced_tax_ident is required') ELSE '{}'::jsonb END
                || CASE WHEN l.unknown_influenced THEN jsonb_build_object('unknown_influenced_tax_ident', 'No legal unit found for influenced_tax_ident') ELSE '{}'::jsonb END
                || CASE WHEN l.missing_rel_type THEN jsonb_build_object('missing_rel_type_code', 'rel_type_code is required') ELSE '{}'::jsonb END
                || CASE WHEN l.unknown_rel_type THEN jsonb_build_object('unknown_rel_type_code', 'Unknown rel_type_code') ELSE '{}'::jsonb END
                || CASE WHEN l.invalid_percentage THEN jsonb_build_object('invalid_percentage', 'percentage must be a number 0-100') ELSE '{}'::jsonb END,
            warnings = CASE
                WHEN l.unknown_rel_type THEN jsonb_strip_nulls((dt.warnings - %3$L::TEXT[]) || jsonb_build_object('rel_type_code', dt.rel_type_code_raw))
                ELSE dt.warnings - %3$L::TEXT[]
            END
        FROM deduped AS l
        WHERE dt.row_id = l.data_row_id;
    $SQL$, v_data_table_name, v_error_keys_to_clear_arr, v_warning_keys_arr, v_definition.strategy);

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_relationship: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_relationship: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_legal_relationship_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
    END;

    -- STEP 4: Compute founding_row_id for rows with same natural key in the batch.
    -- When multiple rows share (influencing_id, influenced_id, type_id) -- e.g., different
    -- temporal periods for the same relationship -- they must be linked via founding_row_id
    -- so temporal_merge knows they belong to the same entity.
    -- Offset of 1000000000 avoids collision between legal_relationship IDs and row_ids,
    -- matching the pattern used in analyse_external_idents.
    v_sql := format($SQL$
        WITH entity_groups AS (
            SELECT
                dt.row_id,
                dt.influencing_id,
                dt.influenced_id,
                dt.type_id,
                COALESCE(
                    dt.legal_relationship_id + 1000000000,
                    MIN(dt.row_id) OVER (
                        PARTITION BY dt.influencing_id, dt.influenced_id, dt.type_id
                    )
                ) AS computed_founding_id
            FROM public.%1$I AS dt
            WHERE dt.batch_seq = $1
              AND dt.action = 'use'
              AND dt.influencing_id IS NOT NULL
              AND dt.influenced_id IS NOT NULL
              AND dt.type_id IS NOT NULL
        )
        UPDATE public.%1$I dt SET
            founding_row_id = eg.computed_founding_id
        FROM entity_groups AS eg
        WHERE dt.row_id = eg.row_id
          AND dt.founding_row_id IS DISTINCT FROM eg.computed_founding_id;
    $SQL$, v_data_table_name);
    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_legal_relationship: Set founding_row_id for batch rows.', p_job_id;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_relationship: Error during founding_row_id computation: %', p_job_id, SQLERRM;
    END;

    -- Advance priority for all batch rows
    v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L',
                    v_data_table_name, v_step.priority);
    EXECUTE v_sql USING p_batch_seq;

    -- Count errors
    BEGIN
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_relationship: Error during error count: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_legal_relationship (Batch): Finished analysis for batch. Total errors: %', p_job_id, v_error_count;
END;
$procedure$;

-- 4j: import.process_legal_relationship
CREATE OR REPLACE PROCEDURE import.process_legal_relationship(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_legal_relationship (Batch): Starting operation for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = 'legal_relationship';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] legal_relationship target step not found in snapshot', p_job_id; END IF;

    -- Create updatable view over batch data mapping to legal_relationship columns
    v_sql := format($$
        CREATE OR REPLACE TEMP VIEW temp_legal_relationship_source_view AS
        SELECT
            row_id AS data_row_id,
            founding_row_id,
            legal_relationship_id AS id,
            influencing_id,
            influenced_id,
            type_id,
            percentage,
            valid_from,
            valid_until,
            edit_by_user_id,
            edit_at,
            edit_comment,
            NULLIF(warnings,'{}'::JSONB) AS warnings,
            errors,
            merge_status
        FROM public.%1$I
        WHERE batch_seq = %2$L AND action = 'use';
    $$, v_data_table_name, p_batch_seq);
    EXECUTE v_sql;

    BEGIN
        v_merge_mode := CASE v_definition.strategy
            WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'replace_only' THEN 'REPLACE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            WHEN 'update_only' THEN 'UPDATE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
        END;
        RAISE DEBUG '[Job %] process_legal_relationship: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        CALL sql_saga.temporal_merge(
            target_table => 'public.legal_relationship'::regclass,
            source_table => 'temp_legal_relationship_source_view'::regclass,
            primary_identity_columns => ARRAY['id'],
            mode => v_merge_mode,
            row_id_column => 'data_row_id',
            founding_id_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => 'legal_relationship',
            feedback_error_column => 'errors',
            feedback_error_key => 'legal_relationship'
        );

        v_sql := format($$ SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.errors->'legal_relationship' IS NOT NULL $$, v_data_table_name);
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors ? 'legal_relationship' THEN 'error'::public.import_data_state ELSE 'processing'::public.import_data_state END
            WHERE dt.batch_seq = $1 AND dt.action = 'use';
        $$, v_data_table_name);
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_legal_relationship: temporal_merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

        -- Propagate newly assigned legal_relationship_id within batch
        v_sql := format($$
            WITH id_source AS (
                SELECT DISTINCT src.founding_row_id, src.legal_relationship_id
                FROM public.%1$I src
                WHERE src.batch_seq = $1
                  AND src.legal_relationship_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET legal_relationship_id = id_source.legal_relationship_id
            FROM id_source
            WHERE dt.batch_seq = $1
              AND dt.founding_row_id = id_source.founding_row_id
              AND dt.legal_relationship_id IS NULL;
        $$, v_data_table_name);
        EXECUTE v_sql USING p_batch_seq;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_relationship: Unhandled error: %', p_job_id, replace(error_message, '%', '%%');
        BEGIN
            v_sql := format($$UPDATE public.%1$I dt SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('unhandled_error_process_legal_relationship', %2$L) WHERE dt.batch_seq = $1 AND dt.state != 'error'::public.import_data_state$$,
                           v_data_table_name, error_message);
            EXECUTE v_sql USING p_batch_seq;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] process_legal_relationship: Failed to mark rows as error: %', p_job_id, SQLERRM;
        END;
        UPDATE public.import_job SET error = jsonb_build_object('process_legal_relationship_unhandled_error', error_message)::TEXT, state = 'failed' WHERE id = p_job_id;
    END;

    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_legal_relationship (Batch): Finished in % ms. Success: %, Errors: %', p_job_id, round(v_duration_ms, 2), v_update_count, v_error_count;
END;
$procedure$;

-- 4k: public.statistical_history_highcharts
-- NOTE: This function's v_invalid_codes local variable is for validating user-supplied
-- series codes, NOT related to the import column rename. Left unchanged intentionally.
CREATE OR REPLACE FUNCTION public.statistical_history_highcharts(p_resolution history_resolution, p_unit_type statistical_unit_type, p_year integer DEFAULT NULL::integer, p_series_codes text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    result jsonb;
    v_filtered_codes text[];
    v_invalid_codes text[];
BEGIN
    -- Use a temporary table for series definitions to avoid code duplication.
    IF to_regclass('pg_temp.series_definition') IS NOT NULL THEN DROP TABLE series_definition; END IF;
    CREATE TEMP TABLE series_definition(priority int, is_default boolean, code text, name text) ON COMMIT DROP;
    INSERT INTO series_definition(priority, is_default, code, name)
    VALUES
        (10,  true,  'countable_count',                          'Unit Count'),
        (11,  false, 'countable_change',                         'Unit Count Change'),
        (12,  false, 'countable_added_count',                    'Units Added (Countable)'),
        (13,  false, 'countable_removed_count',                  'Units Removed (Countable)'),
        (14,  false, 'exists_count',                             'Existing Units'),
        (15,  false, 'exists_change',                            'Existing Units Change'),
        (16,  false, 'exists_added_count',                       'Units Added (Existence)'),
        (17,  false, 'exists_removed_count',                     'Units Removed (Existence)'),
        (20,  true , 'births',                                   'Births'),
        (30,  true , 'deaths',                                   'Deaths'),
        (40,  false, 'name_change_count',                        'Name Changes'),
        (50,  true , 'primary_activity_category_change_count',   'Primary Activity Changes'),
        (60,  false, 'secondary_activity_category_change_count', 'Secondary Activity Changes'),
        (70,  false, 'sector_change_count',                      'Sector Changes'),
        (80,  false, 'legal_form_change_count',                  'Legal Form Changes'),
        (90,  true , 'physical_region_change_count',             'Region Changes'),
        (100, false, 'physical_country_change_count',            'Country Changes'),
        (110, false, 'physical_address_change_count',            'Physical Address Changes');

    -- Fail fast if any requested series codes are invalid.
    IF p_series_codes IS NOT NULL AND cardinality(p_series_codes) > 0 THEN
        SELECT array_agg(req_code)
        INTO v_invalid_codes
        FROM unnest(p_series_codes) AS t(req_code)
        WHERE NOT EXISTS (SELECT 1 FROM series_definition sd WHERE sd.code = t.req_code);

        IF v_invalid_codes IS NOT NULL AND cardinality(v_invalid_codes) > 0 THEN
            RAISE EXCEPTION 'Invalid series code(s) provided: %', array_to_string(v_invalid_codes, ', ');
        END IF;
    END IF;

    v_filtered_codes := CASE
        WHEN p_series_codes IS NULL OR cardinality(p_series_codes) = 0 THEN
            (SELECT array_agg(code) FROM series_definition WHERE is_default)
        ELSE
            p_series_codes
    END;

    WITH
    base AS (
        -- Prepare base data, calculating the Javascript-compatible millisecond timestamp once.
        SELECT
            -- Highcharts expects UTC milliseconds since epoch.
            extract(epoch FROM
                CASE p_resolution
                    WHEN 'year' THEN make_timestamp(year, 1, 1, 0, 0, 0)
                    WHEN 'year-month' THEN make_timestamp(year, month, 1, 0, 0, 0)
                END
            )::bigint * 1000 AS ts_epoch_ms,
            exists_count, exists_change, exists_added_count, exists_removed_count,
            countable_count, countable_change, countable_added_count, countable_removed_count,
            births, deaths, name_change_count,
            primary_activity_category_change_count, secondary_activity_category_change_count,
            sector_change_count, legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count
        FROM public.statistical_history
        WHERE resolution = p_resolution
          AND unit_type = p_unit_type
          AND (p_year IS NULL OR year = p_year)
    ),
    aggregated_data AS (
        -- Aggregate each metric into a JSONB array of [timestamp, value] pairs.
        SELECT
            jsonb_build_object(
                'exists_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, exists_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'exists_change', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, exists_change) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'exists_added_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, exists_added_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'exists_removed_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, exists_removed_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'countable_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, countable_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'countable_change', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, countable_change) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'countable_added_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, countable_added_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'countable_removed_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, countable_removed_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'births', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, births) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'deaths', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, deaths) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'name_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, name_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'primary_activity_category_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, primary_activity_category_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'secondary_activity_category_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, secondary_activity_category_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'sector_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, sector_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'legal_form_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, legal_form_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'physical_region_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, physical_region_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'physical_country_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, physical_country_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'physical_address_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, physical_address_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb)
            ) as series_data_map
        FROM base
    )
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'resolution', p_resolution,
        'unit_type', p_unit_type,
        'year', p_year,
        'available_series', (
            SELECT jsonb_agg(jsonb_build_object('code', code, 'name', name, 'priority', priority) ORDER BY priority)
            FROM series_definition
            WHERE code <> ALL(v_filtered_codes)
        ),
        'filtered_series', to_jsonb(v_filtered_codes),
        'series', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'code', sd.code,
                    'name', sd.name,
                    'data', COALESCE(ad.series_data_map -> sd.code, '[]'::jsonb)
                ) ORDER BY sd.priority
            )
            FROM series_definition sd, aggregated_data ad
            WHERE sd.code = ANY(v_filtered_codes)
        )
    ))
    INTO result
    FROM aggregated_data;

    RETURN result;
END;
$function$;

END;

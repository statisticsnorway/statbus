```sql
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
$procedure$
```

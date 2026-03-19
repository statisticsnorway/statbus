-- Migration 20260319170725: worker_info_own_contribution_principle
--
-- Apply the "Info Principle": each task reports in info only what IT contributed.
-- - Rename derive_statistical_unit keys: affected_* → effective_*
-- - Change import_job_process from cumulative snapshot to delta reporting
-- - Add p_info to 9 analytics handlers (3 spawners, 3 leaves, 3 reducers)
BEGIN;

-- 1. Rename affected_* → effective_* in derive_statistical_unit function
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_power_group_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
    v_orphan_power_group_ids INT[];
    v_enterprise_count INT := 0;
    v_legal_unit_count INT := 0;
    v_establishment_count INT := 0;
    v_power_group_count INT := 0;
    v_partition_count INT;
    v_pg_batch_size INT;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    IF v_is_full_refresh THEN
        FOR v_batch IN SELECT * FROM public.get_closed_group_batches(p_target_batch_size => 1000)
        LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command => 'statistical_unit_refresh_batch',
                p_payload => jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id => p_task_id
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;

        v_power_group_ids := ARRAY(SELECT id FROM public.power_group ORDER BY id);
        v_power_group_count := COALESCE(array_length(v_power_group_ids, 1), 0);
        IF v_power_group_count > 0 THEN
            SELECT analytics_partition_count INTO v_partition_count FROM public.settings;
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / v_partition_count));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    ELSE
        v_establishment_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
        v_legal_unit_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r));
        v_enterprise_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r));
        v_power_group_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_power_group_id_ranges, '{}'::int4multirange)) AS t(r));

        -- ORPHAN CLEANUP
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(SELECT id FROM unnest(v_enterprise_ids) AS id EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids));
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_orphan_power_group_ids := ARRAY(SELECT id FROM unnest(v_power_group_ids) AS id EXCEPT SELECT pg.id FROM public.power_group AS pg WHERE pg.id = ANY(v_power_group_ids));
            IF COALESCE(array_length(v_orphan_power_group_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timeline_power_group WHERE power_group_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
            END IF;
        END IF;

        IF p_establishment_id_ranges IS NOT NULL
           OR p_legal_unit_id_ranges IS NOT NULL
           OR p_enterprise_id_ranges IS NOT NULL THEN
            IF to_regclass('pg_temp._batches') IS NOT NULL THEN DROP TABLE _batches; END IF;
            CREATE TEMP TABLE _batches ON COMMIT DROP AS
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size => 1000,
                p_establishment_id_ranges => NULLIF(p_establishment_id_ranges, '{}'::int4multirange),
                p_legal_unit_id_ranges => NULLIF(p_legal_unit_id_ranges, '{}'::int4multirange),
                p_enterprise_id_ranges => NULLIF(p_enterprise_id_ranges, '{}'::int4multirange)
            );
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings))
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _batches AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _batches AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _batches AS b
            ) AS t WHERE t.unit_id IS NOT NULL
            ON CONFLICT DO NOTHING;

            <<effective_counts>>
            DECLARE
                v_all_batch_est_ranges int4multirange;
                v_all_batch_lu_ranges int4multirange;
                v_all_batch_en_ranges int4multirange;
                v_propagated_lu int4multirange;
                v_propagated_en int4multirange;
                v_eff_est int4multirange;
                v_eff_lu int4multirange;
                v_eff_en int4multirange;
            BEGIN
                v_all_batch_est_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(establishment_ids) AS id FROM _batches) AS t);
                v_all_batch_lu_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(legal_unit_ids) AS id FROM _batches) AS t);
                v_all_batch_en_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(enterprise_ids) AS id FROM _batches) AS t);

                v_eff_est := NULLIF(
                    COALESCE(v_all_batch_est_ranges, '{}'::int4multirange)
                    * COALESCE(p_establishment_id_ranges, '{}'::int4multirange),
                    '{}'::int4multirange);

                SELECT range_agg(int4range(es.legal_unit_id, es.legal_unit_id, '[]'))
                  INTO v_propagated_lu
                  FROM public.establishment AS es
                 WHERE es.id <@ COALESCE(p_establishment_id_ranges, '{}'::int4multirange)
                   AND es.legal_unit_id IS NOT NULL;
                v_eff_lu := NULLIF(
                    COALESCE(v_all_batch_lu_ranges, '{}'::int4multirange)
                    * (COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_lu, '{}'::int4multirange)),
                    '{}'::int4multirange);

                SELECT range_agg(int4range(lu.enterprise_id, lu.enterprise_id, '[]'))
                  INTO v_propagated_en
                  FROM public.legal_unit AS lu
                 WHERE lu.id <@ COALESCE(v_eff_lu, '{}'::int4multirange)
                   AND lu.enterprise_id IS NOT NULL;
                v_eff_en := NULLIF(
                    COALESCE(v_all_batch_en_ranges, '{}'::int4multirange)
                    * (COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_en, '{}'::int4multirange)),
                    '{}'::int4multirange);

                v_establishment_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_est, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_legal_unit_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_lu, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_enterprise_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_en, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
            END effective_counts;

            FOR v_batch IN SELECT * FROM _batches LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch.batch_seq,
                        'enterprise_ids', v_batch.enterprise_ids,
                        'legal_unit_ids', v_batch.legal_unit_ids,
                        'establishment_ids', v_batch.establishment_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until,
                        'changed_establishment_id_ranges', p_establishment_id_ranges::text,
                        'changed_legal_unit_id_ranges', p_legal_unit_id_ranges::text,
                        'changed_enterprise_id_ranges', p_enterprise_id_ranges::text
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;

        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_power_group_count := array_length(v_power_group_ids, 1);
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq('power_group', pg_id, (SELECT analytics_partition_count FROM public.settings))
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

            SELECT analytics_partition_count INTO v_partition_count FROM public.settings;
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / v_partition_count));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id => p_task_id
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%, pg=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count, v_power_group_count;

    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- Info Principle: report effective counts (post-propagation), not affected counts (raw change-log)
    RETURN jsonb_build_object(
        'effective_establishment_count', v_establishment_count,
        'effective_legal_unit_count', v_legal_unit_count,
        'effective_enterprise_count', v_enterprise_count,
        'effective_power_group_count', v_power_group_count,
        'batch_count', v_batch_count
    );
END;
$derive_statistical_unit$;

-- 2. Fix import_job_process: delta reporting instead of cumulative snapshot
CREATE OR REPLACE PROCEDURE admin.import_job_process(IN job_id integer, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
AS $import_job_process$
DECLARE
    job public.import_job;
    next_state public.import_job_state;
    should_reschedule BOOLEAN := FALSE;
    -- Baseline captures for delta reporting
    v_imported_rows_before bigint;
    v_error_count_before integer;
    v_warning_count_before integer;
BEGIN
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', job_id;
    END IF;

    -- Capture baseline for delta calculation
    v_imported_rows_before := COALESCE(job.imported_rows, 0);
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
                        COUNT(*) FILTER (WHERE action = 'use' AND invalid_codes IS NOT NULL AND invalid_codes <> '{}'::jsonb)
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

    -- Report total_rows only when this invocation discovered it (preparing_data→analysing_data)
    IF job.state = 'analysing_data' AND v_imported_rows_before = 0
       AND v_error_count_before = 0 AND job.total_rows IS NOT NULL THEN
        p_info := p_info || jsonb_build_object('total_rows', job.total_rows);
    END IF;

    -- Report rows_processed delta (processing_data batches)
    IF COALESCE(job.imported_rows, 0) > v_imported_rows_before THEN
        p_info := p_info || jsonb_build_object(
            'rows_processed', job.imported_rows - v_imported_rows_before
        );
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
$import_job_process$;

-- 3. Spawners: add p_info with child_count

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_partition INT;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE partition_seq IS NOT NULL LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_history: No partition entries exist, forcing full refresh';
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NULL THEN
            FOR v_partition IN
                SELECT DISTINCT report_partition_seq
                FROM public.statistical_unit
                ORDER BY report_partition_seq
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            FOREACH v_partition IN ARRAY v_dirty_partitions LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history: spawned % period x partition children (dirty_partitions=%)',
        v_child_count, v_dirty_partitions;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_history$;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_partitions INT[];
    v_populated_partitions INT;
    v_expected_partitions INT;
    v_child_count INT := 0;
    v_i INT;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_unit_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    SELECT COUNT(DISTINCT partition_seq) INTO v_populated_partitions
    FROM public.statistical_unit_facet_staging;

    SELECT COUNT(DISTINCT report_partition_seq) INTO v_expected_partitions
    FROM public.statistical_unit
    WHERE used_for_counting;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF v_populated_partitions < v_expected_partitions THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_unit_facet: Staging has %/% expected partitions populated, forcing full refresh',
            v_populated_partitions, v_expected_partitions;
    END IF;

    IF v_dirty_partitions IS NULL THEN
        RAISE DEBUG 'derive_statistical_unit_facet: Full refresh -- spawning % partition children (populated)',
            v_expected_partitions;
        FOR v_i IN
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            WHERE used_for_counting
            ORDER BY report_partition_seq
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq', v_i
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        RAISE DEBUG 'derive_statistical_unit_facet: Partial refresh -- spawning % dirty partition children',
            array_length(v_dirty_partitions, 1);
        FOREACH v_i IN ARRAY v_dirty_partitions LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq', v_i
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    RAISE DEBUG 'derive_statistical_unit_facet: Spawned % partition children', v_child_count;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_unit_facet$;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_partition INT;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_history_facet: No partition entries exist, forcing full refresh';
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NULL THEN
            FOR v_partition IN
                SELECT DISTINCT report_partition_seq
                FROM public.statistical_unit
                ORDER BY report_partition_seq
            LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            FOREACH v_partition IN ARRAY v_dirty_partitions LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history_facet: spawned % period x partition children', v_child_count;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_history_facet$;

-- 4. Leaves: add p_info with rows_inserted

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_partition_seq integer := (payload->>'partition_seq')::integer;
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;

    IF v_partition_seq IS NOT NULL THEN
        DELETE FROM public.statistical_history
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq = v_partition_seq;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month, v_partition_seq) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    ELSE
        DELETE FROM public.statistical_history
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq IS NULL;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_history_period$;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_unit_facet_partition$
DECLARE
    v_partition_seq INT := (payload->>'partition_seq')::int;
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq=%', v_partition_seq;

    DELETE FROM public.statistical_unit_facet_staging
    WHERE partition_seq = v_partition_seq;

    INSERT INTO public.statistical_unit_facet_staging
    SELECT v_partition_seq,
           su.valid_from, su.valid_to, su.valid_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::INT,
           jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    WHERE su.used_for_counting
      AND su.report_partition_seq = v_partition_seq
    GROUP BY su.valid_from, su.valid_to, su.valid_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    RAISE DEBUG 'derive_statistical_unit_facet_partition: partition_seq=% done', v_partition_seq;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_unit_facet_partition$;

CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_partition_seq integer := (payload->>'partition_seq')::integer;
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'Processing statistical_history_facet for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;

    IF v_partition_seq IS NOT NULL THEN
        DELETE FROM public.statistical_history_facet_partitions
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq = v_partition_seq;

        INSERT INTO public.statistical_history_facet_partitions (
            partition_seq,
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            exists_count, exists_change, exists_added_count, exists_removed_count,
            countable_count, countable_change, countable_added_count, countable_removed_count,
            births, deaths,
            name_change_count, primary_activity_category_change_count,
            secondary_activity_category_change_count, sector_change_count,
            legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count,
            unit_size_change_count, status_change_count,
            stats_summary
        )
        SELECT v_partition_seq, h.*
        FROM public.statistical_history_facet_def(v_resolution, v_year, v_month, v_partition_seq) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    ELSE
        DELETE FROM public.statistical_history_facet
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month;

        INSERT INTO public.statistical_history_facet
        SELECT h.*
        FROM public.statistical_history_facet_def(v_resolution, v_year, v_month) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    END IF;

    RAISE DEBUG 'Completed statistical_history_facet for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$derive_statistical_history_facet_period$;

-- 5. Reducers: add p_info with rows_reduced

CREATE OR REPLACE PROCEDURE worker.statistical_history_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_history_reduce$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_history WHERE partition_seq IS NULL;

    INSERT INTO public.statistical_history (
        resolution, year, month, unit_type,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        stats_summary,
        partition_seq
    )
    SELECT
        resolution, year, month, unit_type,
        SUM(exists_count)::integer, SUM(exists_change)::integer,
        SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer, SUM(countable_change)::integer,
        SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
        SUM(births)::integer, SUM(deaths)::integer,
        SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
        jsonb_stats_merge_agg(stats_summary),
        NULL
    FROM public.statistical_history
    WHERE partition_seq IS NOT NULL
    GROUP BY resolution, year, month, unit_type;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    p_info := jsonb_build_object('rows_reduced', v_row_count);
END;
$statistical_history_reduce$;

CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_unit_facet_reduce$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_row_count bigint;
BEGIN
    TRUNCATE public.statistical_unit_facet;

    INSERT INTO public.statistical_unit_facet
    SELECT sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
           sufp.physical_region_path, sufp.primary_activity_category_path,
           sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id,
           SUM(sufp.count)::BIGINT,
           jsonb_stats_merge_agg(sufp.stats_summary)
    FROM public.statistical_unit_facet_staging AS sufp
    GROUP BY sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
             sufp.physical_region_path, sufp.primary_activity_category_path,
             sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    TRUNCATE public.statistical_unit_facet_dirty_partitions;

    p_info := jsonb_build_object('rows_reduced', v_row_count);
END;
$statistical_unit_facet_reduce$;

CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_history_facet_reduce$
DECLARE
    v_row_count bigint;
BEGIN
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_year;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_month;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_unit_type;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_primary_activity_category_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_primary_activity_category_pa;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_secondary_activity_category_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_secondary_activity_category_;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_sector_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_sector_path;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_legal_form_id;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_region_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_physical_region_path;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_country_id;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_stats_summary;
    DROP INDEX IF EXISTS public.statistical_history_facet_month_key;
    DROP INDEX IF EXISTS public.statistical_history_facet_year_key;

    TRUNCATE public.statistical_history_facet;

    INSERT INTO public.statistical_history_facet (
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        unit_size_change_count, status_change_count,
        stats_summary
    )
    SELECT
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        SUM(exists_count)::integer, SUM(exists_change)::integer,
        SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer, SUM(countable_change)::integer,
        SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
        SUM(births)::integer, SUM(deaths)::integer,
        SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
        SUM(unit_size_change_count)::integer, SUM(status_change_count)::integer,
        jsonb_stats_merge_agg(stats_summary)
    FROM public.statistical_history_facet_partitions
    GROUP BY resolution, year, month, unit_type,
             primary_activity_category_path, secondary_activity_category_path,
             sector_path, legal_form_id, physical_region_path,
             physical_country_id, unit_size_id, status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    CREATE UNIQUE INDEX statistical_history_facet_month_key
        ON public.statistical_history_facet (resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path, physical_country_id)
        WHERE resolution = 'year-month'::public.history_resolution;
    CREATE UNIQUE INDEX statistical_history_facet_year_key
        ON public.statistical_history_facet (year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path, physical_country_id)
        WHERE resolution = 'year'::public.history_resolution;
    CREATE INDEX idx_statistical_history_facet_year ON public.statistical_history_facet (year);
    CREATE INDEX idx_statistical_history_facet_month ON public.statistical_history_facet (month);
    CREATE INDEX idx_statistical_history_facet_unit_type ON public.statistical_history_facet (unit_type);
    CREATE INDEX idx_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet (primary_activity_category_path);
    CREATE INDEX idx_gist_statistical_history_facet_primary_activity_category_pa ON public.statistical_history_facet USING GIST (primary_activity_category_path);
    CREATE INDEX idx_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet (secondary_activity_category_path);
    CREATE INDEX idx_gist_statistical_history_facet_secondary_activity_category_ ON public.statistical_history_facet USING GIST (secondary_activity_category_path);
    CREATE INDEX idx_statistical_history_facet_sector_path ON public.statistical_history_facet (sector_path);
    CREATE INDEX idx_gist_statistical_history_facet_sector_path ON public.statistical_history_facet USING GIST (sector_path);
    CREATE INDEX idx_statistical_history_facet_legal_form_id ON public.statistical_history_facet (legal_form_id);
    CREATE INDEX idx_statistical_history_facet_physical_region_path ON public.statistical_history_facet (physical_region_path);
    CREATE INDEX idx_gist_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING GIST (physical_region_path);
    CREATE INDEX idx_statistical_history_facet_physical_country_id ON public.statistical_history_facet (physical_country_id);
    CREATE INDEX idx_statistical_history_facet_stats_summary ON public.statistical_history_facet USING GIN (stats_summary jsonb_path_ops);

    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', false)::text);

    p_info := jsonb_build_object('rows_reduced', v_row_count);
END;
$statistical_history_facet_reduce$;

END;

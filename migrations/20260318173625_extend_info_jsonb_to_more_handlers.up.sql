BEGIN;

-- 1. derive_statistical_unit: move counts from payload to info
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS void
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
    v_child_priority BIGINT;
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

    v_child_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

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
                p_parent_id => p_task_id,
                p_priority => v_child_priority
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
                    p_parent_id => p_task_id,
                    p_priority => v_child_priority
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
                    p_parent_id => p_task_id,
                    p_priority => v_child_priority
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
                    p_parent_id => p_task_id,
                    p_priority => v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%, pg=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count, v_power_group_count;

    -- Store affected counts in info (handler output, separate from payload input)
    IF p_task_id IS NOT NULL THEN
        UPDATE worker.tasks
        SET info = jsonb_build_object(
            'affected_establishment_count', v_establishment_count,
            'affected_legal_unit_count', v_legal_unit_count,
            'affected_enterprise_count', v_enterprise_count,
            'affected_power_group_count', v_power_group_count,
            'batch_count', v_batch_count
        )
        WHERE id = p_task_id;
    END IF;

    -- REMOVED: is_deriving_statistical_units notification (now in derive_units_phase)

    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- REMOVED: enqueue_statistical_unit_flush_staging (now pre-spawned sibling)
    -- REMOVED: enqueue_derive_reports (now pre-spawned sibling phase)
END;
$derive_statistical_unit$;

-- 2. notify_task_progress: read counts from info instead of payload
CREATE OR REPLACE FUNCTION worker.notify_task_progress()
 RETURNS void
 LANGUAGE plpgsql
AS $notify_task_progress$
DECLARE
    v_payload JSONB;
    v_phases JSONB := '[]'::jsonb;
    v_units_phase JSONB;
    v_reports_phase JSONB;
    -- Phase 1 variables (is_deriving_statistical_units)
    v_units_active BOOLEAN;
    v_units_step TEXT;
    v_units_total BIGINT;
    v_units_completed BIGINT;
    v_affected_est INT;
    v_affected_lu INT;
    v_affected_en INT;
    v_affected_pg INT;
    -- Phase 2 variables (is_deriving_reports)
    v_reports_active BOOLEAN;
    v_reports_step TEXT;
    v_reports_total BIGINT;
    v_reports_completed BIGINT;
BEGIN
    -- Phase 1: is_deriving_statistical_units
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE command IN ('collect_changes', 'derive_units_phase', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
          AND state IN ('pending', 'processing', 'waiting')
    ) INTO v_units_active;

    IF v_units_active THEN
        SELECT t.command INTO v_units_step
        FROM worker.tasks AS t
        WHERE t.command IN ('collect_changes', 'derive_units_phase', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
          AND (t.state IN ('processing', 'waiting') OR (t.command = 'collect_changes' AND t.state = 'pending'))
        ORDER BY t.id DESC LIMIT 1;

        SELECT count(*) INTO v_units_total
        FROM worker.tasks AS t
        WHERE t.command = 'statistical_unit_refresh_batch'
          AND EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.command = 'derive_statistical_unit'
                AND p.state IN ('processing', 'waiting')
          );

        SELECT count(*) INTO v_units_completed
        FROM worker.tasks AS t
        WHERE t.state IN ('completed', 'failed')
          AND t.command = 'statistical_unit_refresh_batch'
          AND EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.command = 'derive_statistical_unit'
                AND p.state IN ('processing', 'waiting')
          );

        -- Read effective counts from info (handler output)
        SELECT (t.info->>'effective_establishment_count')::int,
               (t.info->>'effective_legal_unit_count')::int,
               (t.info->>'effective_enterprise_count')::int,
               (t.info->>'effective_power_group_count')::int
        INTO v_affected_est, v_affected_lu, v_affected_en, v_affected_pg
        FROM worker.tasks AS t
        WHERE t.command = 'derive_statistical_unit'
          AND t.state IN ('processing', 'waiting')
        ORDER BY t.id DESC LIMIT 1;

        v_units_phase := jsonb_build_object(
            'phase', 'is_deriving_statistical_units',
            'step', v_units_step,
            'total', COALESCE(v_units_total, 0),
            'completed', COALESCE(v_units_completed, 0),
            'effective_establishment_count', v_affected_est,
            'effective_legal_unit_count', v_affected_lu,
            'effective_enterprise_count', v_affected_en,
            'effective_power_group_count', v_affected_pg
        );
        v_phases := v_phases || jsonb_build_array(v_units_phase);
    END IF;

    -- Phase 2: is_deriving_reports
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE command IN ('derive_reports_phase', 'derive_reports', 'derive_statistical_history', 'derive_statistical_history_period',
                         'statistical_history_reduce', 'derive_statistical_unit_facet',
                         'derive_statistical_unit_facet_partition', 'statistical_unit_facet_reduce',
                         'derive_statistical_history_facet', 'derive_statistical_history_facet_period',
                         'statistical_history_facet_reduce')
          AND state IN ('pending', 'processing', 'waiting')
    ) INTO v_reports_active;

    IF v_reports_active THEN
        SELECT t.command INTO v_reports_step
        FROM worker.tasks AS t
        WHERE t.command IN ('derive_reports_phase', 'derive_reports', 'derive_statistical_history',
                           'statistical_history_reduce', 'derive_statistical_unit_facet',
                           'statistical_unit_facet_reduce', 'derive_statistical_history_facet',
                           'statistical_history_facet_reduce')
          AND t.state IN ('processing', 'waiting')
        ORDER BY t.id DESC LIMIT 1;

        SELECT count(*) INTO v_reports_total
        FROM worker.tasks AS t
        WHERE EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.state IN ('processing', 'waiting')
                AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                'derive_statistical_history_facet')
          );

        SELECT count(*) INTO v_reports_completed
        FROM worker.tasks AS t
        WHERE t.state IN ('completed', 'failed')
          AND EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.state IN ('processing', 'waiting')
                AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                'derive_statistical_history_facet')
          );

        -- Effective counts come from derive_statistical_unit task info (same pipeline run)
        IF v_affected_est IS NULL THEN
            SELECT (t.info->>'effective_establishment_count')::int,
                   (t.info->>'effective_legal_unit_count')::int,
                   (t.info->>'effective_enterprise_count')::int,
                   (t.info->>'effective_power_group_count')::int
            INTO v_affected_est, v_affected_lu, v_affected_en, v_affected_pg
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1;
        END IF;

        v_reports_phase := jsonb_build_object(
            'phase', 'is_deriving_reports',
            'step', v_reports_step,
            'total', COALESCE(v_reports_total, 0),
            'completed', COALESCE(v_reports_completed, 0),
            'effective_establishment_count', v_affected_est,
            'effective_legal_unit_count', v_affected_lu,
            'effective_enterprise_count', v_affected_en,
            'effective_power_group_count', v_affected_pg
        );
        v_phases := v_phases || jsonb_build_array(v_reports_phase);
    END IF;

    -- Only notify if there are active phases
    IF jsonb_array_length(v_phases) > 0 THEN
        v_payload := jsonb_build_object(
            'type', 'pipeline_progress',
            'phases', v_phases
        );
        PERFORM pg_notify('worker_status', v_payload::text);
    END IF;
END;
$notify_task_progress$;

-- 3. import_job_process: write job summary to info
CREATE OR REPLACE PROCEDURE admin.import_job_process(IN job_id integer)
 LANGUAGE plpgsql
AS $import_job_process$
/*
RATIONALE for Control Flow:

This procedure acts as the main "Orchestrator" for a single import job. It is called by the worker system.
Its primary responsibilities are:
1.  Managing the high-level STATE of the import job (e.g., from 'analysing_data' to 'waiting_for_review').
2.  Calling the "Phase Processor" (`admin.import_job_process_phase`) to perform the actual work for a given state.
3.  Interpreting the boolean return value from the Phase Processor to decide on the next action.

The `should_reschedule` variable is key. It holds the return value from `import_job_process_phase`.
- `TRUE`:  Indicates that one unit of work was completed, but the phase is not finished. The Orchestrator MUST reschedule itself to continue processing in the CURRENT state.
- `FALSE`: Indicates that a full pass over all steps in the phase found no work left to do. The Orchestrator MUST transition the job to the NEXT state.
*/
DECLARE
    job public.import_job;
    next_state public.import_job_state;
    should_reschedule BOOLEAN := FALSE;
BEGIN
    -- Get the job details
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import job % not found', job_id;
    END IF;

    -- Set the user context to the job creator
    PERFORM admin.set_import_job_user_context(job_id);

    RAISE DEBUG '[Job %] Processing job in state: %', job_id, job.state;

    -- Block import queue while any OTHER job is waiting for review.
    -- This prevents dependent jobs (e.g., ES) from processing before their
    -- prerequisite (e.g., LU) has been reviewed and approved/rejected.
    -- Jobs that ARE in waiting_for_review/approved/rejected are exempt —
    -- they need to proceed through their own state transitions.
    -- When the review resolves, the after-trigger re-enqueues all blocked jobs.
    IF job.state NOT IN ('waiting_for_review', 'approved', 'rejected') THEN
        PERFORM id FROM public.import_job
        WHERE state = 'waiting_for_review'
          AND id <> job_id
        LIMIT 1;
        IF FOUND THEN
            RAISE DEBUG '[Job %] Blocked: another job is waiting_for_review. Will resume when review resolves.', job_id;
            -- Do NOT reschedule — the after-trigger on review resolution will re-enqueue us.
            RETURN;
        END IF;
    END IF;

    -- Process based on current state
    CASE job.state
        WHEN 'waiting_for_upload' THEN
            RAISE DEBUG '[Job %] Waiting for upload.', job_id;
            should_reschedule := FALSE;

        WHEN 'upload_completed' THEN
            RAISE DEBUG '[Job %] Transitioning to preparing_data.', job_id;
            job := admin.import_job_set_state(job, 'preparing_data');
            should_reschedule := TRUE; -- Reschedule immediately to start prepare

        WHEN 'preparing_data' THEN
            DECLARE
                v_data_row_count BIGINT;
            BEGIN
                RAISE DEBUG '[Job %] Calling import_job_prepare.', job_id;
                PERFORM admin.import_job_prepare(job);

                -- After preparing, recount total_rows from the data table as UPSERT might have changed the count.
                -- Also, recalculate total_analysis_steps_weighted with the correct row count.
                EXECUTE format('SELECT COUNT(*) FROM public.%I', job.data_table_name) INTO v_data_row_count;

                UPDATE public.import_job
                SET
                    total_rows = v_data_row_count,
                    total_analysis_steps_weighted = v_data_row_count * max_analysis_priority
                WHERE id = job.id
                RETURNING * INTO job; -- Refresh local job variable to have updated values.

                RAISE DEBUG '[Job %] Recounted total_rows to % and updated total_analysis_steps_weighted.', job.id, job.total_rows;

                -- ATOMICALLY assign batch_seq AND set state to 'analysing' to satisfy CHECK constraint.
                -- The constraint requires: state='analysing' implies batch_seq IS NOT NULL.
                RAISE DEBUG '[Job %] Assigning batch_seq and transitioning rows to analysing in table %', job_id, job.data_table_name;
                PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.analysis_batch_size, FALSE, 'analysing'::public.import_data_state);

                -- PERFORMANCE FIX: ANALYZE must run AFTER batch_seq is assigned.
                -- Otherwise the planner sees batch_seq = NULL for all rows and estimates
                -- rows=1 for WHERE batch_seq = $1, causing Nested Loop instead of Hash Join.
                RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                EXECUTE format('ANALYZE public.%I', job.data_table_name);

                job := admin.import_job_set_state(job, 'analysing_data');
                should_reschedule := TRUE; -- Reschedule immediately to start analysis
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

                -- Refresh job record to see current step
                SELECT * INTO job FROM public.import_job WHERE id = job.id;

                -- PERFORMANCE FIX: Only recount weighted progress when step changes (not every batch).
                -- This avoids O(n) full table scans after every batch. Instead, we only recount
                -- when moving to a new step or when the phase completes, reducing scans from ~350 to ~10.
                IF job.max_analysis_priority IS NOT NULL AND (
                    job.current_step_code IS DISTINCT FROM v_old_step_code  -- Step changed
                    OR NOT should_reschedule  -- Phase is complete
                ) THEN
                    -- Recount weighted steps for granular progress
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
                ELSIF NOT should_reschedule THEN -- No error, and phase reported no more work
                    -- Compute error and warning counts now that analysis is complete.
                    -- This is the single point where all rows have their final analysis state.
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

                    -- Tri-state review logic:
                    --   TRUE  = always review
                    --   NULL  = review only if errors found during analysis
                    --   FALSE = never review (auto-approve)
                    IF job.review IS TRUE
                       OR (job.review IS NULL AND v_error_count > 0)
                    THEN
                        -- Transition rows from 'analysing' to 'analysed' if review is required
                        RAISE DEBUG '[Job %] Updating data rows from analysing to analysed in table % for review', job_id, job.data_table_name;
                        EXECUTE format($$UPDATE public.%I SET state = %L WHERE state = %L AND action = 'use'$$, job.data_table_name, 'analysed'::public.import_data_state, 'analysing'::public.import_data_state);
                        job := admin.import_job_set_state(job, 'waiting_for_review');
                        RAISE DEBUG '[Job %] Analysis complete, waiting for review.', job_id;
                    ELSE
                        -- ATOMICALLY assign batch_seq, set state to 'processing', AND reset priority in ONE UPDATE.
                        -- This satisfies the CHECK constraint and minimizes UPDATE count for performance.
                        RAISE DEBUG '[Job %] Assigning batch_seq and transitioning rows to processing in table %', job_id, job.data_table_name;
                        PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.processing_batch_size, TRUE, 'processing'::public.import_data_state, TRUE);

                        -- The performance index is now created when the job is generated.
                        -- We still need to ANALYZE to update statistics after the analysis phase.
                        RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                        EXECUTE format('ANALYZE public.%I', job.data_table_name);

                        job := admin.import_job_set_state(job, 'processing_data');
                        RAISE DEBUG '[Job %] Analysis complete, proceeding to processing.', job_id;
                        should_reschedule := TRUE; -- Reschedule to start processing
                    END IF;
                END IF;
                -- If should_reschedule is TRUE from the phase function (and no error), it will be rescheduled.
            END;

        WHEN 'waiting_for_review' THEN
            RAISE DEBUG '[Job %] Waiting for user review.', job_id;
            should_reschedule := FALSE;

        WHEN 'approved' THEN
            BEGIN
                RAISE DEBUG '[Job %] Approved, transitioning to processing_data.', job_id;
                -- ATOMICALLY assign batch_seq, set state to 'processing', AND reset priority in ONE UPDATE.
                RAISE DEBUG '[Job %] Assigning batch_seq and transitioning rows to processing in table % after approval', job_id, job.data_table_name;
                PERFORM admin.import_job_assign_batch_seq(job.data_table_name, job.processing_batch_size, TRUE, 'processing'::public.import_data_state, TRUE);

                -- The performance index is now created when the job is generated.
                -- We still need to ANALYZE to update statistics after the analysis phase.
                RAISE DEBUG '[Job %] Running ANALYZE on data table %', job_id, job.data_table_name;
                EXECUTE format('ANALYZE public.%I', job.data_table_name);

                job := admin.import_job_set_state(job, 'processing_data');
                should_reschedule := TRUE; -- Reschedule immediately to start import
            END;

        WHEN 'rejected' THEN
            RAISE DEBUG '[Job %] Rejected, transitioning to finished.', job_id;
            job := admin.import_job_set_state(job, 'finished');
            should_reschedule := FALSE;

        WHEN 'processing_data' THEN
            BEGIN
                RAISE DEBUG '[Job %] Starting processing phase.', job_id;

                should_reschedule := admin.import_job_processing_phase(job);

                -- PERFORMANCE FIX: Progress tracking is now done incrementally inside import_job_processing_phase.
                -- This avoids a full table scan (COUNT(*) WHERE state = 'processed') after every batch.

                -- Refresh job record to see if an error was set by the phase
                SELECT * INTO job FROM public.import_job WHERE id = job.id;

                RAISE DEBUG '[Job %] Processing phase batch complete. imported_rows: %', job.id, job.imported_rows;

                IF job.error IS NOT NULL THEN
                    RAISE WARNING '[Job %] Error detected during processing phase: %. Job already transitioned to finished.', job.id, job.error;
                    should_reschedule := FALSE;
                ELSIF NOT should_reschedule THEN -- No error, and phase reported no more work
                    job := admin.import_job_set_state(job, 'finished');
                    RAISE DEBUG '[Job %] Processing complete, transitioning to finished.', job_id;
                    -- should_reschedule remains FALSE
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

    -- Write import job summary to info for at-a-glance visibility in worker tasks UI
    -- Refresh job to get latest state after all processing above
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    UPDATE worker.tasks SET info = jsonb_build_object(
        'job_state', job.state::text,
        'total_rows', job.total_rows,
        'imported_rows', job.imported_rows,
        'error_count', job.error_count,
        'warning_count', job.warning_count,
        'current_step', job.current_step_code
    ) WHERE state = 'processing' AND worker_pid = pg_backend_pid();

    IF should_reschedule THEN
        PERFORM admin.reschedule_import_job_process(job_id);
    END IF;
END;
$import_job_process$;

-- Change worker command procedures from SECURITY DEFINER to SECURITY INVOKER.
-- The worker always runs as postgres, so SECURITY DEFINER is unnecessary.
ALTER PROCEDURE worker.command_collect_changes(jsonb) SECURITY INVOKER;
ALTER PROCEDURE worker.command_import_job(jsonb) SECURITY INVOKER;
ALTER PROCEDURE worker.command_import_job_cleanup(jsonb) SECURITY INVOKER;
ALTER PROCEDURE worker.command_task_cleanup(jsonb) SECURITY INVOKER;

END;

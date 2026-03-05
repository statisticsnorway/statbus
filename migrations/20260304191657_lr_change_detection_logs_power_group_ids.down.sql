BEGIN;

-- Restore original base_change_log (drop power_group_ids column)
ALTER TABLE worker.base_change_log DROP COLUMN IF EXISTS power_group_ids;

-- Restore original log_base_change (logs LU IDs for LR, no PG support)
CREATE OR REPLACE FUNCTION worker.log_base_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_columns TEXT;
    v_has_valid_range BOOLEAN;
    v_source TEXT;
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_ent_ids int4multirange;
    v_valid_range datemultirange;
BEGIN
    CASE TG_TABLE_NAME
        WHEN 'establishment' THEN
            v_columns := 'id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'legal_unit' THEN
            v_columns := 'NULL::INT AS est_id, id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'enterprise' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, id AS ent_id';
            v_has_valid_range := FALSE;
        WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'external_ident' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := FALSE;
        WHEN 'legal_relationship' THEN
            -- Special: two LU references per row, capture both influencing and influenced
            v_columns := 'NULL::INT AS est_id, influencing_id AS lu_id, NULL::INT AS ent_id';
            v_has_valid_range := TRUE;
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    IF v_has_valid_range THEN
        v_columns := v_columns || ', valid_range';
    ELSE
        v_columns := v_columns || ', NULL::daterange AS valid_range';
    END IF;

    CASE TG_OP
        WHEN 'INSERT' THEN v_source := format('SELECT %s FROM new_rows', v_columns);
        WHEN 'DELETE' THEN v_source := format('SELECT %s FROM old_rows', v_columns);
        WHEN 'UPDATE' THEN v_source := format('SELECT %s FROM old_rows UNION ALL SELECT %s FROM new_rows', v_columns, v_columns);
        ELSE RAISE EXCEPTION 'log_base_change: unsupported operation %', TG_OP;
    END CASE;

    -- For legal_relationship, also capture the influenced_id
    IF TG_TABLE_NAME = 'legal_relationship' THEN
        CASE TG_OP
            WHEN 'INSERT' THEN v_source := v_source || ' UNION ALL SELECT NULL::INT, influenced_id, NULL::INT, valid_range FROM new_rows';
            WHEN 'DELETE' THEN v_source := v_source || ' UNION ALL SELECT NULL::INT, influenced_id, NULL::INT, valid_range FROM old_rows';
            WHEN 'UPDATE' THEN v_source := v_source || ' UNION ALL SELECT NULL::INT, influenced_id, NULL::INT, valid_range FROM old_rows UNION ALL SELECT NULL::INT, influenced_id, NULL::INT, valid_range FROM new_rows';
        END CASE;
    END IF;

    EXECUTE format(
        'SELECT COALESCE(range_agg(int4range(est_id, est_id, %1$L)) FILTER (WHERE est_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(lu_id, lu_id, %1$L)) FILTER (WHERE lu_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(ent_id, ent_id, %1$L)) FILTER (WHERE ent_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(valid_range) FILTER (WHERE valid_range IS NOT NULL), %3$L::datemultirange)
         FROM (%s) AS mapped',
        '[]', '{}', '{}', v_source
    ) INTO v_est_ids, v_lu_ids, v_ent_ids, v_valid_range;

    IF v_est_ids != '{}'::int4multirange OR v_lu_ids != '{}'::int4multirange OR v_ent_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, edited_by_valid_range)
        VALUES (v_est_ids, v_lu_ids, v_ent_ids, v_valid_range);
    END IF;

    RETURN NULL;
END;
$function$;

-- Restore original command_collect_changes (indirect PG lookup)
CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_pg_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
    v_round_priority_base BIGINT;
BEGIN
    -- Atomically drain all committed rows, merging multiranges.
    FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
        v_est_ids := v_est_ids + v_row.establishment_ids;
        v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
        v_ent_ids := v_ent_ids + v_row.enterprise_ids;
        v_valid_range := v_valid_range + v_row.edited_by_valid_range;
    END LOOP;

    -- Clear crash recovery flag
    UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;

    -- If any changes exist, enqueue derive
    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange THEN

        -- ROUND PRIORITY: Read own priority as the round base.
        SELECT priority INTO v_round_priority_base
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        -- Compute affected power group IDs from legal_relationship using containment operator
        SELECT COALESCE(
            range_agg(int4range(lr.derived_power_group_id, lr.derived_power_group_id, '[]')),
            '{}'::int4multirange
        )
        INTO v_pg_ids
        FROM public.legal_relationship AS lr
        WHERE lr.derived_power_group_id IS NOT NULL
          AND (v_lu_ids @> lr.influencing_id OR v_lu_ids @> lr.influenced_id);

        -- If date range is empty, look up actual valid ranges from affected units
        IF v_valid_range = '{}'::datemultirange THEN
            SELECT COALESCE(range_agg(vr)::datemultirange, '{}'::datemultirange)
            INTO v_valid_range
            FROM (
                SELECT valid_range AS vr FROM public.establishment AS est
                  WHERE v_est_ids @> est.id
                UNION ALL
                SELECT valid_range AS vr FROM public.legal_unit AS lu
                  WHERE v_lu_ids @> lu.id
            ) AS units;
        END IF;

        -- Extract date bounds for enqueue_derive interface
        v_valid_from := lower(v_valid_range);
        v_valid_until := upper(v_valid_range);

        PERFORM worker.enqueue_derive_statistical_unit(
            p_establishment_id_ranges := v_est_ids,
            p_legal_unit_id_ranges := v_lu_ids,
            p_enterprise_id_ranges := v_ent_ids,
            p_power_group_id_ranges := v_pg_ids,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until,
            p_round_priority_base := v_round_priority_base
        );
    END IF;
END;
$procedure$;

-- Drop LR-specific trigger functions and restore generic trigger
DROP TRIGGER IF EXISTS b_legal_relationship_ensure_collect_insert ON public.legal_relationship;
DROP TRIGGER IF EXISTS b_legal_relationship_ensure_collect_update ON public.legal_relationship;
DROP TRIGGER IF EXISTS b_legal_relationship_ensure_collect_delete ON public.legal_relationship;
DROP FUNCTION IF EXISTS worker.ensure_collect_changes_for_legal_relationship();

-- Remove power_group change detection triggers
DROP TRIGGER IF EXISTS a_power_group_log_insert ON public.power_group;
DROP TRIGGER IF EXISTS a_power_group_log_update ON public.power_group;
DROP TRIGGER IF EXISTS a_power_group_log_delete ON public.power_group;
DROP TRIGGER IF EXISTS b_power_group_ensure_collect ON public.power_group;

CREATE TRIGGER b_legal_relationship_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.legal_relationship
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

-- Restore original notify_is_deriving_statistical_units_start (NULLs counts)
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_start()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  INSERT INTO worker.pipeline_progress (phase, step, total, completed, updated_at)
  VALUES ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0, clock_timestamp())
  ON CONFLICT (phase) DO UPDATE SET
    step = EXCLUDED.step, total = 0, completed = 0,
    affected_establishment_count = NULL, affected_legal_unit_count = NULL,
    affected_enterprise_count = NULL, affected_power_group_count = NULL,
    updated_at = clock_timestamp();

  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text);
END;
$procedure$;

-- Restore original statistical_unit_flush_staging (dead pg_notify)
CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    UPDATE worker.pipeline_progress
    SET step = 'statistical_unit_flush_staging', updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    PERFORM pg_notify('pipeline_progress', '');

    CALL public.statistical_unit_flush_staging();

    UPDATE worker.pipeline_progress
    SET completed = total, updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    PERFORM pg_notify('pipeline_progress', '');
END;
$procedure$;

-- Restore original derive_statistical_unit (without notify_pipeline_progress call)
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL,
    p_power_group_id_ranges int4multirange DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_until date DEFAULT NULL,
    p_task_id bigint DEFAULT NULL,
    p_round_priority_base bigint DEFAULT NULL
)
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
    -- Unit count accumulators for pipeline progress
    v_enterprise_count INT := 0;
    v_legal_unit_count INT := 0;
    v_establishment_count INT := 0;
    v_power_group_count INT := 0;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    -- Priority for children: use round base if available, otherwise nextval
    v_child_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        -- No dirty partition tracking needed: full refresh recomputes all partitions
        FOR v_batch IN SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
            -- Accumulate unit counts
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;

        -- Spawn a separate batch for all power groups (not in enterprise connectivity graph)
        v_power_group_count := (SELECT COUNT(*)::int FROM public.power_group);
        IF v_power_group_count > 0 THEN
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch_count + 1,
                    'power_group_ids', (SELECT COALESCE(array_agg(id), '{}') FROM public.power_group),
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END IF;
    ELSE
        -- Partial refresh: convert multiranges to arrays
        v_establishment_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
        v_legal_unit_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r));
        v_enterprise_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r));
        v_power_group_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_power_group_id_ranges, '{}'::int4multirange)) AS t(r));

        -- ORPHAN CLEANUP: Handle deleted entities BEFORE batching
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(SELECT id FROM unnest(v_enterprise_ids) AS id EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids));
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs', array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs', array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs', array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_orphan_power_group_ids := ARRAY(SELECT id FROM unnest(v_power_group_ids) AS id EXCEPT SELECT pg.id FROM public.power_group AS pg WHERE pg.id = ANY(v_power_group_ids));
            IF COALESCE(array_length(v_orphan_power_group_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan power_group IDs', array_length(v_orphan_power_group_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timeline_power_group WHERE power_group_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
            END IF;
        END IF;

        -- BATCHING: EST/LU/EN use closed-group batches
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0
           OR COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0
           OR COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            IF to_regclass('pg_temp._batches') IS NOT NULL THEN DROP TABLE _batches; END IF;
            CREATE TEMP TABLE _batches ON COMMIT DROP AS
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
                p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
                p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
            );
            -- Dirty partition tracking
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings))
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _batches AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _batches AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _batches AS b
            ) AS t WHERE t.unit_id IS NOT NULL
            ON CONFLICT DO NOTHING;
            RAISE DEBUG 'derive_statistical_unit: Tracked dirty facet partitions for closed group across % batches', (SELECT count(*) FROM _batches);

            -- Spawn batch children and accumulate unit counts
            FOR v_batch IN SELECT * FROM _batches LOOP
                v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
                v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
                v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

                PERFORM worker.spawn(
                    p_command := 'statistical_unit_refresh_batch',
                    p_payload := jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch.batch_seq,
                        'enterprise_ids', v_batch.enterprise_ids,
                        'legal_unit_ids', v_batch.legal_unit_ids,
                        'establishment_ids', v_batch.establishment_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id := p_task_id,
                    p_priority := v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;

        -- PG batch: single batch with all affected power_group IDs (always, not conditional on two-pass)
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_power_group_count := array_length(v_power_group_ids, 1);

            -- Dirty partition tracking for PG
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq('power_group', pg_id, (SELECT analytics_partition_count FROM public.settings))
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch_count + 1,
                    'power_group_ids', v_power_group_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END IF;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%, pg=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count, v_power_group_count;

    -- Create/update Phase 1 row with unit counts
    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count,
         affected_power_group_count, updated_at)
    VALUES
        ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count,
         v_power_group_count, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        affected_power_group_count = EXCLUDED.affected_power_group_count,
        updated_at = EXCLUDED.updated_at;

    -- Pre-create Phase 2 row with counts (pending, visible to user before phase 2 starts)
    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count,
         affected_power_group_count, updated_at)
    VALUES
        ('is_deriving_reports', NULL, 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count,
         v_power_group_count, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        affected_power_group_count = EXCLUDED.affected_power_group_count,
        updated_at = EXCLUDED.updated_at;

    -- Refresh derived data (used flags)
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- Pipeline routing: always flush then reports (no more derive_power_groups in pipeline)
    PERFORM worker.enqueue_statistical_unit_flush_staging(
        p_round_priority_base := p_round_priority_base
    );
    RAISE DEBUG 'derive_statistical_unit: Enqueued flush_staging task';
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until,
        p_round_priority_base := p_round_priority_base
    );
    RAISE DEBUG 'derive_statistical_unit: Enqueued derive_reports';
END;
$derive_statistical_unit$;

-- Drop helper function
DROP FUNCTION IF EXISTS worker.notify_pipeline_progress();

-- Restore original notify_is_deriving_statistical_units_stop
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- Check if any Phase 1 tasks are still pending or running.
  -- By the time after_procedure fires, the calling task is already in 'completed' state,
  -- so this only finds OTHER Phase 1 tasks that still need to run.
  -- Exclude collect_changes: it always has a pending task queued via dedup index
  -- as the entry-point trigger — it's not actual derive work.
  IF EXISTS (
    SELECT 1 FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON cr.command = t.command
    WHERE cr.phase = 'is_deriving_statistical_units'
    AND t.command <> 'collect_changes'
    AND t.state IN ('pending', 'processing', 'waiting')
  ) THEN
    RETURN;  -- More Phase 1 work pending, don't stop yet
  END IF;

  -- If collect_changes is pending, more Phase 1 work is guaranteed
  -- (collect_changes always leads to derive_statistical_unit), so stay active.
  -- Reset to collect_changes step with unknown counts (not yet collected).
  IF EXISTS (
    SELECT 1 FROM worker.tasks
    WHERE command = 'collect_changes'
    AND state = 'pending'
  ) THEN
    UPDATE worker.pipeline_progress
    SET step = 'collect_changes', total = 0, completed = 0,
        affected_establishment_count = NULL,
        affected_legal_unit_count = NULL,
        affected_enterprise_count = NULL,
        affected_power_group_count = NULL,
        updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    RETURN;
  END IF;

  DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_statistical_units';
  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text
  );
END;
$procedure$;

END;

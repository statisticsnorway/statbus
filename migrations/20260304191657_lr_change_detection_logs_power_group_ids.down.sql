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
            range_agg(int4range(lr.power_group_id, lr.power_group_id, '[]')),
            '{}'::int4multirange
        )
        INTO v_pg_ids
        FROM public.legal_relationship AS lr
        WHERE lr.power_group_id IS NOT NULL
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

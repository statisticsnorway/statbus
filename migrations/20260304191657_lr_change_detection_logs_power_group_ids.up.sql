BEGIN;

-- =============================================================================
-- Fix 1: Add power_group_ids column to base_change_log
-- =============================================================================
-- LR changes only affect power groups. This column allows direct PG ID logging
-- instead of the indirect lookup that fails when PGs aren't assigned yet.
ALTER TABLE worker.base_change_log
ADD COLUMN power_group_ids int4multirange NOT NULL DEFAULT '{}'::int4multirange;

-- =============================================================================
-- Fix 2: log_base_change — LR case logs PG IDs only (not LU IDs)
-- =============================================================================
-- Previously logged influencing_id/influenced_id as lu_id, which:
-- 1. Triggered unnecessary LU/enterprise re-derivation
-- 2. Never captured power_group_id (wasn't in base_change_log schema)
-- 3. The indirect PG lookup in collect_changes failed because PG isn't assigned
--    yet at drain time during initial import
CREATE OR REPLACE FUNCTION worker.log_base_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $log_base_change$
DECLARE
    v_columns TEXT;
    v_has_valid_range BOOLEAN;
    v_has_power_group BOOLEAN := FALSE;
    v_where_clause TEXT := '';
    v_source TEXT;
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_ent_ids int4multirange;
    v_pg_ids int4multirange;
    v_valid_range datemultirange;
BEGIN
    CASE TG_TABLE_NAME
        WHEN 'establishment' THEN
            v_columns := 'id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'legal_unit' THEN
            v_columns := 'NULL::INT AS est_id, id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'enterprise' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'external_ident' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'legal_relationship' THEN
            -- LR changes only affect power groups, not individual LUs/enterprises.
            -- Only log when power_group_id is assigned (NULL = PG not yet linked).
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, power_group_id AS pg_id';
            v_has_valid_range := TRUE;
            v_has_power_group := TRUE;
            v_where_clause := ' WHERE power_group_id IS NOT NULL';
        WHEN 'power_group' THEN
            -- PG metadata changes (name, type_id, etc.) affect PG statistical units.
            -- Timeless table — no valid_range.
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, id AS pg_id';
            v_has_valid_range := FALSE;
            v_has_power_group := TRUE;
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    IF v_has_valid_range THEN
        v_columns := v_columns || ', valid_range';
    ELSE
        v_columns := v_columns || ', NULL::daterange AS valid_range';
    END IF;

    CASE TG_OP
        WHEN 'INSERT' THEN v_source := format('SELECT %s FROM new_rows%s', v_columns, v_where_clause);
        WHEN 'DELETE' THEN v_source := format('SELECT %s FROM old_rows%s', v_columns, v_where_clause);
        WHEN 'UPDATE' THEN v_source := format('SELECT %s FROM old_rows%s UNION ALL SELECT %s FROM new_rows%s', v_columns, v_where_clause, v_columns, v_where_clause);
        ELSE RAISE EXCEPTION 'log_base_change: unsupported operation %', TG_OP;
    END CASE;

    -- No UNION ALL for influenced_id — LR changes only log PG IDs, not individual LU IDs

    EXECUTE format(
        'SELECT COALESCE(range_agg(int4range(est_id, est_id, %1$L)) FILTER (WHERE est_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(lu_id, lu_id, %1$L)) FILTER (WHERE lu_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(ent_id, ent_id, %1$L)) FILTER (WHERE ent_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(pg_id, pg_id, %1$L)) FILTER (WHERE pg_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(valid_range) FILTER (WHERE valid_range IS NOT NULL), %3$L::datemultirange)
         FROM (%s) AS mapped',
        '[]', '{}', '{}', v_source
    ) INTO v_est_ids, v_lu_ids, v_ent_ids, v_pg_ids, v_valid_range;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, edited_by_valid_range)
        VALUES (v_est_ids, v_lu_ids, v_ent_ids, v_pg_ids, v_valid_range);
    END IF;

    RETURN NULL;
END;
$log_base_change$;

-- =============================================================================
-- Fix 3: collect_changes — drain PG IDs directly from log (no indirect lookup)
-- =============================================================================
-- Previously computed v_pg_ids with an indirect lookup against legal_relationship,
-- which failed because PG IDs weren't assigned yet during initial import.
-- Now drains power_group_ids directly from base_change_log.
CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $command_collect_changes$
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
        v_pg_ids := v_pg_ids + v_row.power_group_ids;
        v_valid_range := v_valid_range + v_row.edited_by_valid_range;
    END LOOP;

    -- Clear crash recovery flag
    UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;

    -- If any changes exist, enqueue derive
    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN

        -- ROUND PRIORITY: Read own priority as the round base.
        SELECT priority INTO v_round_priority_base
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        -- No indirect PG lookup needed — PG IDs come directly from base_change_log

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
    ELSE
        -- Fix 5: Defensive cleanup when collect_changes finds 0 changes.
        -- This prevents Phase 1 from getting stuck permanently yellow.
        DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_statistical_units';
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
END;
$command_collect_changes$;

-- =============================================================================
-- Fix 4: Replace generic ensure_collect trigger on LR with PG-aware version
-- =============================================================================
-- The generic trigger schedules collection even when no PG is assigned (useless).
-- The LR-specific version checks power_group_id IS NOT NULL before scheduling.

-- Drop the existing generic trigger
DROP TRIGGER IF EXISTS b_legal_relationship_ensure_collect ON public.legal_relationship;

-- Create LR-specific trigger function that filters on power_group_id
CREATE OR REPLACE FUNCTION worker.ensure_collect_changes_for_legal_relationship()
RETURNS trigger LANGUAGE plpgsql AS $ensure_collect_changes_for_legal_relationship$
BEGIN
    -- Only schedule collection if any changed row has a PG assigned.
    -- During initial import, LR rows are inserted with power_group_id = NULL,
    -- then process_power_group_link assigns PG IDs (triggering this again).
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF NOT EXISTS (SELECT 1 FROM new_rows WHERE power_group_id IS NOT NULL) THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Standard scheduling logic (same as ensure_collect_changes)
    UPDATE worker.base_change_log_has_pending
    SET has_pending = TRUE WHERE has_pending = FALSE;

    INSERT INTO worker.tasks (command, payload)
    VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
    ON CONFLICT (command)
    WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
    DO NOTHING;

    PERFORM pg_notify('worker_tasks', 'analytics');
    RETURN NULL;
END;
$ensure_collect_changes_for_legal_relationship$;

-- INSERT: use LR-specific function that checks power_group_id
CREATE TRIGGER b_legal_relationship_ensure_collect_insert
AFTER INSERT ON public.legal_relationship
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes_for_legal_relationship();

-- UPDATE: use LR-specific function that checks power_group_id
CREATE TRIGGER b_legal_relationship_ensure_collect_update
AFTER UPDATE ON public.legal_relationship
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes_for_legal_relationship();

-- DELETE: always schedule (PG was set before deletion, log already captured it)
CREATE TRIGGER b_legal_relationship_ensure_collect_delete
AFTER DELETE ON public.legal_relationship
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

-- =============================================================================
-- Fix 4b: Add change detection triggers on power_group
-- =============================================================================
-- Changes to power_group metadata (short_name, name, type_id, etc.) should
-- trigger PG re-derivation. The log_base_change function now handles
-- 'power_group' via the new WHEN case above.

-- Log changes (same pattern as other tables: a_ prefix for logging triggers)
CREATE TRIGGER a_power_group_log_insert
AFTER INSERT ON public.power_group
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change();

CREATE TRIGGER a_power_group_log_update
AFTER UPDATE ON public.power_group
REFERENCING NEW TABLE AS new_rows OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change();

CREATE TRIGGER a_power_group_log_delete
AFTER DELETE ON public.power_group
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change();

-- Schedule collection (same generic function as most tables)
CREATE TRIGGER b_power_group_ensure_collect
AFTER INSERT OR DELETE OR UPDATE ON public.power_group
FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes();

-- =============================================================================
-- Fix 6: notify_is_deriving_statistical_units_stop — preserve counts on reset
-- =============================================================================
-- When resetting to collect_changes step, don't NULL the affected counts.
-- This keeps the counts visible in the navbar while collecting more changes.
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_stop()
 LANGUAGE plpgsql
AS $notify_is_deriving_statistical_units_stop$
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
  -- Reset to collect_changes step with cleared counts — the previous cycle's
  -- counts are stale and the new collect_changes will set fresh ones.
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
$notify_is_deriving_statistical_units_stop$;

END;

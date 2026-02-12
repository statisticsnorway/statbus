-- Down Migration 20260212220011: fix_base_change_log_review_findings
BEGIN;

-- Restore original command_collect_changes (without valid_range lookup or comments)
CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $procedure$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
BEGIN
    -- Atomically drain all committed rows, merging multiranges
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
        -- Extract date bounds for enqueue_derive interface (takes DATE, not daterange)
        v_valid_from := lower(v_valid_range);
        v_valid_until := upper(v_valid_range);

        PERFORM worker.enqueue_derive_statistical_unit(
            p_establishment_id_ranges := v_est_ids,
            p_legal_unit_id_ranges := v_lu_ids,
            p_enterprise_id_ranges := v_ent_ids,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        );
    END IF;
END;
$procedure$;

-- Restore original ensure_collect_changes (without pg_notify comment)
CREATE OR REPLACE FUNCTION worker.ensure_collect_changes()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Set LOGGED flag for crash recovery (no-op if already TRUE)
    UPDATE worker.base_change_log_has_pending
    SET has_pending = TRUE WHERE has_pending = FALSE;

    -- Enqueue collect_changes task (DO NOTHING = no row lock!)
    INSERT INTO worker.tasks (command, payload)
    VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
    ON CONFLICT (command)
    WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
    DO NOTHING;

    PERFORM pg_notify('worker_tasks', 'analytics');
    RETURN NULL;
END;
$function$;

-- Restore original log_base_change (string concatenation style)
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
    -- Column mapping based on table name
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
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    -- Add valid_range to column list
    IF v_has_valid_range THEN
        v_columns := v_columns || ', valid_range';
    ELSE
        v_columns := v_columns || ', NULL::daterange AS valid_range';
    END IF;

    -- Build source query based on operation
    CASE TG_OP
        WHEN 'INSERT' THEN
            v_source := format('SELECT %s FROM new_rows', v_columns);
        WHEN 'DELETE' THEN
            v_source := format('SELECT %s FROM old_rows', v_columns);
        WHEN 'UPDATE' THEN
            v_source := format('SELECT %s FROM old_rows UNION ALL SELECT %s FROM new_rows',
                               v_columns, v_columns);
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported operation %', TG_OP;
    END CASE;

    -- Aggregate into multiranges
    -- CRITICAL: Use FILTER (WHERE col IS NOT NULL) to avoid int4range(NULL,NULL,'[]')
    -- which produces unbounded range (,) meaning ALL integers, not empty.
    EXECUTE format(
        'SELECT COALESCE(range_agg(int4range(est_id, est_id, %1$L)) FILTER (WHERE est_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(lu_id, lu_id, %1$L)) FILTER (WHERE lu_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(ent_id, ent_id, %1$L)) FILTER (WHERE ent_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(valid_range) FILTER (WHERE valid_range IS NOT NULL), %3$L::datemultirange)
         FROM (%s) AS mapped',
        '[]', '{}', '{}', v_source
    ) INTO v_est_ids, v_lu_ids, v_ent_ids, v_valid_range;

    -- Only insert if there's actually something to record
    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, edited_by_valid_range)
        VALUES (v_est_ids, v_lu_ids, v_ent_ids, v_valid_range);
    END IF;

    RETURN NULL;
END;
$function$;

-- Revert autovacuum tuning
ALTER TABLE worker.base_change_log RESET (
    autovacuum_vacuum_threshold,
    autovacuum_vacuum_scale_factor
);

-- Drop single-row constraint
DROP INDEX worker.base_change_log_has_pending_single_row;

END;

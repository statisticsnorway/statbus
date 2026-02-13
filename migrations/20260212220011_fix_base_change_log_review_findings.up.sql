-- Migration 20260212220011: fix_base_change_log_review_findings
-- Addresses review findings from base_change_log migration:
--   Fix 2: Single-row constraint on base_change_log_has_pending
--   Fix 3: Look up valid ranges for tables without valid_range
--   Fix 6: Use format(%I) for column names in log_base_change
--   Fix 7: Autovacuum tuning for base_change_log
--   Skip 4/5: Documentation comments
BEGIN;

-- Fix 2: Single-row constraint on base_change_log_has_pending
-- Prevents inserting additional rows (table must always have exactly 1 row).
CREATE UNIQUE INDEX base_change_log_has_pending_single_row
    ON worker.base_change_log_has_pending ((true));

-- Fix 7: Autovacuum tuning for base_change_log
-- UNLOGGED table drained frequently via DELETE ... RETURNING; trigger autovacuum
-- after 50 dead tuples regardless of table size.
ALTER TABLE worker.base_change_log SET (
    autovacuum_vacuum_threshold = 50,
    autovacuum_vacuum_scale_factor = 0.0
);

-- Fix 6: Use format(%I) for column names in log_base_change
CREATE OR REPLACE FUNCTION worker.log_base_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $log_base_change$
DECLARE
    v_est_col TEXT;   -- Column name for establishment id, or NULL to use NULL::INT
    v_lu_col TEXT;    -- Column name for legal unit id, or NULL to use NULL::INT
    v_ent_col TEXT;   -- Column name for enterprise id, or NULL to use NULL::INT
    v_has_valid_range BOOLEAN;
    v_columns TEXT;
    v_source TEXT;
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_ent_ids int4multirange;
    v_valid_range datemultirange;
BEGIN
    -- Column mapping based on table name
    CASE TG_TABLE_NAME
        WHEN 'establishment' THEN
            v_est_col := 'id'; v_lu_col := 'legal_unit_id'; v_ent_col := 'enterprise_id';
            v_has_valid_range := TRUE;
        WHEN 'legal_unit' THEN
            v_est_col := NULL; v_lu_col := 'id'; v_ent_col := 'enterprise_id';
            v_has_valid_range := TRUE;
        WHEN 'enterprise' THEN
            v_est_col := NULL; v_lu_col := NULL; v_ent_col := 'id';
            v_has_valid_range := FALSE;
        WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
            v_est_col := 'establishment_id'; v_lu_col := 'legal_unit_id'; v_ent_col := NULL;
            v_has_valid_range := TRUE;
        WHEN 'external_ident' THEN
            v_est_col := 'establishment_id'; v_lu_col := 'legal_unit_id'; v_ent_col := 'enterprise_id';
            v_has_valid_range := FALSE;
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    -- Build column list with proper identifier escaping
    v_columns := concat_ws(', ',
        CASE WHEN v_est_col IS NOT NULL
             THEN format('%I AS est_id', v_est_col)
             ELSE 'NULL::INT AS est_id' END,
        CASE WHEN v_lu_col IS NOT NULL
             THEN format('%I AS lu_id', v_lu_col)
             ELSE 'NULL::INT AS lu_id' END,
        CASE WHEN v_ent_col IS NOT NULL
             THEN format('%I AS ent_id', v_ent_col)
             ELSE 'NULL::INT AS ent_id' END,
        CASE WHEN v_has_valid_range
             THEN format('%I', 'valid_range')
             ELSE 'NULL::daterange AS valid_range' END
    );

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
$log_base_change$;


-- Skip 5: Add documentation comment about pg_notify on DO NOTHING
CREATE OR REPLACE FUNCTION worker.ensure_collect_changes()
 RETURNS trigger
 LANGUAGE plpgsql
AS $ensure_collect_changes$
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

    -- pg_notify fires even when ON CONFLICT DO NOTHING matches (PG provides
    -- no way to detect this). Cost is negligible: worker wakes, finds nothing, sleeps.
    PERFORM pg_notify('worker_tasks', 'analytics');
    RETURN NULL;
END;
$ensure_collect_changes$;


-- Fix 3: Look up actual valid ranges for tables without valid_range
-- Skip 4: Document why FOR UPDATE is not needed on drain
CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $command_collect_changes$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
BEGIN
    -- Atomically drain all committed rows, merging multiranges.
    -- No FOR UPDATE needed: structured concurrency ensures only one
    -- collect_changes runs at a time (serial top-level analytics tasks).
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

        -- If date range is empty (all changes from tables without valid_range,
        -- e.g. enterprise or external_ident), look up actual valid ranges from
        -- affected units to avoid full-scope refresh.
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
            -- Note: enterprise has no valid_range. If only enterprise IDs changed
            -- and no est/lu IDs, v_valid_range stays empty -> enqueue_derive
            -- COALESCEs to -infinity/infinity, which is correct for structural changes.
        END IF;

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
$command_collect_changes$;

END;

```sql
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
    v_est_count INT;
    v_lu_count INT;
    v_ent_count INT;
    v_pg_count INT;
BEGIN
    -- Atomically drain all committed rows, merging multiranges.
    FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
        v_est_ids := v_est_ids + v_row.establishment_ids;
        v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
        v_ent_ids := v_ent_ids + v_row.enterprise_ids;
        v_pg_ids := v_pg_ids + v_row.power_group_ids;
        v_valid_range := v_valid_range + v_row.valid_ranges;
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

        -- Compute approximate counts from multiranges for pipeline progress.
        -- SUM(upper-lower) works because PostgreSQL normalizes [x,x] to [x,x+1).
        SELECT COALESCE(SUM(upper(r) - lower(r)), 0)::int INTO v_est_count FROM unnest(v_est_ids) AS t(r);
        SELECT COALESCE(SUM(upper(r) - lower(r)), 0)::int INTO v_lu_count FROM unnest(v_lu_ids) AS t(r);
        SELECT COALESCE(SUM(upper(r) - lower(r)), 0)::int INTO v_ent_count FROM unnest(v_ent_ids) AS t(r);
        SELECT COALESCE(SUM(upper(r) - lower(r)), 0)::int INTO v_pg_count FROM unnest(v_pg_ids) AS t(r);

        -- Set approximate counts in pipeline_progress immediately.
        UPDATE worker.pipeline_progress
        SET affected_establishment_count = NULLIF(v_est_count, 0),
            affected_legal_unit_count = NULLIF(v_lu_count, 0),
            affected_enterprise_count = NULLIF(v_ent_count, 0),
            affected_power_group_count = NULLIF(v_pg_count, 0),
            updated_at = clock_timestamp()
        WHERE phase = 'is_deriving_statistical_units';

        -- Notify frontend with updated counts
        PERFORM worker.notify_pipeline_progress();

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
        -- Defensive cleanup when collect_changes finds 0 changes.
        -- This prevents Phase 1 from getting stuck permanently yellow.
        DELETE FROM worker.pipeline_progress WHERE phase = 'is_deriving_statistical_units';
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
END;
$procedure$
```

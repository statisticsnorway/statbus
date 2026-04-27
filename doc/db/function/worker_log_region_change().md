```sql
CREATE OR REPLACE FUNCTION worker.log_region_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_valid_ranges datemultirange;
    v_source TEXT;
BEGIN
    -- Build source query based on operation
    CASE TG_OP
        WHEN 'INSERT' THEN v_source := 'new_rows';
        WHEN 'DELETE' THEN v_source := 'old_rows';
        WHEN 'UPDATE' THEN v_source := 'old_rows UNION ALL SELECT * FROM new_rows';
        ELSE RAISE EXCEPTION 'log_region_change: unsupported operation %', TG_OP;
    END CASE;

    -- Find affected units by joining region → location
    EXECUTE format(
        $SQL$
        SELECT
            COALESCE(range_agg(int4range(l.establishment_id, l.establishment_id, '[]')) FILTER (WHERE l.establishment_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(int4range(l.legal_unit_id, l.legal_unit_id, '[]')) FILTER (WHERE l.legal_unit_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(l.valid_range) FILTER (WHERE l.valid_range IS NOT NULL), '{}'::datemultirange)
        FROM (%s) AS affected_regions
        JOIN public.location AS l ON l.region_id = affected_regions.id
        $SQL$,
        format('SELECT * FROM %s', v_source)
    ) INTO v_est_ids, v_lu_ids, v_valid_ranges;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, '{}'::int4multirange, '{}'::int4multirange, v_valid_ranges);

        -- Folded from former worker.ensure_collect_changes (rc.66, task #32):
        -- scheduling now fires only when actual change data was logged.
        UPDATE worker.base_change_log_has_pending
        SET has_pending = TRUE WHERE has_pending = FALSE;

        INSERT INTO worker.tasks (command, payload)
        VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
        ON CONFLICT (command)
        WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
        DO NOTHING;

        PERFORM pg_notify('worker_tasks', 'analytics');
    END IF;

    RETURN NULL;
END;
$function$
```

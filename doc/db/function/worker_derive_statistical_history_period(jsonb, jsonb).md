```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := NULLIF(payload->>'hash_partition', '')::int4range;
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%, hash_partition=%',
                 v_resolution, v_year, v_month, v_hash_partition;

    IF v_hash_partition IS NOT NULL THEN
        -- Range-overlap DELETE on the slot value: stored rows are singletons
        -- whose lower(hash_partition) equals the slot, so this matches every
        -- stored row whose slot falls in the spawn's slot range. Works for
        -- any spawn shape (singleton dirty children OR wide full-rebuild
        -- children) because storage geometry is uniform per-slot.
        DELETE FROM public.statistical_history
         WHERE resolution = v_resolution
           AND year = v_year
           AND month IS NOT DISTINCT FROM v_month
           AND hash_partition IS NOT NULL
           AND lower(hash_partition) >= lower(v_hash_partition)
           AND lower(hash_partition) <  upper(v_hash_partition);

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month, v_hash_partition) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    ELSE
        -- Manual escape hatch: full-period rebuild. The DELETE drops the
        -- `hash_partition IS NULL` filter (vs rc.42), wiping every row for
        -- the period — both the NULL summary and any per-slot rows. The
        -- INSERT then writes fresh per-slot rows from def(...). Reduce
        -- rebuilds the NULL summary on its next run.
        DELETE FROM public.statistical_history
         WHERE resolution = v_resolution
           AND year = v_year
           AND month IS NOT DISTINCT FROM v_month;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%, hash_partition=%',
                 v_resolution, v_year, v_month, v_hash_partition;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
```

```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_partition_seq integer := (payload->>'partition_seq')::integer;
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;

    IF v_partition_seq IS NOT NULL THEN
        -- Partition-aware: delete and reinsert for this specific partition × period
        DELETE FROM public.statistical_history
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq = v_partition_seq;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month, v_partition_seq) AS h;
    ELSE
        -- Legacy non-partitioned path (backwards compatible for full refresh without partitions)
        DELETE FROM public.statistical_history
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq IS NULL;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;
END;
$procedure$
```

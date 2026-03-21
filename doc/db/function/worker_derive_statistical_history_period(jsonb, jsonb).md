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
    -- Support both single partition_seq (legacy) and range
    v_partition_seq_from integer := COALESCE(
        (payload->>'partition_seq_from')::integer,
        (payload->>'partition_seq')::integer
    );
    v_partition_seq_to integer := COALESCE(
        (payload->>'partition_seq_to')::integer,
        (payload->>'partition_seq')::integer
    );
    v_row_count bigint;
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%, partition_seq=[%,%]',
                 v_resolution, v_year, v_month, v_partition_seq_from, v_partition_seq_to;

    IF v_partition_seq_from IS NOT NULL THEN
        DELETE FROM public.statistical_history
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq BETWEEN v_partition_seq_from AND v_partition_seq_to;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month, v_partition_seq_from, v_partition_seq_to) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    ELSE
        DELETE FROM public.statistical_history
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq IS NULL;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%, partition_seq=[%,%]',
                 v_resolution, v_year, v_month, v_partition_seq_from, v_partition_seq_to;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
```

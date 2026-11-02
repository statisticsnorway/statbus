```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    v_row_count bigint;
BEGIN
    DELETE FROM public.statistical_history_facet_partitions
     WHERE resolution = v_resolution
       AND year = v_year
       AND month IS NOT DISTINCT FROM v_month
       AND hash_slot >= lower(v_hash_partition)
       AND hash_slot <  upper(v_hash_partition);

    INSERT INTO public.statistical_history_facet_partitions
    SELECT * FROM public.statistical_history_facet_def(
        v_resolution, v_year, v_month, v_hash_partition
    );

    GET DIAGNOSTICS v_row_count := ROW_COUNT;
    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
```

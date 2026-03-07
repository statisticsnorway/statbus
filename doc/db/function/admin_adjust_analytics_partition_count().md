```sql
CREATE OR REPLACE PROCEDURE admin.adjust_analytics_partition_count()
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'admin', 'pg_temp'
AS $procedure$
DECLARE
    v_unit_count bigint;
    v_current_count int;
    v_desired_count int;
BEGIN
    SELECT analytics_partition_count INTO v_current_count FROM public.settings;
    SELECT count(*) INTO v_unit_count FROM public.statistical_unit;

    v_desired_count := CASE
        WHEN v_unit_count <= 5000 THEN 4
        WHEN v_unit_count <= 25000 THEN 8
        WHEN v_unit_count <= 100000 THEN 16
        WHEN v_unit_count <= 500000 THEN 32
        WHEN v_unit_count <= 2000000 THEN 64
        ELSE 128
    END;

    IF v_desired_count != v_current_count THEN
        RAISE LOG 'adjust_analytics_partition_count: % units → % partitions (was %)',
            v_unit_count, v_desired_count, v_current_count;
        -- This fires the settings trigger which handles propagation
        UPDATE public.settings SET analytics_partition_count = v_desired_count;
    END IF;
END;
$procedure$
```

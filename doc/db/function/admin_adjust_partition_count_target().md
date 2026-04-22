```sql
CREATE OR REPLACE PROCEDURE admin.adjust_partition_count_target()
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'admin', 'public', 'pg_temp'
AS $procedure$
DECLARE
    v_unit_count bigint;
    v_desired    integer;
BEGIN
    SELECT count(*) INTO v_unit_count FROM public.statistical_unit;
    -- Thresholds tuned for 16384-slot space; keep target small for tiny
    -- datasets, scale up as unit count grows. See proposal §7.
    v_desired := CASE
        WHEN v_unit_count <=      100 THEN     4
        WHEN v_unit_count <=   10000 THEN    16
        WHEN v_unit_count <=  100000 THEN    64
        WHEN v_unit_count <= 1000000 THEN   128
        WHEN v_unit_count <= 5000000 THEN   256
        ELSE                                 512
    END;
    UPDATE public.settings
       SET partition_count_target = v_desired
     WHERE partition_count_target IS DISTINCT FROM v_desired;
END;
$procedure$
```

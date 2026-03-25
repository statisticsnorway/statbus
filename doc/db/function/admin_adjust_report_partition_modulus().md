```sql
CREATE OR REPLACE PROCEDURE admin.adjust_report_partition_modulus()
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'admin', 'pg_temp'
AS $procedure$
DECLARE
    v_unit_count bigint;
    v_current int;
    v_desired int;
BEGIN
    SELECT report_partition_modulus INTO v_current FROM public.settings;
    SELECT count(*) INTO v_unit_count FROM public.statistical_unit;

    v_desired := CASE
        WHEN v_unit_count <= 10000 THEN 64
        WHEN v_unit_count <= 100000 THEN 128
        WHEN v_unit_count <= 1000000 THEN 256
        WHEN v_unit_count <= 5000000 THEN 512
        ELSE 1024
    END;

    IF v_desired != v_current THEN
        RAISE LOG 'adjust_report_partition_modulus: % units -> % partitions (was %)',
            v_unit_count, v_desired, v_current;
        UPDATE public.settings SET report_partition_modulus = v_desired;
    END IF;
END;
$procedure$
```

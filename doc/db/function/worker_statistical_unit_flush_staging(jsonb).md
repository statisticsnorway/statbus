```sql
CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    UPDATE worker.pipeline_progress
    SET step = 'statistical_unit_flush_staging', updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    PERFORM worker.notify_pipeline_progress();

    CALL public.statistical_unit_flush_staging();

    UPDATE worker.pipeline_progress
    SET completed = total, updated_at = clock_timestamp()
    WHERE phase = 'is_deriving_statistical_units';
    PERFORM worker.notify_pipeline_progress();
END;
$procedure$
```

```sql
CREATE OR REPLACE FUNCTION public.power_root_queue_derive()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $function$
BEGIN
    -- Only fire for NSO custom_root changes (not algorithm-derived writes).
    IF (TG_OP = 'INSERT' AND NEW.custom_root_legal_unit_id IS NOT NULL) OR
       (TG_OP = 'UPDATE' AND OLD.custom_root_legal_unit_id IS DISTINCT FROM NEW.custom_root_legal_unit_id) THEN
        PERFORM worker.enqueue_derive_statistical_unit(
            p_power_group_id_ranges := int4range(NEW.power_group_id, NEW.power_group_id, '[]')::int4multirange
        );
    END IF;
    RETURN NULL;
END;
$function$
```

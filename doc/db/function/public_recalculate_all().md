```sql
CREATE OR REPLACE FUNCTION public.recalculate_all()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    RETURN worker.enqueue_derive_statistical_unit_all();
END;
$function$
```

```sql
CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM worker.tasks
    WHERE command = 'derive_statistical_unit'
      AND state IN ('pending', 'processing')
    LIMIT 1
  );
$function$
```

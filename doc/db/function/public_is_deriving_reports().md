```sql
CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM worker.tasks
    WHERE command = 'derive_reports'
      AND state IN ('pending', 'processing')
    LIMIT 1
  );
$function$
```

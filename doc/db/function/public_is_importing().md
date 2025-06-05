```sql
CREATE OR REPLACE FUNCTION public.is_importing()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM worker.tasks
    WHERE command = 'import_job_process'
      AND state IN ('pending', 'processing')
    LIMIT 1
  );
$function$
```

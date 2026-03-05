```sql
CREATE OR REPLACE FUNCTION worker.has_pending_children(p_task_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks 
        WHERE parent_id = p_task_id 
          AND state IN ('pending', 'processing', 'waiting')
    );
$function$
```

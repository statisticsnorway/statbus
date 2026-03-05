```sql
CREATE OR REPLACE FUNCTION worker.has_failed_siblings(p_task_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks t
        JOIN worker.tasks self ON self.id = p_task_id
        WHERE t.parent_id = self.parent_id 
          AND t.id != p_task_id
          AND t.state = 'failed'
    );
$function$
```

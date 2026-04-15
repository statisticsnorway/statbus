```sql
CREATE OR REPLACE FUNCTION worker.cascade_fail_descendants(p_parent_id bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    WITH RECURSIVE descendants AS (
        SELECT id FROM worker.tasks
        WHERE parent_id = p_parent_id AND state IN ('interrupted', 'pending', 'waiting')
        UNION ALL
        SELECT t.id FROM worker.tasks AS t
        JOIN descendants AS d ON t.parent_id = d.id
        WHERE t.state IN ('interrupted', 'pending', 'waiting')
    )
    UPDATE worker.tasks
    SET state = 'failed',
        error = 'Parent task failed',
        completed_at = clock_timestamp()
    WHERE id IN (SELECT id FROM descendants);
END;
$function$
```

```sql
CREATE OR REPLACE FUNCTION worker.seed_recurring_tasks()
 RETURNS TABLE(command text, task_id bigint)
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- A box whose recurring row was destroyed by the old self-scheduling bug
    -- has nothing pending and therefore nothing to trigger recovery — rune has
    -- been in that state since May. Seeding at startup is what brings such a
    -- box back without an operator knowing to intervene.
    --
    -- Only rows that were actually ABSENT come back (ensure_recurring_task
    -- returns NULL when one was already pending), so the caller can report what
    -- it repaired instead of announcing work it did not do.
    RETURN QUERY
    SELECT cr.command,
           worker.ensure_recurring_task(cr.command, NULL)
    FROM worker.command_registry AS cr
    WHERE cr.schedule_interval IS NOT NULL;
END;
$function$
```

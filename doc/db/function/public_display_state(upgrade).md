```sql
CREATE OR REPLACE FUNCTION public.display_state(u upgrade)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE u.state
        WHEN 'available'   THEN 'Available'
        WHEN 'scheduled'   THEN 'Scheduled'
        WHEN 'in_progress' THEN 'In Progress'
        WHEN 'completed'   THEN 'Completed'
        WHEN 'failed'      THEN 'Failed'
        WHEN 'rolled_back' THEN 'Rolled Back'
        WHEN 'dismissed'   THEN 'Dismissed'
        WHEN 'skipped'     THEN 'Skipped'
        WHEN 'superseded'  THEN 'Superseded'
    END;
$function$
```

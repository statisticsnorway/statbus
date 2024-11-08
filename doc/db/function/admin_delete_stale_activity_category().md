```sql
CREATE OR REPLACE FUNCTION admin.delete_stale_activity_category()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- All the `standard_id` with a recent update must be complete.
    WITH changed_activity_category AS (
      SELECT DISTINCT standard_id
      FROM public.activity_category
      WHERE updated_at = statement_timestamp()
    )
    -- Delete activities that have a stale updated_at
    DELETE FROM public.activity_category
    WHERE standard_id IN (SELECT standard_id FROM changed_activity_category)
    AND updated_at < statement_timestamp();
    RETURN NULL;
END;
$function$
```

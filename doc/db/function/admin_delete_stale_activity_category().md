```sql
CREATE OR REPLACE FUNCTION admin.delete_stale_activity_category()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- A load through a standard view is the complete standard: the system
    -- codes of that standard the statement did NOT address are stale.
    -- admin.upsert_activity_category recorded every addressed code; a
    -- statement that addressed none (empty load) deletes nothing. Custom
    -- overrides are never stale here, they are not part of the standard.
    IF to_regclass('pg_temp.activity_category_addressed') IS NULL THEN
        RETURN NULL;
    END IF;

    DELETE FROM public.activity_category AS ac
    WHERE ac.standard_id IN (SELECT DISTINCT standard_id FROM pg_temp.activity_category_addressed)
      AND NOT ac.custom
      AND NOT EXISTS (
          SELECT 1 FROM pg_temp.activity_category_addressed AS addressed
           WHERE addressed.standard_id = ac.standard_id
             AND addressed.path OPERATOR(public.=) ac.path);

    DROP TABLE pg_temp.activity_category_addressed;
    RETURN NULL;
END;
$function$
```

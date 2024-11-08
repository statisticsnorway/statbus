```sql
CREATE OR REPLACE FUNCTION admin.prepare_foreign_participation_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Deactivate all non-custom entries before insertion
    UPDATE public.foreign_participation
       SET active = false
     WHERE active = true
       AND custom = false;

    RETURN NULL;
END;
$function$
```

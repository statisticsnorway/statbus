```sql
CREATE OR REPLACE FUNCTION admin.prepare_sector_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Deactivate all non-custom entries before insertion
    UPDATE public.sector
       SET enabled = false
     WHERE enabled = true
       AND custom = false;

    RETURN NULL;
END;
$function$
```

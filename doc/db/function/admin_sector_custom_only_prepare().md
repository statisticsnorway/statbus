```sql
CREATE OR REPLACE FUNCTION admin.sector_custom_only_prepare()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Deactivate all non-custom sector entries before insertion
    UPDATE public.sector
       SET enabled = false
     WHERE enabled = true
       AND custom = false;
    RETURN NEW;
END;
$function$
```

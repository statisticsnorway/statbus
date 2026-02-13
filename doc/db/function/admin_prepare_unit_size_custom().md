```sql
CREATE OR REPLACE FUNCTION admin.prepare_unit_size_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Deactivate all non-custom entries before insertion
    UPDATE public.unit_size
       SET enabled = false
     WHERE enabled = true
       AND custom = false;

    RETURN NULL;
END;
$function$
```

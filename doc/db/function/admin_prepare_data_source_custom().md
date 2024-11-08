```sql
CREATE OR REPLACE FUNCTION admin.prepare_data_source_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Deactivate all non-custom entries before insertion
    UPDATE public.data_source
       SET active = false
     WHERE active = true
       AND custom = false;

    RETURN NULL;
END;
$function$
```

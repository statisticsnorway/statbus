```sql
CREATE OR REPLACE FUNCTION admin.prepare_enterprise_group_type_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Deactivate all non-custom entries before insertion
    UPDATE public.enterprise_group_type
       SET active = false
     WHERE active = true
       AND custom = false;

    RETURN NULL;
END;
$function$
```

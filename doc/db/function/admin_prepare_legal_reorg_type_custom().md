```sql
CREATE OR REPLACE FUNCTION admin.prepare_legal_reorg_type_custom()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Deactivate all non-custom entries before insertion
    UPDATE public.legal_reorg_type
       SET enabled = false
     WHERE enabled = true
       AND custom = false;

    RETURN NULL;
END;
$function$
```

```sql
CREATE OR REPLACE FUNCTION admin.legal_form_custom_only_prepare()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Deactivate all non-custom legal_form entries before insertion
    UPDATE public.legal_form
       SET active = false
     WHERE active = true
       AND custom = false;
    RETURN NEW;
END;
$function$
```

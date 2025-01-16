```sql
CREATE OR REPLACE FUNCTION public.external_ident_type_derive_code_and_name_from_by_tag_id()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.by_tag_id IS NOT NULL THEN
        SELECT tag.path, tag.name INTO NEW.code, NEW.name
        FROM public.tag
        WHERE tag.id = NEW.by_tag_id;
    END IF;
    RETURN NEW;
END;
$function$
```

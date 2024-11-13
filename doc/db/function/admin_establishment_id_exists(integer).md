```sql
CREATE OR REPLACE FUNCTION admin.establishment_id_exists(fk_id integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE STRICT
AS $function$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.establishment WHERE id = fk_id);
$function$
```

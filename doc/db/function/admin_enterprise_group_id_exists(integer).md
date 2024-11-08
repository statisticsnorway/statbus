```sql
CREATE OR REPLACE FUNCTION admin.enterprise_group_id_exists(fk_id integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE STRICT
AS $function$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.enterprise_group WHERE id = fk_id);
$function$
```

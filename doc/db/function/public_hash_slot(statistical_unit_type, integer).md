```sql
CREATE OR REPLACE FUNCTION public.hash_slot(p_unit_type statistical_unit_type, p_unit_id integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT abs(hashtext(p_unit_type::text || ':' || p_unit_id::text)) % 16384;
$function$
```

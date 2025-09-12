```sql
CREATE OR REPLACE FUNCTION public.from_until_overlaps(from1 anyelement, until1 anyelement, from2 anyelement, until2 anyelement)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE COST 1
AS $function$
    -- This function implements range overlap check for any comparable type
    -- with the range semantics: from <= time < until
    -- The formula (from1 < until2 AND from2 < until1) checks if two half-open ranges overlap
    SELECT from1 < until2 AND from2 < until1;
$function$
```

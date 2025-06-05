```sql
CREATE OR REPLACE FUNCTION public.after_to_overlaps(after1 anyelement, to1 anyelement, after2 anyelement, to2 anyelement)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE COST 1
AS $function$
    -- This function implements range overlap check for any comparable type
    -- with the range semantics: after < time <= to
    -- The formula (after1 < to2 AND after2 < to1) checks if two half-open ranges overlap
    SELECT after1 < to2 AND after2 < to1;
$function$
```

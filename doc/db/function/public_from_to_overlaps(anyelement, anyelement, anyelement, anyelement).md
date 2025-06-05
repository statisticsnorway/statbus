```sql
CREATE OR REPLACE FUNCTION public.from_to_overlaps(start1 anyelement, end1 anyelement, start2 anyelement, end2 anyelement)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE COST 1
AS $function$
    -- This function implements range overlap check for any comparable type
    -- The formula (start1 <= end2 AND start2 <= end1) is the standard way to check
    -- if two ranges overlap, and it already handles inclusive endpoints correctly
    -- 
    -- This can replace the && operator for ranges when working with primitive types
    -- For example, instead of: daterange('2024-01-01', '2024-12-31') && daterange('2024-12-31', '2025-12-31')
    -- You can use: from_to_overlaps('2024-01-01'::date, '2024-12-31'::date, '2024-12-31'::date, '2025-12-31'::date)
    SELECT start1 <= end2 AND start2 <= end1;
$function$
```

```sql
CREATE OR REPLACE FUNCTION public.partition_count_target_for(p_unit_count bigint)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT CASE
        WHEN p_unit_count <=      100 THEN     4
        WHEN p_unit_count <=   10000 THEN    16
        WHEN p_unit_count <=  100000 THEN    64
        WHEN p_unit_count <= 1000000 THEN   128
        WHEN p_unit_count <= 5000000 THEN   256
        ELSE                                 512
    END
$function$
```

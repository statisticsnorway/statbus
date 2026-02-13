```sql
CREATE OR REPLACE FUNCTION public.report_partition_seq(p_unit_type statistical_unit_type, p_unit_id integer, p_num_partitions integer DEFAULT 128)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT abs(hashtext(p_unit_type::text || ':' || p_unit_id::text)) % p_num_partitions;
$function$
```

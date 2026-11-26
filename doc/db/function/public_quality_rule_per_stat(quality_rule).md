```sql
CREATE OR REPLACE FUNCTION public.quality_rule_per_stat(rule quality_rule)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT rule IN ('establishments_above_legal_unit', 'legal_unit_above_establishments')
$function$
```

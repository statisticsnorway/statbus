```sql
CREATE OR REPLACE FUNCTION public.quality_rule_kind(rule quality_rule)
 RETURNS quality_check_kind
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT CASE WHEN rule IN ('establishment_activity_differs', 'establishments_above_legal_unit', 'legal_unit_above_establishments')
                THEN 'relation'::public.quality_check_kind
                ELSE 'row'::public.quality_check_kind
           END
$function$
```

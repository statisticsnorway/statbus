```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_hierarchy(unit_type statistical_unit_type, unit_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE, strip_nulls boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  WITH result AS (
    SELECT public.enterprise_hierarchy(
      public.statistical_unit_enterprise_id(unit_type, unit_id, valid_on)
      , scope, valid_on
    ) AS data
  )
  SELECT
    CASE
      WHEN strip_nulls THEN jsonb_strip_nulls(result.data)
      ELSE result.data
    END
   FROM result
  ;
$function$
```

```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_tree(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT public.statistical_unit_hierarchy(unit_type, unit_id, 'tree'::public.hierarchy_scope, valid_on);
$function$
```

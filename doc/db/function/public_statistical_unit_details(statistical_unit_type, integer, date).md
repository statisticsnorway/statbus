```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_details(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE
        WHEN unit_type = 'enterprise' THEN public.enterprise_hierarchy(unit_id, 'details', valid_on)
        WHEN unit_type = 'legal_unit' THEN public.legal_unit_hierarchy(unit_id, NULL, 'details', valid_on)
        WHEN unit_type = 'establishment' THEN public.establishment_hierarchy(unit_id, NULL, NULL, 'details', valid_on)
        ELSE '{}'::JSONB
    END;
$function$
```

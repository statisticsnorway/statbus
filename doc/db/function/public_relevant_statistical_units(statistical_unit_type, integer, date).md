```sql
CREATE OR REPLACE FUNCTION public.relevant_statistical_units(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS SETOF statistical_unit
 LANGUAGE sql
 STABLE
AS $function$
    WITH valid_units AS (
        SELECT * FROM public.statistical_unit
        WHERE valid_after < $3 AND $3 <= valid_to
    ), root_unit AS (
        SELECT * FROM valid_units
        WHERE unit_type = 'enterprise'
          AND unit_id = public.statistical_unit_enterprise_id($1, $2, $3)
    ), related_units AS (
        SELECT * FROM valid_units
        WHERE unit_type = 'legal_unit'
          AND unit_id IN (SELECT unnest(legal_unit_ids) FROM root_unit)
            UNION ALL
        SELECT * FROM valid_units
        WHERE unit_type = 'establishment'
          AND unit_id IN (SELECT unnest(establishment_ids) FROM root_unit)
    ), relevant_units AS (
        SELECT * FROM root_unit
            UNION ALL
        SELECT * FROM related_units
    )
    SELECT * FROM relevant_units;
$function$
```

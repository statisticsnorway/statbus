```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_stats(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS SETOF statistical_unit_stats
 LANGUAGE sql
 STABLE
AS $function$
    WITH root_unit AS (
        SELECT su.unit_id,
               su.related_legal_unit_ids,
               su.related_establishment_ids
        FROM public.statistical_unit AS su
        WHERE su.unit_type = 'enterprise'
          AND su.unit_id = public.statistical_unit_enterprise_id($1, $2, $3)
          AND su.valid_from <= $3 AND $3 < su.valid_until
    ), relevant_ids AS (
        SELECT 'enterprise'::statistical_unit_type AS unit_type, ru.unit_id FROM root_unit AS ru
        UNION ALL
        SELECT 'legal_unit'::statistical_unit_type, unnest(ru.related_legal_unit_ids) FROM root_unit AS ru
        UNION ALL
        SELECT 'establishment'::statistical_unit_type, unnest(ru.related_establishment_ids) FROM root_unit AS ru
    )
    SELECT su.unit_type, su.unit_id, su.valid_from, su.valid_to, su.stats, su.stats_summary
    FROM relevant_ids AS ri
    JOIN public.statistical_unit AS su
      ON su.unit_type = ri.unit_type
     AND su.unit_id = ri.unit_id
     AND su.valid_from <= $3 AND $3 < su.valid_until
    ORDER BY su.unit_type, su.unit_id;
$function$
```

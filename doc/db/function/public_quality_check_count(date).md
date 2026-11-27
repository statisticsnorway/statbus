```sql
CREATE OR REPLACE FUNCTION public.quality_check_count(valid_on date)
 RETURNS TABLE(check_id integer, units bigint)
 LANGUAGE sql
 STABLE
AS $function$
    -- Row checks: one grouped count over the rows that have a check (the partial covering index
    -- idx_statistical_unit_quality_check_count), split per id afterwards.
    WITH by_array AS (
        SELECT su.quality_check_ids, count(*) AS units
        FROM public.statistical_unit AS su
        WHERE su.quality_check_ids <> '{}'
          AND public.existence_from(su) <= quality_check_count.valid_on
          AND quality_check_count.valid_on < public.existence_until(su)
        GROUP BY su.quality_check_ids
    ), counted AS (
        SELECT r.check_id, sum(a.units)::bigint AS units
        FROM by_array AS a CROSS JOIN LATERAL unnest(a.quality_check_ids) AS r(check_id)
        GROUP BY r.check_id
        UNION ALL
        SELECT d.check_id, count(*)
        FROM public.quality_establishment_activity_differs AS d
        WHERE d.existence_from <= quality_check_count.valid_on AND quality_check_count.valid_on < d.existence_until
        GROUP BY d.check_id
        UNION ALL
        SELECT s.check_id, count(*)
        FROM public.quality_legal_unit_establishment_stat AS s
        WHERE s.existence_from <= quality_check_count.valid_on AND quality_check_count.valid_on < s.existence_until
        GROUP BY s.check_id
    )
    SELECT qc.id, COALESCE(c.units, 0)
    FROM public.quality_check AS qc
    LEFT JOIN counted AS c ON c.check_id = qc.id
    WHERE public.in_use(qc)
$function$
```

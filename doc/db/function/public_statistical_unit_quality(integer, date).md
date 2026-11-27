```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_quality(quality_check_id integer, valid_on date)
 RETURNS SETOF statistical_unit
 LANGUAGE sql
 STABLE
AS $function$
    -- A row check: the units whose generated quality_check_ids holds it (GIN, gin__int_ops).
    SELECT su.*
    FROM public.statistical_unit AS su
    WHERE su.quality_check_ids @> ARRAY[statistical_unit_quality.quality_check_id]
      AND public.existence_from(su) <= statistical_unit_quality.valid_on
      AND statistical_unit_quality.valid_on < public.existence_until(su)
      AND EXISTS (SELECT 1 FROM public.quality_check AS qc
                  WHERE qc.id = statistical_unit_quality.quality_check_id AND qc.kind = 'row')
    UNION ALL
    -- A relation check: the legal unit rows its table lists at the instant, then those rows.
    SELECT su.*
    FROM (
        SELECT d.unit_type, d.unit_id, d.valid_range
        FROM public.quality_establishment_activity_differs AS d
        WHERE d.check_id = statistical_unit_quality.quality_check_id
          AND d.existence_from <= statistical_unit_quality.valid_on AND statistical_unit_quality.valid_on < d.existence_until
        UNION ALL
        SELECT s.unit_type, s.unit_id, s.valid_range
        FROM public.quality_legal_unit_establishment_stat AS s
        JOIN public.quality_check AS qc ON qc.id = s.check_id AND public.in_use(qc)
        WHERE s.check_id = statistical_unit_quality.quality_check_id
          AND s.existence_from <= statistical_unit_quality.valid_on AND statistical_unit_quality.valid_on < s.existence_until
    ) AS f
    JOIN public.statistical_unit AS su
      ON su.unit_type = f.unit_type AND su.unit_id = f.unit_id AND su.valid_range = f.valid_range
$function$
```

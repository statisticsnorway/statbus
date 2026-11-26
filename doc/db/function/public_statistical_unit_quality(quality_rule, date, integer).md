```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_quality(quality_rule quality_rule, valid_on date, quality_stat_definition_id integer DEFAULT NULL::integer)
 RETURNS SETOF statistical_unit
 LANGUAGE sql
 STABLE
AS $function$
    SELECT su.*
    FROM public.statistical_unit AS su
    WHERE public.existence_from(su) <= statistical_unit_quality.valid_on
      AND statistical_unit_quality.valid_on < public.existence_until(su)
      AND EXISTS (
          SELECT 1 FROM public.quality_finding AS f
          WHERE f.rule = statistical_unit_quality.quality_rule
            AND COALESCE(f.stat_definition_id, 0) = COALESCE(statistical_unit_quality.quality_stat_definition_id, 0)
            AND f.existence_from <= statistical_unit_quality.valid_on
            AND statistical_unit_quality.valid_on < f.existence_until
            AND f.unit_type = su.unit_type
            AND f.unit_id = su.unit_id
            AND f.valid_range = su.valid_range)
$function$
```

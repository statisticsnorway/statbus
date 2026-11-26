```sql
CREATE OR REPLACE FUNCTION public.quality_finding_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running quality_finding_derive()';
    MERGE INTO public.quality_finding AS target
    USING (
        SELECT d.rule, d.stat_definition_id, d.unit_type, d.unit_id, d.valid_from, d.valid_until, d.detail,
               public.unit_existence_from(su.valid_from, su.birth_date) AS existence_from,
               public.unit_existence_until(su.valid_until, su.death_date) AS existence_until
        FROM public.quality_finding_def AS d
        JOIN public.statistical_unit AS su
          ON su.unit_type = d.unit_type AND su.unit_id = d.unit_id AND su.valid_from = d.valid_from
    ) AS source
    ON target.rule = source.rule
   AND COALESCE(target.stat_definition_id, 0) = COALESCE(source.stat_definition_id, 0)
   AND target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND (target.detail IS DISTINCT FROM source.detail
                      OR target.existence_from IS DISTINCT FROM source.existence_from
                      OR target.existence_until IS DISTINCT FROM source.existence_until) THEN
        UPDATE SET detail = source.detail,
                   existence_from = source.existence_from,
                   existence_until = source.existence_until
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (rule, stat_definition_id, unit_type, unit_id, valid_from, valid_until, existence_from, existence_until, detail)
        VALUES (source.rule, source.stat_definition_id, source.unit_type, source.unit_id, source.valid_from,
                source.valid_until, source.existence_from, source.existence_until, source.detail)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_finding;
END;
$function$
```

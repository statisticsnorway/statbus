```sql
CREATE OR REPLACE FUNCTION public.quality_establishments_above_legal_unit_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running quality_establishments_above_legal_unit_derive()';
    MERGE INTO public.quality_establishments_above_legal_unit AS target
    USING public.quality_establishments_above_legal_unit_def AS source
    ON target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND target.stats IS DISTINCT FROM source.stats THEN UPDATE SET stats = source.stats
    WHEN NOT MATCHED BY TARGET THEN INSERT (unit_type, unit_id, valid_from, valid_until, stats)
        VALUES (source.unit_type, source.unit_id, source.valid_from, source.valid_until, source.stats)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_establishments_above_legal_unit;
END;
$function$
```

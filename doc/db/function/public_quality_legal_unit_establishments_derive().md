```sql
CREATE OR REPLACE FUNCTION public.quality_legal_unit_establishments_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running quality_legal_unit_establishments_derive()';
    IF to_regclass('pg_temp.legal_unit_establishment_stat_comparison_now') IS NOT NULL THEN
        DROP TABLE legal_unit_establishment_stat_comparison_now;
    END IF;
    CREATE TEMP TABLE legal_unit_establishment_stat_comparison_now ON COMMIT DROP AS
    SELECT * FROM public.legal_unit_establishment_stat_comparison;

    MERGE INTO public.quality_establishments_above_legal_unit AS target
    USING (
        SELECT c.unit_type, c.unit_id, c.valid_from, c.valid_until,
               jsonb_object_agg(c.stat_code, jsonb_build_object(
                   'legal_unit', c.legal_unit_value,
                   'establishments_sum', c.establishments_sum,
                   'establishments', c.establishment_count)) AS stats
        FROM legal_unit_establishment_stat_comparison_now AS c
        WHERE c.legal_unit_value < c.establishments_sum
        GROUP BY c.unit_type, c.unit_id, c.valid_from, c.valid_until
    ) AS source
    ON target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND target.stats IS DISTINCT FROM source.stats THEN UPDATE SET stats = source.stats
    WHEN NOT MATCHED BY TARGET THEN INSERT (unit_type, unit_id, valid_from, valid_until, stats)
        VALUES (source.unit_type, source.unit_id, source.valid_from, source.valid_until, source.stats)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_establishments_above_legal_unit;

    MERGE INTO public.quality_legal_unit_above_establishments AS target
    USING (
        SELECT c.unit_type, c.unit_id, c.valid_from, c.valid_until,
               jsonb_object_agg(c.stat_code, jsonb_build_object(
                   'legal_unit', c.legal_unit_value,
                   'establishments_sum', c.establishments_sum,
                   'establishments', c.establishment_count)) AS stats
        FROM legal_unit_establishment_stat_comparison_now AS c
        WHERE c.establishments_sum < c.legal_unit_value
          AND c.establishments_with_value = c.establishment_count
        GROUP BY c.unit_type, c.unit_id, c.valid_from, c.valid_until
    ) AS source
    ON target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND target.stats IS DISTINCT FROM source.stats THEN UPDATE SET stats = source.stats
    WHEN NOT MATCHED BY TARGET THEN INSERT (unit_type, unit_id, valid_from, valid_until, stats)
        VALUES (source.unit_type, source.unit_id, source.valid_from, source.valid_until, source.stats)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_legal_unit_above_establishments;
END;
$function$
```

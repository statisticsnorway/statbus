```sql
CREATE OR REPLACE FUNCTION public.quality_establishment_activity_differs_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running quality_establishment_activity_differs_derive()';
    MERGE INTO public.quality_establishment_activity_differs AS target
    USING public.quality_establishment_activity_differs_def AS source
    ON target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND (
        target.legal_unit_activity_category_id IS DISTINCT FROM source.legal_unit_activity_category_id
        OR target.primary_establishment_id IS DISTINCT FROM source.primary_establishment_id
        OR target.primary_establishment_activity_category_id IS DISTINCT FROM source.primary_establishment_activity_category_id
    ) THEN UPDATE SET
        legal_unit_activity_category_id = source.legal_unit_activity_category_id,
        primary_establishment_id = source.primary_establishment_id,
        primary_establishment_activity_category_id = source.primary_establishment_activity_category_id
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (unit_type, unit_id, valid_from, valid_until, legal_unit_activity_category_id,
         primary_establishment_id, primary_establishment_activity_category_id)
        VALUES (source.unit_type, source.unit_id, source.valid_from, source.valid_until,
                source.legal_unit_activity_category_id, source.primary_establishment_id,
                source.primary_establishment_activity_category_id)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_establishment_activity_differs;
END;
$function$
```

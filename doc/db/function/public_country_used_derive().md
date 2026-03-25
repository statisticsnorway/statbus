```sql
CREATE OR REPLACE FUNCTION public.country_used_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running country_used_derive()';
    MERGE INTO public.country_used AS target
    USING public.country_used_def AS source
    ON target.iso_2 = source.iso_2
    WHEN MATCHED AND (
        target.id IS DISTINCT FROM source.id
        OR target.name IS DISTINCT FROM source.name
    ) THEN UPDATE SET
        id = source.id,
        name = source.name
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (id, iso_2, name)
        VALUES (source.id, source.iso_2, source.name)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
END;
$function$
```

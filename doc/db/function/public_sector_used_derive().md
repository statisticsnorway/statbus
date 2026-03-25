```sql
CREATE OR REPLACE FUNCTION public.sector_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    RAISE DEBUG 'Running sector_used_derive()';
    MERGE INTO public.sector_used AS target
    USING public.sector_used_def AS source
    ON target.path = source.path
    WHEN MATCHED AND (
        target.id IS DISTINCT FROM source.id
        OR target.label IS DISTINCT FROM source.label
        OR target.code IS DISTINCT FROM source.code
        OR target.name IS DISTINCT FROM source.name
    ) THEN UPDATE SET
        id = source.id,
        label = source.label,
        code = source.code,
        name = source.name
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (id, path, label, code, name)
        VALUES (source.id, source.path, source.label, source.code, source.name)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
END;
$function$
```

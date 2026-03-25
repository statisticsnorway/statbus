```sql
CREATE OR REPLACE FUNCTION public.data_source_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    RAISE DEBUG 'Running data_source_used_derive()';
    MERGE INTO public.data_source_used AS target
    USING public.data_source_used_def AS source
    ON target.code = source.code
    WHEN MATCHED AND (
        target.id IS DISTINCT FROM source.id
        OR target.name IS DISTINCT FROM source.name
    ) THEN UPDATE SET
        id = source.id,
        name = source.name
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (id, code, name)
        VALUES (source.id, source.code, source.name)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
END;
$function$
```

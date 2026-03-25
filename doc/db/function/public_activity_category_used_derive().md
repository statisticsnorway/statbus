```sql
CREATE OR REPLACE FUNCTION public.activity_category_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    RAISE DEBUG 'Running activity_category_used_derive()';
    MERGE INTO public.activity_category_used AS target
    USING public.activity_category_used_def AS source
    ON target.path = source.path
    WHEN MATCHED AND (
        target.standard_code IS DISTINCT FROM source.standard_code
        OR target.id IS DISTINCT FROM source.id
        OR target.parent_path IS DISTINCT FROM source.parent_path
        OR target.code IS DISTINCT FROM source.code
        OR target.label IS DISTINCT FROM source.label
        OR target.name IS DISTINCT FROM source.name
        OR target.description IS DISTINCT FROM source.description
    ) THEN UPDATE SET
        standard_code = source.standard_code,
        id = source.id,
        parent_path = source.parent_path,
        code = source.code,
        label = source.label,
        name = source.name,
        description = source.description
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (standard_code, id, path, parent_path, code, label, name, description)
        VALUES (source.standard_code, source.id, source.path, source.parent_path,
                source.code, source.label, source.name, source.description)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
END;
$function$
```

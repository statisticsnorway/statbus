```sql
CREATE OR REPLACE FUNCTION public.legal_form_used_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running legal_form_used_derive()';
    MERGE INTO public.legal_form_used AS target
    USING public.legal_form_used_def AS source
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

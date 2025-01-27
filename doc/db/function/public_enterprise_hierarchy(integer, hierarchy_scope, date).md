```sql
CREATE OR REPLACE FUNCTION public.enterprise_hierarchy(enterprise_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH data AS (
        SELECT jsonb_build_object(
                'enterprise',
                 to_jsonb(en.*)
                 || (SELECT public.external_idents_hierarchy(NULL,NULL,en.id,NULL))
                 || CASE WHEN scope IN ('all','tree') THEN (SELECT public.legal_unit_hierarchy(NULL, en.id, scope, valid_on)) ELSE '{}'::JSONB END
                 || CASE WHEN scope IN ('all','tree') THEN (SELECT public.establishment_hierarchy(NULL, NULL, en.id, scope, valid_on)) ELSE '{}'::JSONB END
                 || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(NULL,NULL,en.id,NULL)) ELSE '{}'::JSONB END
                 || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(NULL,NULL,en.id,NULL)) ELSE '{}'::JSONB END
                ) AS data
          FROM public.enterprise AS en
         WHERE enterprise_id IS NOT NULL AND en.id = enterprise_id
         ORDER BY en.short_name
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$function$
```

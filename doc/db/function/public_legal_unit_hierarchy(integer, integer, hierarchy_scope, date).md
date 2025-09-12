```sql
CREATE OR REPLACE FUNCTION public.legal_unit_hierarchy(legal_unit_id integer, parent_enterprise_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  WITH ordered_data AS (
    SELECT to_jsonb(lu.*)
        || (SELECT public.external_idents_hierarchy(NULL,lu.id,NULL,NULL))
        || CASE WHEN scope IN ('all','tree') THEN (SELECT public.establishment_hierarchy(NULL, lu.id, NULL, scope, valid_on)) ELSE '{}'::JSONB END
        || (SELECT public.activity_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.location_hierarchy(NULL,lu.id,valid_on))
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.stat_for_unit_hierarchy(NULL,lu.id,valid_on)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.sector_hierarchy(lu.sector_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.unit_size_hierarchy(lu.unit_size_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.status_hierarchy(lu.status_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.legal_form_hierarchy(lu.legal_form_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.contact_hierarchy(NULL,lu.id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.data_source_hierarchy(lu.data_source_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(NULL,lu.id,NULL,NULL)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(NULL,lu.id,NULL,NULL)) ELSE '{}'::JSONB END
        AS data
    FROM public.legal_unit AS lu
   WHERE (  (legal_unit_id IS NOT NULL AND lu.id = legal_unit_id)
         OR (parent_enterprise_id IS NOT NULL AND lu.enterprise_id = parent_enterprise_id)
         )
     AND lu.valid_from <= valid_on AND valid_on < lu.valid_until
   ORDER BY lu.primary_for_enterprise DESC, lu.name
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('legal_unit',data)
    END
  FROM data_list;
$function$
```

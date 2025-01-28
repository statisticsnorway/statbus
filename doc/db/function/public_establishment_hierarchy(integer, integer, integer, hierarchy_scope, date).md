```sql
CREATE OR REPLACE FUNCTION public.establishment_hierarchy(establishment_id integer, parent_legal_unit_id integer, parent_enterprise_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  WITH ordered_data AS (
    SELECT to_jsonb(es.*)
        || (SELECT public.external_idents_hierarchy(es.id,NULL,NULL,NULL))
        || (SELECT public.activity_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.location_hierarchy(es.id,NULL,valid_on))
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.stat_for_unit_hierarchy(es.id,NULL,valid_on)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.sector_hierarchy(es.sector_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.status_hierarchy(es.status_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.contact_hierarchy(es.id,NULL)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.data_source_hierarchy(es.data_source_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(es.id,NULL,NULL,NULL)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(es.id,NULL,NULL,NULL)) ELSE '{}'::JSONB END
        AS data
    FROM public.establishment AS es
   WHERE (  (establishment_id IS NOT NULL AND es.id = establishment_id)
         OR (parent_legal_unit_id IS NOT NULL AND es.legal_unit_id = parent_legal_unit_id)
         OR (parent_enterprise_id IS NOT NULL AND es.enterprise_id = parent_enterprise_id)
         )
     AND es.valid_after < valid_on AND valid_on <= es.valid_to
   ORDER BY es.primary_for_legal_unit DESC, es.name
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('establishment',data)
    END
  FROM data_list;
$function$
```

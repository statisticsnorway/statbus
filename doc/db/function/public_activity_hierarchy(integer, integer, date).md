```sql
CREATE OR REPLACE FUNCTION public.activity_hierarchy(parent_establishment_id integer DEFAULT NULL::integer, parent_legal_unit_id integer DEFAULT NULL::integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH ordered_data AS (
        SELECT to_jsonb(a.*)
               || (SELECT public.activity_category_hierarchy(a.category_id))
               || (SELECT public.data_source_hierarchy(a.data_source_id))
               AS data
          FROM public.activity AS a
         WHERE a.valid_after < valid_on AND valid_on <= a.valid_to
           AND (  parent_establishment_id IS NOT NULL AND a.establishment_id = parent_establishment_id
               OR parent_legal_unit_id    IS NOT NULL AND a.legal_unit_id    = parent_legal_unit_id
               )
           ORDER BY a.type
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('activity',data)
    END
  FROM data_list;
  ;
$function$
```

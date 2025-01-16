```sql
CREATE OR REPLACE FUNCTION public.tag_for_unit_hierarchy(parent_establishment_id integer DEFAULT NULL::integer, parent_legal_unit_id integer DEFAULT NULL::integer, parent_enterprise_id integer DEFAULT NULL::integer, parent_enterprise_group_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  WITH ordered_data AS (
    SELECT to_jsonb(t.*)
        AS data
      FROM public.tag_for_unit AS tfu
      JOIN public.tag AS t ON tfu.tag_id = t.id
     WHERE (  parent_establishment_id    IS NOT NULL AND tfu.establishment_id    = parent_establishment_id
           OR parent_legal_unit_id       IS NOT NULL AND tfu.legal_unit_id       = parent_legal_unit_id
           OR parent_enterprise_id       IS NOT NULL AND tfu.enterprise_id       = parent_enterprise_id
           OR parent_enterprise_group_id IS NOT NULL AND tfu.enterprise_group_id = parent_enterprise_group_id
           )
       ORDER BY t.path
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('tag',data)
    END
  FROM data_list;
  ;
$function$
```

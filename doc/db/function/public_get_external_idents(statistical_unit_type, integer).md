```sql
CREATE OR REPLACE FUNCTION public.get_external_idents(unit_type statistical_unit_type, unit_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE STRICT
AS $function$
    SELECT jsonb_object_agg(eit.code, ei.ident ORDER BY eit.priority NULLS LAST, eit.code) AS external_idents
    FROM public.external_ident AS ei
    JOIN public.external_ident_type AS eit ON eit.id = ei.type_id
    WHERE
      CASE unit_type
        WHEN 'enterprise' THEN ei.enterprise_id = unit_id
        WHEN 'legal_unit' THEN ei.legal_unit_id = unit_id
        WHEN 'establishment' THEN ei.establishment_id = unit_id
        WHEN 'enterprise_group' THEN ei.enterprise_group_id = unit_id
      END;
$function$
```

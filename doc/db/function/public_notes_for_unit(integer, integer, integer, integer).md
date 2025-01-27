```sql
CREATE OR REPLACE FUNCTION public.notes_for_unit(parent_establishment_id integer, parent_legal_unit_id integer, parent_enterprise_id integer, parent_enterprise_group_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT COALESCE(
    (SELECT jsonb_build_object('notes',to_jsonb(un.*))
     FROM public.unit_notes AS un
     WHERE (  parent_establishment_id    IS NOT NULL AND un.establishment_id    = parent_establishment_id
           OR parent_legal_unit_id       IS NOT NULL AND un.legal_unit_id       = parent_legal_unit_id
           OR parent_enterprise_id       IS NOT NULL AND un.enterprise_id       = parent_enterprise_id
           OR parent_enterprise_group_id IS NOT NULL AND un.enterprise_group_id = parent_enterprise_group_id
           )),
    '{}'::JSONB
  );
$function$
```

```sql
CREATE OR REPLACE FUNCTION public.contact_hierarchy(parent_establishment_id integer, parent_legal_unit_id integer, valid_on date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT COALESCE(
    (SELECT jsonb_build_object('contact',to_jsonb(c.*))
     FROM public.contact AS c
     WHERE (  parent_establishment_id IS NOT NULL AND c.establishment_id = parent_establishment_id
           OR parent_legal_unit_id    IS NOT NULL AND c.legal_unit_id    = parent_legal_unit_id
           ) AND c.valid_from <= valid_on AND valid_on < c.valid_until),
    '{}'::JSONB
  );
$function$
```

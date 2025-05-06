```sql
CREATE OR REPLACE FUNCTION admin.link_steps_to_definition(p_definition_id integer, p_step_codes text[])
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO public.import_definition_step (definition_id, step_id)
    SELECT p_definition_id, s.id
    FROM public.import_step s
    WHERE s.code = ANY(p_step_codes);
END;
$function$
```

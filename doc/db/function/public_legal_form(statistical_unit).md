```sql
CREATE OR REPLACE FUNCTION public.legal_form(statistical_unit statistical_unit)
 RETURNS SETOF legal_form
 LANGUAGE sql
 STABLE ROWS 1
AS $function$
    SELECT lf.*
    FROM public.legal_form lf
    WHERE lf.id = statistical_unit.legal_form_id;
$function$
```

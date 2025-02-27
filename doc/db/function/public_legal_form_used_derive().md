```sql
CREATE OR REPLACE FUNCTION public.legal_form_used_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running legal_form_used_derive()';
    DELETE FROM public.legal_form_used;
    INSERT INTO public.legal_form_used
    SELECT * FROM public.legal_form_used_def;
END;
$function$
```

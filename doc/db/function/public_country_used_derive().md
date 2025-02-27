```sql
CREATE OR REPLACE FUNCTION public.country_used_derive()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE DEBUG 'Running country_used_derive()';
    DELETE FROM public.country_used;
    INSERT INTO public.country_used
    SELECT * FROM public.country_used_def;
END;
$function$
```

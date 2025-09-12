```sql
CREATE OR REPLACE FUNCTION public.region_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    RAISE DEBUG 'Running region_used_derive()';
    DELETE FROM public.region_used;
    INSERT INTO public.region_used
    SELECT * FROM public.region_used_def;
END;
$function$
```

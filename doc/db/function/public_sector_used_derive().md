```sql
CREATE OR REPLACE FUNCTION public.sector_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    RAISE DEBUG 'Running sector_used_derive()';
    TRUNCATE TABLE public.sector_used;
    INSERT INTO public.sector_used
    SELECT * FROM public.sector_used_def;
END;
$function$
```

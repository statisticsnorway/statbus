```sql
CREATE OR REPLACE FUNCTION public.data_source_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    RAISE DEBUG 'Running data_source_used_derive()';
    TRUNCATE TABLE public.data_source_used;
    INSERT INTO public.data_source_used 
    SELECT * FROM public.data_source_used_def;
END;
$function$
```

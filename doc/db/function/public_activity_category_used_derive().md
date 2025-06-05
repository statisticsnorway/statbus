```sql
CREATE OR REPLACE FUNCTION public.activity_category_used_derive()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    RAISE DEBUG 'Running activity_category_used_derive()';
    TRUNCATE TABLE public.activity_category_used;
    INSERT INTO public.activity_category_used
    SELECT * FROM public.activity_category_used_def;
END;
$function$
```

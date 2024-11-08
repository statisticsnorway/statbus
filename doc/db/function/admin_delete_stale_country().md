```sql
CREATE OR REPLACE FUNCTION admin.delete_stale_country()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    DELETE FROM public.country
    WHERE updated_at < statement_timestamp();
    RETURN NULL;
END;
$function$
```

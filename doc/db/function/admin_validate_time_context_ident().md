```sql
CREATE OR REPLACE FUNCTION admin.validate_time_context_ident()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.time_context_ident IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.time_context WHERE ident = NEW.time_context_ident) THEN
        RAISE EXCEPTION 'Invalid time_context_ident: %', NEW.time_context_ident;
    END IF;
    RETURN NEW;
END;
$function$
```

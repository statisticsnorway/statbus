```sql
CREATE OR REPLACE FUNCTION auth.normalize_email()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Normalize email to lowercase for consistent storage and role naming
    IF NEW.email IS NOT NULL THEN
        NEW.email := lower(NEW.email);
    END IF;
    RETURN NEW;
END;
$function$
```

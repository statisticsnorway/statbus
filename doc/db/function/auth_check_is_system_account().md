```sql
CREATE OR REPLACE FUNCTION auth.check_is_system_account()
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = current_user
    AND rolbypassrls = true
  );
END;
$function$
```

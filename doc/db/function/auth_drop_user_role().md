```sql
CREATE OR REPLACE FUNCTION auth.drop_user_role()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Only drop the role if it exists and matches the user's email
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = OLD.email) THEN
    EXECUTE format('DROP ROLE %I', OLD.email);
  END IF;

  RETURN OLD;
END;
$function$
```

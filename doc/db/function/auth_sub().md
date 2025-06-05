```sql
CREATE OR REPLACE FUNCTION auth.sub()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  -- Find the user UUID based on the current database role (email)
  SELECT sub FROM auth.user WHERE email = current_user;
$function$
```

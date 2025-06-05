```sql
CREATE OR REPLACE FUNCTION auth.uid()
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  -- Find the user ID based on the current database role, which should match the email
  SELECT id FROM auth.user WHERE email = current_user;
$function$
```

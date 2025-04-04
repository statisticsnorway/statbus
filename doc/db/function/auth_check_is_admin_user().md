```sql
CREATE OR REPLACE FUNCTION auth.check_is_admin_user()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  SELECT EXISTS (
    SELECT 1 
    FROM auth.user 
    WHERE id = auth.uid()
    AND pg_has_role(email, 'admin_user', 'member')
  );
$function$
```

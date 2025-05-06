```sql
CREATE OR REPLACE FUNCTION auth.statbus_role()
 RETURNS statbus_role
 LANGUAGE sql
 STABLE
AS $function$
  SELECT statbus_role FROM auth.user WHERE email = current_user;
$function$
```

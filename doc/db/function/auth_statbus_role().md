```sql
CREATE OR REPLACE FUNCTION auth.statbus_role()
 RETURNS statbus_role
 LANGUAGE sql
 STABLE
AS $function$
  SELECT (nullif(current_setting('request.jwt.claims', true), '')::json->>'statbus_role')::public.statbus_role;
$function$
```

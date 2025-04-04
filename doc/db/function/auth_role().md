```sql
CREATE OR REPLACE FUNCTION auth.role()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nullif(current_setting('request.jwt.claims', true), '')::json->>'role';
$function$
```

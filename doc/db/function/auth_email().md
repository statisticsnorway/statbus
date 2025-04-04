```sql
CREATE OR REPLACE FUNCTION auth.email()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nullif(current_setting('request.jwt.claims', true), '')::json->>'email';
$function$
```

```sql
CREATE OR REPLACE FUNCTION auth.sub()
 RETURNS uuid
 LANGUAGE sql
AS $function$
  SELECT (nullif(current_setting('request.jwt.claims', true), '')::json->>'sub')::uuid;
$function$
```

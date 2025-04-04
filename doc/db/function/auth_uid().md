```sql
CREATE OR REPLACE FUNCTION auth.uid()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  SELECT id FROM auth.user WHERE sub = auth.sub();
$function$
```

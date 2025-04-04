```sql
CREATE OR REPLACE FUNCTION auth.generate_jwt(claims jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  token text;
BEGIN
  SELECT sign(
    claims::json,
    current_setting('app.settings.jwt_secret')
  ) INTO token;
  
  RETURN token;
END;
$function$
```

```sql
CREATE OR REPLACE FUNCTION auth.generate_jwt(claims jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  token text;
BEGIN
  SELECT public.sign(
    claims::json,
    current_setting('app.settings.jwt_secret')
  ) INTO token;
  
  RETURN token;
END;
$function$
```

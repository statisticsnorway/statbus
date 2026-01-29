```sql
CREATE OR REPLACE FUNCTION auth.generate_jwt(claims jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
BEGIN
  -- Use centralized jwt_secret() function which handles all error checking
  RETURN public.sign(claims::json, auth.jwt_secret());
END;
$function$
```

```sql
CREATE OR REPLACE FUNCTION auth.jwt_secret()
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'auth', 'pg_temp'
AS $function$
DECLARE
  _secret text;
BEGIN
  SELECT value INTO _secret FROM auth.secrets WHERE key = 'jwt_secret';
  
  IF _secret IS NULL THEN
    RAISE EXCEPTION 'JWT secret not found in auth.secrets. Either not loaded yet, or insufficient permissions (must be called from SECURITY DEFINER context).';
  END IF;
  
  RETURN _secret;
END;
$function$
```

```sql
CREATE OR REPLACE FUNCTION auth.extract_access_token_from_cookies()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  cookies json;
BEGIN
  cookies := nullif(current_setting('request.cookies', true), '')::json;
  
  IF cookies IS NULL THEN
    RETURN NULL;
  END IF;
  
  RETURN cookies->>'statbus';
END;
$function$
```

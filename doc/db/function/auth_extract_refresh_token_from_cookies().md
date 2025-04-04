```sql
CREATE OR REPLACE FUNCTION auth.extract_refresh_token_from_cookies()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  cookie_str text;
  cookie_pattern text;
  refresh_token text;
BEGIN
  -- Get cookie string from request headers
  cookie_str := nullif(current_setting('request.headers', true), '')::json->>'cookie';
  
  IF cookie_str IS NULL THEN
    RETURN NULL;
  END IF;
  
  -- Format is: statbus-<slot>-refresh=<token>; other cookies...
  cookie_pattern := 'statbus-' || 
                   coalesce(current_setting('app.settings.deployment_slot_code', true), 'dev') || 
                   '-refresh=([^;]+)';
  
  -- Extract the token using regex
  refresh_token := substring(cookie_str FROM cookie_pattern);
  
  RETURN refresh_token;
END;
$function$
```

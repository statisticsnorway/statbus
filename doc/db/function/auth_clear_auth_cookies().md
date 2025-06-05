```sql
CREATE OR REPLACE FUNCTION auth.clear_auth_cookies()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  current_headers jsonb;
  new_headers jsonb;
BEGIN
  current_headers := coalesce(nullif(current_setting('response.headers', true), '')::jsonb, '[]'::jsonb);
  new_headers := current_headers;
  
  -- Add expired cookies (set to epoch)
  new_headers := new_headers || jsonb_build_array(
    jsonb_build_object(
      'Set-Cookie',
      'statbus=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Strict'
    )
  );
  
  new_headers := new_headers || jsonb_build_array(
    jsonb_build_object(
      'Set-Cookie',
      'statbus-refresh=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Strict'
    )
  );
  
  PERFORM set_config('response.headers', new_headers::text, true);
END;
$function$
```

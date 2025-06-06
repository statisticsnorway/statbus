```sql
CREATE OR REPLACE FUNCTION auth.set_auth_cookies(access_jwt text, refresh_jwt text, access_expires timestamp with time zone, refresh_expires timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  secure boolean;
  current_headers jsonb;
  new_headers jsonb;
BEGIN
  -- Check if the request is using HTTPS by examining the X-Forwarded-Proto header
  IF nullif(current_setting('request.headers', true), '')::json->>'x-forwarded-proto' IS NOT DISTINCT FROM 'https' THEN
    secure := true;
  ELSE
    secure := false;
  END IF;
  
  -- Get current headers and prepare new ones
  current_headers := coalesce(nullif(current_setting('response.headers', true), '')::jsonb, '[]'::jsonb);
  new_headers := current_headers;
  
  -- Add access token cookie
  new_headers := new_headers || jsonb_build_array(
    jsonb_build_object(
      'Set-Cookie',
      format(
        'statbus=%s; Path=/; HttpOnly; SameSite=Strict; %sExpires=%s',
        access_jwt,
        CASE WHEN secure THEN 'Secure; ' ELSE '' END,
        to_char(access_expires, 'Dy, DD Mon YYYY HH24:MI:SS') || ' GMT'
      )
    )
  );
  
  -- Add refresh token cookie
  new_headers := new_headers || jsonb_build_array(
    jsonb_build_object(
      'Set-Cookie',
      format(
        'statbus-refresh=%s; Path=/; HttpOnly; SameSite=Strict; %sExpires=%s',
        refresh_jwt,
        CASE WHEN secure THEN 'Secure; ' ELSE '' END,
        to_char(refresh_expires, 'Dy, DD Mon YYYY HH24:MI:SS') || ' GMT'
      )
    )
  );
  
  -- Set the headers in the response
  PERFORM set_config('response.headers', new_headers::text, true);
END;
$function$
```

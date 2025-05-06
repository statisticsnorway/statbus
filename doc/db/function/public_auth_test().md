```sql
CREATE OR REPLACE FUNCTION public.auth_test()
 RETURNS auth.auth_test_response
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  headers json;
  cookies json;
  claims json;
  access_token text;
  refresh_token text;
  access_claims json := NULL;
  refresh_claims json := NULL;
  jwt_secret text;
  result auth.auth_test_response;
  access_token_info auth.token_info;
  refresh_token_info auth.token_info;
BEGIN
  -- Get headers, cookies, and claims from the current request
  headers := nullif(current_setting('request.headers', true), '')::json;
  cookies := nullif(current_setting('request.cookies', true), '')::json;
  claims := nullif(current_setting('request.jwt.claims', true), '')::json;
  
  -- Get tokens from cookies
  access_token := cookies->>'statbus';
  refresh_token := cookies->>'statbus-refresh';
  jwt_secret := current_setting('app.settings.jwt_secret', true);
  
  -- Validate and decode access token if present
  IF access_token IS NOT NULL THEN
    BEGIN
      SELECT payload::json INTO access_claims 
      FROM verify(access_token, jwt_secret);
    EXCEPTION WHEN OTHERS THEN
      access_claims := json_build_object('error', 'Invalid access token: ' || SQLERRM);
    END;
  END IF;
  
  -- Validate and decode refresh token if present
  IF refresh_token IS NOT NULL THEN
    BEGIN
      SELECT payload::json INTO refresh_claims 
      FROM verify(refresh_token, jwt_secret);
    EXCEPTION WHEN OTHERS THEN
      refresh_claims := json_build_object('error', 'Invalid refresh token: ' || SQLERRM);
    END;
  END IF;
  
  -- Build access token info
  IF access_token IS NOT NULL THEN
    access_token_info.present := TRUE;
    access_token_info.token_length := length(access_token);
    access_token_info.claims := access_claims;
    access_token_info.valid := access_claims IS NOT NULL AND NOT (access_claims::jsonb ? 'error');
    
    IF access_claims IS NULL OR access_claims::jsonb ? 'error' THEN
      access_token_info.expired := NULL;
    ELSIF (access_claims->>'exp')::numeric < extract(epoch from clock_timestamp()) THEN
      access_token_info.expired := TRUE;
    ELSE
      access_token_info.expired := FALSE;
    END IF;
  END IF;
  
  -- Build refresh token info
  IF refresh_token IS NOT NULL THEN
    refresh_token_info.present := TRUE;
    refresh_token_info.token_length := length(refresh_token);
    refresh_token_info.claims := refresh_claims;
    refresh_token_info.valid := refresh_claims IS NOT NULL AND NOT (refresh_claims::jsonb ? 'error');
    
    IF refresh_claims IS NULL OR refresh_claims::jsonb ? 'error' THEN
      refresh_token_info.expired := NULL;
    ELSIF (refresh_claims->>'exp')::numeric < extract(epoch from clock_timestamp()) THEN
      refresh_token_info.expired := TRUE;
    ELSE
      refresh_token_info.expired := FALSE;
    END IF;
    
    refresh_token_info.jti := refresh_claims->>'jti';
    refresh_token_info.version := refresh_claims->>'version';
  END IF;
  
  -- Build result
  result.headers := headers;
  result.cookies := cookies;
  result.claims := claims;
  result.access_token := access_token_info;
  result.refresh_token := refresh_token_info;
  result.timestamp := clock_timestamp();
  result.deployment_slot := coalesce(current_setting('app.settings.deployment_slot_code', true), 'dev');
  result.is_https := headers->>'x-forwarded-proto' = 'https';
  
  RETURN result;
END;
$function$
```

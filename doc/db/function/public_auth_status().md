```sql
CREATE OR REPLACE FUNCTION public.auth_status()
 RETURNS auth.auth_status_response
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  claims json;
  user_sub uuid;
  user_record auth.user;
  is_authenticated boolean := false;
  token_expiring boolean := false;
  current_epoch integer;
  expiration_time integer;
  access_token text;
  refresh_token text;
  jwt_secret text;
  result auth.auth_status_response;
BEGIN
  jwt_secret := current_setting('app.settings.jwt_secret', true);
  
  -- Try to get tokens from cookies
  access_token := auth.extract_access_token_from_cookies();
  refresh_token := auth.extract_refresh_token_from_cookies();
    
  -- First try access token
  IF access_token IS NOT NULL THEN
    BEGIN
      SELECT payload::json INTO claims 
      FROM verify(access_token, jwt_secret);
      
      PERFORM set_config('request.jwt.claims', claims::text, true);
    EXCEPTION WHEN OTHERS THEN
      claims := NULL;
    END;
  END IF;
  
  -- If access token failed, try refresh token
  IF claims IS NULL AND refresh_token IS NOT NULL THEN
    BEGIN
      SELECT payload::json INTO claims 
      FROM verify(refresh_token, jwt_secret);
      
      IF claims->>'type' = 'refresh' THEN
        PERFORM set_config('request.jwt.claims', claims::text, true);
      ELSE
        claims := NULL;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      claims := NULL;
    END;
  END IF;
  
  -- If no claims from cookies, try request context
  IF claims IS NULL THEN
    claims := nullif(current_setting('request.jwt.claims', true), '')::json;
  END IF;
    
  -- Check if we have valid claims
  IF claims IS NULL OR claims->>'sub' IS NULL THEN
    result.is_authenticated := false;
    result.token_expiring := false;
    result.uid := NULL;
    result.sub := NULL;
    result.email := NULL;
    result.role := NULL;
    result.statbus_role := NULL;
    result.last_sign_in_at := NULL;
    result.created_at := NULL;
    RETURN result;
  END IF;
  
  -- Get user from claims
  user_sub := (claims->>'sub')::uuid;
  
  SELECT * INTO user_record
  FROM auth.user
  WHERE sub = user_sub AND deleted_at IS NULL;
  
  IF NOT FOUND THEN
    result.is_authenticated := false;
    result.token_expiring := false;
    result.uid := NULL;
    result.sub := NULL;
    result.email := NULL;
    result.role := NULL;
    result.statbus_role := NULL;
    result.last_sign_in_at := NULL;
    result.created_at := NULL;
    RETURN result;
  END IF;
  
  -- User exists and is authenticated
  is_authenticated := true;
  
  -- Check if token is about to expire (within 5 minutes)
  current_epoch := extract(epoch from clock_timestamp())::integer;
  expiration_time := (claims->>'exp')::integer;
  token_expiring := expiration_time - current_epoch < 300; -- 5 minutes
  
  -- Build result with flattened user info
  result.is_authenticated := is_authenticated;
  result.token_expiring := token_expiring;
  result.uid := user_record.id;
  result.sub := user_record.sub;
  result.email := user_record.email;
  result.role := user_record.email;
  result.statbus_role := user_record.statbus_role;
  result.last_sign_in_at := user_record.last_sign_in_at;
  result.created_at := user_record.created_at;
  
  RETURN result;
END;
$function$
```

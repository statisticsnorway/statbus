```sql
CREATE OR REPLACE FUNCTION public.logout()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  claims json;
  user_sub uuid;
  refresh_session_jti uuid;
  refresh_token text;
BEGIN
  -- Extract the refresh token from the cookie
  refresh_token := auth.extract_refresh_token_from_cookies();
  
  -- If we have a refresh token, use its claims
  IF refresh_token IS NOT NULL THEN
    SELECT payload::json INTO claims 
    FROM verify(refresh_token, current_setting('app.settings.jwt_secret'));
    
    -- If this is a refresh token, get the session ID
    IF claims->>'type' = 'refresh' THEN
      refresh_session_jti := (claims->>'jti')::uuid;
      user_sub := nullif(claims->>'sub', '')::uuid;
      
      -- Delete just this session
      IF refresh_session_jti IS NOT NULL THEN
        DELETE FROM auth.refresh_session
        WHERE jti = refresh_session_jti AND user_id = (SELECT id FROM auth.user WHERE sub = user_sub);
      END IF;
    END IF;
  ELSE
    -- Fall back to current JWT claims if no refresh token
    claims := current_setting('request.jwt.claims', true)::json;
    user_sub := nullif(claims->>'sub', '')::uuid;
    
    -- For access tokens, we can't identify the specific session
    IF user_sub IS NOT NULL THEN
      -- Delete all sessions for this user (aggressive but secure)
      DELETE FROM auth.refresh_session
      WHERE user_id = (SELECT id FROM auth.user WHERE sub = user_sub);
    END IF;
  END IF;

  -- Set cookies in response headers to clear them
  PERFORM auth.clear_auth_cookies();

  -- Return success
  RETURN json_build_object('success', true);
END;
$function$
```

```sql
CREATE OR REPLACE FUNCTION public.logout()
 RETURNS auth.auth_response
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  claims json;
  user_sub uuid;
  refresh_session_jti uuid;
  refresh_token text;
  result auth.logout_response;
BEGIN
  -- Extract the refresh token from the cookie
  refresh_token := auth.extract_refresh_token_from_cookies();
  
  -- If we have a refresh token, use its claims
  IF refresh_token IS NOT NULL THEN
    -- Try to verify the token, but logout should work even if verification fails
    -- This is a non-critical path for cleanup purposes
    BEGIN
      SELECT payload::json INTO claims 
      FROM verify(refresh_token, auth.jwt_secret());
    EXCEPTION WHEN OTHERS THEN
      -- Ignore errors, proceed with logout anyway
      NULL;
    END;
    
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
  END IF;

  -- Set cookies in response headers to clear them
  PERFORM auth.clear_auth_cookies();

  -- Reset session context and return the "not authenticated" status
  PERFORM auth.reset_session_context();
  RETURN auth.build_auth_response();
END;
$function$
```

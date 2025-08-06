```sql
CREATE OR REPLACE FUNCTION public.auth_status()
 RETURNS auth.auth_response
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  access_token_value text;
  access_verification_result auth.jwt_verification_result;
  user_record auth.user;
BEGIN
  RAISE DEBUG '[auth_status] Starting. This function can only see the statbus (access) cookie.';
  
  -- Try to get the access token from cookies. The refresh token is not available on this path.
  access_token_value := auth.extract_access_token_from_cookies();
  
  -- Case 1: No access token cookie. The user is unauthenticated.
  IF access_token_value IS NULL THEN
    RAISE DEBUG '[auth_status] No access token cookie found. Unauthenticated.';
    RETURN auth.build_auth_response(); -- is_authenticated=false, expired_access_token_call_refresh=false
  END IF;

  -- Case 2: Access token cookie is present. Verify it.
  access_verification_result := auth.verify_jwt_with_secret(access_token_value);

  -- Case 2a: Token is valid and NOT expired. User is authenticated.
  IF access_verification_result.is_valid AND NOT access_verification_result.expired THEN
    RAISE DEBUG '[auth_status] Access token is valid and not expired.';
    SELECT * INTO user_record
    FROM auth.user
    WHERE sub = (access_verification_result.claims->>'sub')::uuid AND deleted_at IS NULL;
    
    IF FOUND THEN
      RAISE DEBUG '[auth_status] User found. Authenticated.';
      RETURN auth.build_auth_response(p_user_record => user_record);
    ELSE
      RAISE DEBUG '[auth_status] User from valid token not found in DB. Unauthenticated.';
      -- This is an anomaly (e.g., user deleted after token was issued).
      -- Clear cookies to be safe and force a new login.
      PERFORM auth.clear_auth_cookies();
      RETURN auth.build_auth_response();
    END IF;
  END IF;

  -- Case 2b: Token signature is valid, but the token is EXPIRED.
  -- This is the signal for the client to attempt a refresh.
  IF access_verification_result.is_valid AND access_verification_result.expired THEN
    RAISE DEBUG '[auth_status] Access token is expired but signature is valid. Client should refresh.';
    RETURN auth.build_auth_response(p_expired_access_token_call_refresh => true);
  END IF;

  -- Case 3: Token is invalid (e.g., bad signature). The user is unauthenticated.
  -- This covers `NOT access_verification_result.is_valid`.
  RAISE DEBUG '[auth_status] Access token is invalid (e.g., bad signature). Unauthenticated.';
  -- We could clear cookies here, but it might be better to let the client decide.
  -- A bad signature could indicate tampering, but also just a key rotation.
  -- For now, just return unauthenticated status.
  RETURN auth.build_auth_response();
END;
$function$
```

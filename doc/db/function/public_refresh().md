```sql
CREATE OR REPLACE FUNCTION public.refresh()
 RETURNS auth.auth_response
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _user auth.user;
  _session auth.refresh_session;
  claims json;
  token_version integer;
  refresh_session_jti uuid;
  current_ip inet;
  current_ua text;
  access_jwt text;
  refresh_jwt text;
  access_expires timestamptz;
  refresh_expires timestamptz;
  new_version integer;
  access_claims jsonb;
  refresh_claims jsonb;
  access_token_value text;
  access_jwt_verify_result auth.jwt_verify_result;
BEGIN
  -- This function is idempotent. Calling it multiple times will result in a new token pair
  -- each time, and the previous refresh token version will be invalidated.
  -- The 'statbus-refresh' cookie is path-scoped to this endpoint, so it's not sent elsewhere.

  -- Extract the refresh token from the cookie and get its claims
  DECLARE
    refresh_token text;
  BEGIN
    -- Get refresh token from cookies
    refresh_token := auth.extract_refresh_token_from_cookies();
    
    IF refresh_token IS NULL THEN
      -- No valid refresh token found in cookies
      PERFORM auth.clear_auth_cookies();
      PERFORM auth.reset_session_context(); -- Ensure context is cleared
      PERFORM set_config('response.status', '401', true);
      RETURN auth.build_auth_response(p_error_code => 'REFRESH_NO_TOKEN_COOKIE'::auth.login_error_code);
    END IF;
    
    -- Decode the JWT to get the claims using centralized jwt_secret() function
    BEGIN
      SELECT payload::json INTO claims
      FROM verify(refresh_token, auth.jwt_secret());
    EXCEPTION WHEN OTHERS THEN
      PERFORM auth.clear_auth_cookies();
      PERFORM auth.reset_session_context();
      PERFORM set_config('response.status', '500', true);
      RAISE;
    END;
  END;
  
  -- Verify this is actually a refresh token
  IF claims->>'type' != 'refresh' THEN
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(p_error_code => 'REFRESH_INVALID_TOKEN_TYPE'::auth.login_error_code);
  END IF;
  
  -- Extract claims
  token_version := (claims->>'version')::integer;
  refresh_session_jti := (claims->>'jti')::uuid;
  
  -- Get current client information safely
  current_ip := auth.get_request_ip();
  current_ua := nullif(current_setting('request.headers', true),'')::json->>'user-agent';
  
  RAISE DEBUG '[public.refresh] current_ua before session update: %', current_ua; -- DEBUG
  
  -- Get the user
  SELECT u.* INTO _user
  FROM auth.user u
  WHERE u.sub = (claims->>'sub')::uuid
    AND u.deleted_at IS NULL;
    
  IF NOT FOUND THEN
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(p_error_code => 'REFRESH_USER_NOT_FOUND_OR_DELETED'::auth.login_error_code);
  END IF;
  
  -- Get the session
  SELECT s.* INTO _session
  FROM auth.refresh_session s
  WHERE s.jti = refresh_session_jti
    AND s.user_id = _user.id
    AND s.refresh_version = token_version;

  IF NOT FOUND THEN
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(p_error_code => 'REFRESH_SESSION_INVALID_OR_SUPERSEDED'::auth.login_error_code);
  END IF;
  
  
  -- Set expiration times, and use clock_timestamp() to have progress within the same transaction when testing.
  access_expires := clock_timestamp() + (coalesce(current_setting('app.settings.access_jwt_exp', true)::int, 3600) || ' seconds')::interval;
  refresh_expires := clock_timestamp() + (coalesce(current_setting('app.settings.refresh_jwt_exp', true)::int, 2592000) || ' seconds')::interval;
  
  -- Update session version and last used time
  UPDATE auth.refresh_session
  SET refresh_version = refresh_version + 1,
      last_used_at = clock_timestamp(),
      expires_at = refresh_expires,
      ip_address = current_ip,  -- Update to current IP
      user_agent = current_ua -- Update user agent
  WHERE id = _session.id
  RETURNING refresh_version INTO new_version;

  -- Generate access token claims using the shared function
  access_claims := auth.build_jwt_claims(
    p_email => _user.email, 
    p_expires_at => access_expires, 
    p_type => 'access'
  );

  -- Generate refresh token claims using the shared function
  refresh_claims := auth.build_jwt_claims(
    p_email => _user.email,
    p_expires_at => refresh_expires,
    p_type => 'refresh',
    p_additional_claims => jsonb_build_object(
      'jti', _session.jti::text,
      'version', new_version,
      'ip', current_ip::text
    )
  );

  -- Sign the tokens
  SELECT auth.generate_jwt(access_claims) INTO access_jwt;
  SELECT auth.generate_jwt(refresh_claims) INTO refresh_jwt;

  -- Set cookies in response headers
  PERFORM auth.set_auth_cookies(
    access_jwt,
    refresh_jwt,
    access_expires,
    refresh_expires
  );

  -- Return the authentication response
  -- Note: We are no longer setting request.jwt.claims here.
  RETURN auth.build_auth_response(p_user_record => _user);
END;
$function$
```

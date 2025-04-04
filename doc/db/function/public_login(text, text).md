```sql
CREATE OR REPLACE FUNCTION public.login(email text, password text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _user auth.user;
  access_jwt text;
  refresh_jwt text;
  access_expires timestamptz;
  refresh_expires timestamptz;
  refresh_session_jti uuid;
  user_ip inet;
  user_agent text;
  ua_hash text;
  access_claims jsonb;
  refresh_claims jsonb;
BEGIN
  -- Find user first
  SELECT u.* INTO _user
  FROM auth.user u
  WHERE (login.email IS NOT NULL AND u.email = login.email)
    AND u.deleted_at IS NULL
    AND u.email_confirmed_at IS NOT NULL;

  -- Set a fallback password hash if user not found to prevent timing attacks
  IF NOT FOUND THEN
    _user.encrypted_password := '$2a$10$0000000000000000000000000000000000000000000000000000';
  END IF;

  -- Reject NULL passwords immediately
  IF login.password IS NULL THEN
    RETURN NULL;
  END IF;

  -- Always verify password to maintain constant-time operation
  IF crypt(login.password, _user.encrypted_password) IS DISTINCT FROM _user.encrypted_password
     OR NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Set expiration times
  access_expires := now() + (coalesce(current_setting('app.settings.access_jwt_exp', true)::int, 3600) || ' seconds')::interval;
  refresh_expires := now() + (coalesce(current_setting('app.settings.refresh_jwt_exp', true)::int, 2592000) || ' seconds')::interval;
  
  -- Get client information
  user_ip := inet(split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1));
  user_agent := current_setting('request.headers', true)::json->>'user-agent';
  ua_hash := encode(digest(user_agent, 'sha256'), 'hex');

  -- Create a new refresh session
  INSERT INTO auth.refresh_session (
    user_id, 
    expires_at,
    user_agent,
    ip_address
  ) VALUES (
    _user.id,
    refresh_expires,
    user_agent,
    user_ip
  ) RETURNING jti INTO refresh_session_jti;

  -- Generate access token claims using the shared function
  access_claims := auth.build_jwt_claims(
    p_email => _user.email,
    p_sub => NULL, 
    p_statbus_role => NULL, 
    p_expires_at => access_expires, 
    p_type => 'access'
  );

  -- Generate refresh token claims using the shared function
  refresh_claims := auth.build_jwt_claims(
    p_email => _user.email,
    p_sub => NULL,
    p_statbus_role => NULL,
    p_expires_at => refresh_expires,
    p_type => 'refresh',
    p_additional_claims => jsonb_build_object(
      'jti', refresh_session_jti::text,
      'version', 0,  -- Initial version for this session
      'ip', user_ip::text,  -- Include IP in token for verification
      'ua_hash', ua_hash  -- Include UA hash for verification
    )
  );

  -- Sign the tokens
  SELECT auth.generate_jwt(access_claims) INTO access_jwt;
  SELECT auth.generate_jwt(refresh_claims) INTO refresh_jwt;

  -- Update last sign in
  UPDATE auth.user
  SET last_sign_in_at = now(),
      updated_at = now()
  WHERE id = _user.id;

  -- Set cookies in response headers
  PERFORM auth.set_auth_cookies(
    access_jwt,
    refresh_jwt,
    access_expires,
    refresh_expires,
    _user.id,
    _user.email
  );

  -- Return tokens in response body
  RETURN auth.build_auth_response(
    access_jwt,
    refresh_jwt,
    _user.id,
    _user.email,
    _user.statbus_role
  );
END;
$function$
```

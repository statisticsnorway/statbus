```sql
CREATE OR REPLACE FUNCTION public.login(email text, password text)
 RETURNS auth.auth_response
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
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
  access_claims jsonb;
  refresh_claims jsonb;
BEGIN
  IF login.password IS NULL THEN
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(p_error_code => 'USER_MISSING_PASSWORD'::auth.login_error_code);
  END IF;

  SELECT u.* INTO _user
  FROM auth.user u
  WHERE u.email = login.email::citext;

  IF NOT FOUND THEN
    IF login.email IS NOT NULL THEN
       PERFORM crypt(login.password, '$2a$10$0000000000000000000000000000000000000000000000000000');
    END IF;
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(p_error_code => 'USER_NOT_FOUND'::auth.login_error_code);
  END IF;

  IF _user.deleted_at IS NOT NULL THEN
    PERFORM crypt(login.password, _user.encrypted_password);
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(p_error_code => 'USER_DELETED'::auth.login_error_code);
  END IF;

  IF _user.email_confirmed_at IS NULL THEN
    PERFORM crypt(login.password, _user.encrypted_password);
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(p_error_code => 'USER_NOT_CONFIRMED_EMAIL'::auth.login_error_code);
  END IF;

  IF crypt(login.password, _user.encrypted_password) IS DISTINCT FROM _user.encrypted_password THEN
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(p_error_code => 'WRONG_PASSWORD'::auth.login_error_code);
  END IF;

  access_expires := clock_timestamp() + (coalesce(nullif(current_setting('app.settings.access_jwt_exp', true),'')::int, 3600) || ' seconds')::interval;
  refresh_expires := clock_timestamp() + (coalesce(nullif(current_setting('app.settings.refresh_jwt_exp', true),'')::int, 2592000) || ' seconds')::interval;

  user_ip := auth.get_request_ip();
  user_agent := nullif(current_setting('request.headers', true),'')::json->>'user-agent';

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

  access_claims := auth.build_jwt_claims(
    p_email => _user.email,
    p_expires_at => access_expires,
    p_type => 'access'
  );

  refresh_claims := auth.build_jwt_claims(
    p_email => _user.email,
    p_expires_at => refresh_expires,
    p_type => 'refresh',
    p_additional_claims => jsonb_build_object(
      'jti', refresh_session_jti::text,
      'version', 0,
      'ip', user_ip::text
    )
  );

  SELECT auth.generate_jwt(access_claims) INTO access_jwt;
  SELECT auth.generate_jwt(refresh_claims) INTO refresh_jwt;

  UPDATE auth.user
  SET last_sign_in_at = clock_timestamp(),
      updated_at = clock_timestamp()
  WHERE id = _user.id;

  PERFORM auth.set_auth_cookies(
    access_jwt => access_jwt,
    refresh_jwt => refresh_jwt,
    access_expires => access_expires,
    refresh_expires => refresh_expires
  );

  RETURN auth.build_auth_response(p_user_record => _user, p_token_expires_at => access_expires);
END;
$function$
```

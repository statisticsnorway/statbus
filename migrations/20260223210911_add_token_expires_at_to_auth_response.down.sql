-- Down Migration 20260223210911: add_token_expires_at_to_auth_response
BEGIN;

-- Restore original refresh function (without token_expires_at)
CREATE OR REPLACE FUNCTION public.refresh()
 RETURNS auth.auth_response
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $refresh$
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
  DECLARE
    refresh_token text;
  BEGIN
    refresh_token := auth.extract_refresh_token_from_cookies();

    IF refresh_token IS NULL THEN
      PERFORM auth.clear_auth_cookies();
      PERFORM auth.reset_session_context();
      PERFORM set_config('response.status', '401', true);
      RETURN auth.build_auth_response(p_error_code => 'REFRESH_NO_TOKEN_COOKIE'::auth.login_error_code);
    END IF;

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

  IF claims->>'type' != 'refresh' THEN
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(p_error_code => 'REFRESH_INVALID_TOKEN_TYPE'::auth.login_error_code);
  END IF;

  token_version := (claims->>'version')::integer;
  refresh_session_jti := (claims->>'jti')::uuid;

  current_ip := auth.get_request_ip();
  current_ua := nullif(current_setting('request.headers', true),'')::json->>'user-agent';

  RAISE DEBUG '[public.refresh] current_ua before session update: %', current_ua;

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


  access_expires := clock_timestamp() + (coalesce(current_setting('app.settings.access_jwt_exp', true)::int, 3600) || ' seconds')::interval;
  refresh_expires := clock_timestamp() + (coalesce(current_setting('app.settings.refresh_jwt_exp', true)::int, 2592000) || ' seconds')::interval;

  UPDATE auth.refresh_session
  SET refresh_version = refresh_version + 1,
      last_used_at = clock_timestamp(),
      expires_at = refresh_expires,
      ip_address = current_ip,
      user_agent = current_ua
  WHERE id = _session.id
  RETURNING refresh_version INTO new_version;

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
      'jti', _session.jti::text,
      'version', new_version,
      'ip', current_ip::text
    )
  );

  SELECT auth.generate_jwt(access_claims) INTO access_jwt;
  SELECT auth.generate_jwt(refresh_claims) INTO refresh_jwt;

  PERFORM auth.set_auth_cookies(
    access_jwt,
    refresh_jwt,
    access_expires,
    refresh_expires
  );

  RETURN auth.build_auth_response(p_user_record => _user);
END;
$refresh$;

-- Restore original login function (without token_expires_at)
CREATE OR REPLACE FUNCTION public.login(email text, password text)
 RETURNS auth.auth_response
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $login$
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

  RETURN auth.build_auth_response(p_user_record => _user);
END;
$login$;

-- Restore original auth_status (without token_expires_at)
CREATE OR REPLACE FUNCTION public.auth_status()
 RETURNS auth.auth_response
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $auth_status$
DECLARE
  access_token_value text;
  access_jwt_verify_result auth.jwt_verify_result;
  user_record auth.user;
BEGIN
  RAISE DEBUG '[auth_status] Starting. This function can only see the statbus (access) cookie.';

  access_token_value := auth.extract_access_token_from_cookies();

  IF access_token_value IS NULL THEN
    RAISE DEBUG '[auth_status] No access token cookie found. Unauthenticated.';
    RETURN auth.build_auth_response();
  END IF;

  access_jwt_verify_result := auth.jwt_verify(access_token_value);

  IF access_jwt_verify_result.is_valid AND NOT access_jwt_verify_result.expired THEN
    RAISE DEBUG '[auth_status] Access token is valid and not expired.';
    SELECT * INTO user_record
    FROM auth.user
    WHERE sub = (access_jwt_verify_result.claims->>'sub')::uuid AND deleted_at IS NULL;

    IF FOUND THEN
      RAISE DEBUG '[auth_status] User found. Authenticated.';
      RETURN auth.build_auth_response(p_user_record => user_record);
    ELSE
      RAISE DEBUG '[auth_status] User from valid token not found in DB. Unauthenticated.';
      PERFORM auth.clear_auth_cookies();
      RETURN auth.build_auth_response();
    END IF;
  END IF;

  IF access_jwt_verify_result.is_valid AND access_jwt_verify_result.expired THEN
    RAISE DEBUG '[auth_status] Access token is expired but signature is valid. Client should refresh.';
    RETURN auth.build_auth_response(p_expired_access_token_call_refresh => true);
  END IF;

  RAISE DEBUG '[auth_status] Access token is invalid (e.g., bad signature). Unauthenticated.';
  RETURN auth.build_auth_response();
END;
$auth_status$;

-- Drop the 4-parameter overload before recreating the original 3-parameter version
DROP FUNCTION auth.build_auth_response(auth."user", boolean, auth.login_error_code, timestamptz);

-- Restore original build_auth_response (without token_expires_at parameter)
CREATE OR REPLACE FUNCTION auth.build_auth_response(p_user_record auth."user" DEFAULT NULL::auth."user", p_expired_access_token_call_refresh boolean DEFAULT false, p_error_code auth.login_error_code DEFAULT NULL::auth.login_error_code)
 RETURNS auth.auth_response
 LANGUAGE plpgsql
AS $build_auth_response$
DECLARE
  result auth.auth_response;
BEGIN
  IF p_user_record IS NULL THEN
    result.is_authenticated := false;
    result.uid := NULL;
    result.sub := NULL;
    result.email := NULL;
    result.display_name := NULL;
    result.role := NULL;
    result.statbus_role := NULL;
    result.last_sign_in_at := NULL;
    result.created_at := NULL;
    result.error_code := p_error_code;
    result.expired_access_token_call_refresh := p_expired_access_token_call_refresh;
  ELSE
    result.is_authenticated := true;
    result.uid := p_user_record.id;
    result.sub := p_user_record.sub;
    result.email := p_user_record.email;
    result.display_name := p_user_record.display_name;
    result.role := p_user_record.email;
    result.statbus_role := p_user_record.statbus_role;
    result.last_sign_in_at := p_user_record.last_sign_in_at;
    result.created_at := p_user_record.created_at;
    result.error_code := NULL;
    result.expired_access_token_call_refresh := p_expired_access_token_call_refresh;
  END IF;
  RETURN result;
END;
$build_auth_response$;

-- Remove token_expires_at from auth.auth_response composite type
ALTER TYPE auth.auth_response DROP ATTRIBUTE token_expires_at;

END;

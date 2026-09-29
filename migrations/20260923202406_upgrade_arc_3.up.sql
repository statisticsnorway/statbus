-- Upgrade-arc healthpark fixture V3 (STATBUS-145 doc-029 Rev 2): THE FIX.
-- Restores auth_status() to its original, shipped body verbatim (doc/db/
-- function/public_auth_status().md). A NEW migration, never an edit to V2 —
-- migration immutability + the release-channel bless-not-rerun semantics
-- (migrate.go:1662-1685) mean an in-place edit to an already-applied
-- version would never actually re-execute.
CREATE OR REPLACE FUNCTION public.auth_status()
 RETURNS auth.auth_response
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  access_token_value text;
  access_jwt_verify_result auth.jwt_verify_result;
  user_record auth.user;
  _token_expires_at timestamptz;
BEGIN
  RAISE DEBUG '[auth_status] Starting. This function can only see the statbus (access) cookie.';

  access_token_value := auth.extract_access_token_from_cookies();

  IF access_token_value IS NULL THEN
    RAISE DEBUG '[auth_status] No access token cookie found. Unauthenticated.';
    RETURN auth.build_auth_response();
  END IF;

  access_jwt_verify_result := auth.jwt_verify(access_token_value);

  -- Extract token expiration from claims
  _token_expires_at := to_timestamp((access_jwt_verify_result.claims->>'exp')::bigint);

  IF access_jwt_verify_result.is_valid AND NOT access_jwt_verify_result.expired THEN
    RAISE DEBUG '[auth_status] Access token is valid and not expired.';
    SELECT * INTO user_record
    FROM auth.user
    WHERE sub = (access_jwt_verify_result.claims->>'sub')::uuid AND deleted_at IS NULL;

    IF FOUND THEN
      RAISE DEBUG '[auth_status] User found. Authenticated.';
      RETURN auth.build_auth_response(p_user_record => user_record, p_token_expires_at => _token_expires_at);
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
$function$;

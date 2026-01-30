-- Migration 20260130093218: add_auth_gate_function
BEGIN;

-- auth_gate: A gating function for Caddy's forward_auth directive
-- Returns 200 OK when authenticated, 401 Unauthorized when not
-- 
-- This function is designed to be called via PostgREST at /rest/rpc/auth_gate
-- by Caddy's forward_auth directive to protect resources like pgAdmin.
--
-- The function checks the JWT cookie and:
-- - If authenticated: returns JSON with user info (200 OK)
-- - If not authenticated: sets response.status to 401 and returns error JSON
--
-- When authenticated, it also returns the user's email in a response header
-- that Caddy can forward to the protected resource.
CREATE OR REPLACE FUNCTION public.auth_gate()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $auth_gate$
DECLARE
  access_token_value text;
  access_jwt_verify_result auth.jwt_verify_result;
  user_record auth.user;
BEGIN
  RAISE DEBUG '[auth_gate] Starting authentication gate check';
  
  -- Try to get the access token from cookies
  access_token_value := auth.extract_access_token_from_cookies();
  
  -- Case 1: No access token cookie
  IF access_token_value IS NULL THEN
    RAISE DEBUG '[auth_gate] No access token cookie found';
    PERFORM set_config('response.status', '401', true);
    RETURN json_build_object(
      'authenticated', false,
      'error', 'Authentication required',
      'code', 'NO_TOKEN'
    );
  END IF;

  -- Case 2: Verify the token
  access_jwt_verify_result := auth.jwt_verify(access_token_value);

  -- Case 2a: Token is valid and NOT expired
  IF access_jwt_verify_result.is_valid AND NOT access_jwt_verify_result.expired THEN
    RAISE DEBUG '[auth_gate] Access token is valid and not expired';
    SELECT * INTO user_record
    FROM auth.user
    WHERE sub = (access_jwt_verify_result.claims->>'sub')::uuid AND deleted_at IS NULL;
    
    IF FOUND THEN
      RAISE DEBUG '[auth_gate] User found: %', user_record.email;
      -- Set response headers with user info for downstream services (e.g., pgAdmin)
      PERFORM set_config('response.headers', 
        format('[{"X-Auth-User": "%s"}, {"X-Auth-Email": "%s"}]', 
          user_record.email, user_record.email), 
        true);
      -- Return success - 200 OK (default status)
      RETURN json_build_object(
        'authenticated', true,
        'email', user_record.email,
        'uid', user_record.id
      );
    ELSE
      RAISE DEBUG '[auth_gate] User from token not found in database';
      PERFORM set_config('response.status', '401', true);
      RETURN json_build_object(
        'authenticated', false,
        'error', 'User not found',
        'code', 'USER_NOT_FOUND'
      );
    END IF;
  END IF;

  -- Case 2b: Token is expired (even if signature is valid)
  IF access_jwt_verify_result.is_valid AND access_jwt_verify_result.expired THEN
    RAISE DEBUG '[auth_gate] Access token is expired';
    PERFORM set_config('response.status', '401', true);
    RETURN json_build_object(
      'authenticated', false,
      'error', 'Token expired - please refresh',
      'code', 'TOKEN_EXPIRED'
    );
  END IF;

  -- Case 3: Token is invalid (bad signature, malformed, etc.)
  RAISE DEBUG '[auth_gate] Access token is invalid';
  PERFORM set_config('response.status', '401', true);
  RETURN json_build_object(
    'authenticated', false,
    'error', 'Invalid authentication token',
    'code', 'INVALID_TOKEN'
  );
END;
$auth_gate$;

COMMENT ON FUNCTION public.auth_gate() IS 
'Authentication gate for Caddy forward_auth. Returns 200 when authenticated, 401 otherwise.
Used to protect resources like pgAdmin with STATBUS authentication.
Returns JSON with authentication status and user info when authenticated.';

-- Grant execute to anon so unauthenticated requests can check their status
-- (they will get 401, but the function needs to be callable)
GRANT EXECUTE ON FUNCTION public.auth_gate() TO anon;
GRANT EXECUTE ON FUNCTION public.auth_gate() TO authenticated;

END;

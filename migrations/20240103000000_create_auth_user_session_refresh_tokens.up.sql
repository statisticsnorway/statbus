-- Migration: Create auth schema tables for user, sessions, and refresh tokens
BEGIN;

-- Create auth schema
CREATE SCHEMA IF NOT EXISTS auth;

-- Create statbus role type for reference
CREATE TYPE public.statbus_role AS ENUM('admin_user','regular_user', 'restricted_user', 'external_user');

-- Create PostgreSQL roles for each statbus role type
DO $$
BEGIN
  -- Create roles if they don't exist
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
    CREATE ROLE admin_user;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'regular_user') THEN
    CREATE ROLE regular_user;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'restricted_user') THEN
    CREATE ROLE restricted_user;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'external_user') THEN
    CREATE ROLE external_user;
  END IF;
  
  -- Set up role hierarchy: admin_user > regular_user > restricted_user > external_user
  GRANT regular_user TO admin_user;
  GRANT restricted_user TO regular_user;
  GRANT external_user TO restricted_user;
END
$$;

-- Create auth tables
CREATE TABLE IF NOT EXISTS auth.user (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sub uuid UNIQUE NOT NULL DEFAULT gen_random_uuid(),
  email text UNIQUE NOT NULL,
  password text,
  encrypted_password text NOT NULL,
  statbus_role public.statbus_role NOT NULL DEFAULT 'regular_user',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_sign_in_at timestamptz,
  email_confirmed_at timestamptz,
  deleted_at timestamptz
);

-- Create a table for refresh sessions
CREATE TABLE IF NOT EXISTS auth.refresh_session (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  jti uuid UNIQUE NOT NULL DEFAULT gen_random_uuid(),
  user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE CASCADE,
  refresh_version integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  user_agent text,
  ip_address inet
);

-- Create indexes for efficient lookups
CREATE INDEX ON auth.refresh_session (user_id);
CREATE INDEX ON auth.refresh_session (expires_at);

-- No replacement - removing the restricted_role table and related functions/triggers

-- Cleanup function for expired sessions
CREATE OR REPLACE FUNCTION auth.cleanup_expired_sessions()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
  DELETE FROM auth.refresh_session WHERE expires_at < now();
$$;

-- Grant permissions
GRANT SELECT ON auth.user TO authenticated;


-- Create a function to create a role for each user
-- This function enables direct database access for users with their application credentials
CREATE OR REPLACE FUNCTION auth.create_user_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  role_name text;
BEGIN
  -- Use the email as the role name for the PostgreSQL role
  -- This allows users to connect to the database using their email as username
  -- When PostgREST receives a JWT with 'role': email, it will execute SET LOCAL ROLE email
  role_name := NEW.email;

  -- Check if role already exists
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
    -- Create the role with INHERIT (default) to ensure permissions flow through
    -- INHERIT is ESSENTIAL for the role hierarchy to work properly
    -- Without INHERIT, users would not get permissions from authenticated or their statbus role
    EXECUTE format('CREATE ROLE %I LOGIN INHERIT', role_name);
    
    -- Grant authenticated role to the user role
    -- This provides the base permissions needed for application functionality
    -- With INHERIT, the user will automatically have all permissions from authenticated
    EXECUTE format('GRANT authenticated TO %I', role_name);
    
    -- Grant the appropriate statbus role to the new role
    -- This determines the user's permission level (admin, regular, restricted, external)
    -- The user inherits all permissions from their statbus_role through role inheritance
    EXECUTE format('GRANT %I TO %I', NEW.statbus_role::text, role_name);
    
    -- Set password for database access if provided
    -- This enables the user to connect directly to the database with the same password
    -- they use for the application
    IF NEW.password IS NOT NULL THEN
      -- Set the encrypted password for application authentication
      NEW.encrypted_password := crypt(NEW.password, gen_salt('bf'));
      
      -- Set the database role password for direct database access
      -- This allows psql and other PostgreSQL clients to connect using this user
      EXECUTE format('ALTER ROLE %I WITH PASSWORD %L', role_name, NEW.password);
      
      -- Clear the plain text password for security
      NEW.password := NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Create a trigger to create a role for each new user
DROP TRIGGER IF EXISTS create_user_role_trigger ON auth.user;
CREATE TRIGGER create_user_role_trigger
BEFORE INSERT ON auth.user
FOR EACH ROW
EXECUTE FUNCTION auth.create_user_role();

-- Create a function to drop user role when user is deleted
CREATE OR REPLACE FUNCTION auth.drop_user_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only drop the role if it exists and matches the user's email
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = OLD.email) THEN
    EXECUTE format('DROP ROLE %I', OLD.email);
  END IF;

  RETURN OLD;
END;
$$;

-- Create a trigger to drop the role when a user is deleted
DROP TRIGGER IF EXISTS drop_user_role_trigger ON auth.user;
CREATE TRIGGER drop_user_role_trigger
AFTER DELETE ON auth.user
FOR EACH ROW
EXECUTE FUNCTION auth.drop_user_role();

-- Create a function to set auth cookies
CREATE OR REPLACE FUNCTION auth.set_auth_cookies(
  access_jwt text,
  refresh_jwt text,
  access_expires timestamptz,
  refresh_expires timestamptz,
  user_id integer,
  user_email text
)
RETURNS void
LANGUAGE plpgsql
AS $set_auth_cookies$
BEGIN
  PERFORM set_config('response.headers',
    json_build_array(
      json_build_object(
        'Set-Cookie',
        format('statbus-%s=%s; Path=/; Expires=%s; HttpOnly; SameSite=Strict',
               current_setting('app.settings.deployment_slot_code', true),
               access_jwt,
               to_char(access_expires at time zone 'GMT', 'Dy, DD Mon YYYY HH24:MI:SS GMT'))
      ),
      json_build_object(
        'Set-Cookie',
        format('statbus-%s-refresh=%s; Path=/; Expires=%s; HttpOnly; SameSite=Strict',
               current_setting('app.settings.deployment_slot_code', true),
               refresh_jwt,
               to_char(refresh_expires at time zone 'GMT', 'Dy, DD Mon YYYY HH24:MI:SS GMT'))
      ),
      json_build_object(
        'App-Auth-Token', access_jwt
      ),
      json_build_object(
        'App-Auth-Role', user_email
      ),
      json_build_object(
        'App-Auth-User', user_id
      )
    )::text,
    true
  );
END;
$set_auth_cookies$;

-- Create a function to clear auth cookies
CREATE OR REPLACE FUNCTION auth.clear_auth_cookies()
RETURNS void
LANGUAGE plpgsql
AS $clear_auth_cookies$
BEGIN
  PERFORM set_config('response.headers',
    json_build_array(
      json_build_object(
        'Set-Cookie',
        format('statbus-%s=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Strict',
               current_setting('app.settings.deployment_slot_code', true))
      ),
      json_build_object(
        'Set-Cookie',
        format('statbus-%s-refresh=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Strict',
               current_setting('app.settings.deployment_slot_code', true))
      )
    )::text,
    true
  );
END;
$clear_auth_cookies$;


-- Create login function that returns JWT token
CREATE OR REPLACE FUNCTION public.login(email text, password text)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
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
$login$;

-- Grant execute to anonymous users only
GRANT EXECUTE ON FUNCTION public.login TO anon;


-- Create refresh function that returns a new JWT token
CREATE OR REPLACE FUNCTION public.refresh()
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
AS $refresh$
DECLARE
  _user auth.user;
  _session auth.refresh_session;
  claims json;
  token_version integer;
  refresh_session_jti uuid;
  current_ip inet;
  current_ua text;
  ua_hash text;
  access_jwt text;
  refresh_jwt text;
  access_expires timestamptz;
  refresh_expires timestamptz;
  new_version integer;
  access_claims jsonb;
  refresh_claims jsonb;
BEGIN
  -- Extract the refresh token from the cookie and get its claims
  DECLARE
    refresh_token text;
  BEGIN
    -- Get refresh token from cookies
    refresh_token := auth.extract_refresh_token_from_cookies();
    
    IF refresh_token IS NULL THEN
      -- No valid refresh token found in cookies
      PERFORM auth.clear_auth_cookies();
      RETURN json_build_object('error', 'No valid refresh token found in cookies');
    END IF;
    
    -- Decode the JWT to get the claims
    SELECT payload::json INTO claims 
    FROM verify(refresh_token, current_setting('app.settings.jwt_secret'));
  END;
  
  -- Verify this is actually a refresh token
  IF claims->>'type' != 'refresh' THEN
    PERFORM auth.clear_auth_cookies();
    RETURN json_build_object('error', 'Invalid token type');
  END IF;
  
  -- Extract claims
  token_version := (claims->>'version')::integer;
  refresh_session_jti := (claims->>'jti')::uuid;
  
  -- Get current client information
  current_ip := inet(split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1));
  current_ua := current_setting('request.headers', true)::json->>'user-agent';
  ua_hash := encode(digest(current_ua, 'sha256'), 'hex');
  
  -- Get the user
  SELECT u.* INTO _user
  FROM auth.user u
  WHERE u.sub = (claims->>'sub')::uuid
    AND u.deleted_at IS NULL;
    
  IF NOT FOUND THEN
    PERFORM auth.clear_auth_cookies();
    RETURN json_build_object('error', 'User not found');
  END IF;
  
  -- Get the session
  SELECT s.* INTO _session
  FROM auth.refresh_session s
  WHERE s.jti = refresh_session_jti
    AND s.user_id = _user.id
    AND s.refresh_version = token_version;

  IF NOT FOUND THEN
    PERFORM auth.clear_auth_cookies();
    RETURN json_build_object('error', 'Invalid session or token has been superseded');
  END IF;
  
  -- Verify user agent (with some flexibility)
  IF claims->>'ua_hash' != ua_hash THEN
    PERFORM auth.clear_auth_cookies();
    RETURN json_build_object('error', 'Session appears to be used from a different browser');
  END IF;
  
  -- Set expiration times, and use clock_timestamp() to have progress within the same transaction when testing.
  access_expires := clock_timestamp() + (coalesce(current_setting('app.settings.access_jwt_exp', true)::int, 3600) || ' seconds')::interval;
  refresh_expires := clock_timestamp() + (coalesce(current_setting('app.settings.refresh_jwt_exp', true)::int, 2592000) || ' seconds')::interval;
  
  -- Update session version and last used time
  UPDATE auth.refresh_session
  SET refresh_version = refresh_version + 1,
      last_used_at = clock_timestamp(),
      expires_at = refresh_expires,
      ip_address = current_ip  -- Update to current IP
  WHERE id = _session.id
  RETURNING refresh_version INTO new_version;

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
      'jti', _session.jti::text,
      'version', new_version,
      'ip', current_ip::text,
      'ua_hash', ua_hash
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
    refresh_expires,
    _user.id,
    _user.email
  );

  -- Return new tokens
  RETURN auth.build_auth_response(
    access_jwt,
    refresh_jwt,
    _user.id,
    _user.email,
    _user.statbus_role
  );
END;
$refresh$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.refresh TO authenticated;


-- Create a logout function
CREATE OR REPLACE FUNCTION public.logout()
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
AS $logout$
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
$logout$;


-- Create function to grant a statbus role to a user
CREATE OR REPLACE FUNCTION public.grant_role(user_sub uuid, new_role public.statbus_role)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $grant_role$
DECLARE
  _user auth.user;
  _is_admin boolean;
BEGIN
  -- Check if current user is admin or superuser
  _is_admin := (current_setting('request.jwt.claims', true)::json->>'statbus_role')::public.statbus_role = 'admin_user' OR 
               (SELECT usesuper FROM pg_user WHERE usename = current_user);
               
  IF NOT _is_admin THEN
    RAISE EXCEPTION 'Only admin users can grant roles';
  END IF;
  
  -- Get the target user
  SELECT * INTO _user FROM auth.user WHERE sub = user_sub;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found';
  END IF;
  
  -- Revoke the old statbus role from the user's role
  EXECUTE format('REVOKE %I FROM %I', _user.statbus_role::text, _user.email);
  
  -- Grant the new statbus role to the user's role
  EXECUTE format('GRANT %I TO %I', new_role::text, _user.email);
  
  -- Update the user record
  UPDATE auth.user SET 
    statbus_role = new_role,
    updated_at = now()
  WHERE sub = user_sub;
  
  RETURN true;
END;
$grant_role$;

-- Create function to revoke a statbus role from a user
CREATE OR REPLACE FUNCTION public.revoke_role(user_sub uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $revoke_role$
DECLARE
  _user auth.user;
  _current_user_role public.statbus_role;
  _is_admin boolean;
BEGIN
  -- Get the current user's role from JWT claims
  _current_user_role := (current_setting('request.jwt.claims', true)::json->>'statbus_role')::public.statbus_role;
  
  -- Check if current user is admin or superuser
  _is_admin := _current_user_role = 'admin_user' OR 
               (SELECT usesuper FROM pg_user WHERE usename = current_user);
               
  IF NOT _is_admin THEN
    RAISE EXCEPTION 'Only admin users can revoke roles';
  END IF;
  
  -- Get the target user
  SELECT * INTO _user FROM auth.user WHERE sub = user_sub;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found';
  END IF;
  
  -- Revoke the current statbus role from the user's role
  EXECUTE format('REVOKE %I FROM %I', _user.statbus_role::text, _user.email);
  
  -- Grant the default role (regular_user) to the user's role
  EXECUTE format('GRANT regular_user TO %I', _user.email);
  
  -- Update the user record
  UPDATE auth.user SET 
    statbus_role = 'regular_user',
    updated_at = now()
  WHERE sub = user_sub;
  
  RETURN true;
END;
$revoke_role$;

-- Function to list a user's active sessions
CREATE OR REPLACE FUNCTION public.list_active_sessions()
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_sub uuid;
BEGIN
  -- Get current user ID from JWT claims
  user_sub := (current_setting('request.jwt.claims', true)::json->>'sub')::uuid;
  
  RETURN QUERY
  SELECT json_build_object(
    'id', s.id,
    'created_at', s.created_at,
    'last_used_at', s.last_used_at,
    'user_agent', s.user_agent,
    'ip_address', s.ip_address,
    'current_session', (current_setting('request.jwt.claims', true)::json->>'jti')::uuid = s.jti
  )
  FROM auth.refresh_session s
  WHERE s.user_id = (SELECT id FROM auth.user WHERE sub = user_sub)
  ORDER BY s.last_used_at DESC;
END;
$$;

-- Function to revoke a specific session
CREATE OR REPLACE FUNCTION public.revoke_session(refresh_session_jti uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_sub uuid;
  affected_rows integer;
BEGIN
  -- Get current user ID from JWT claims
  user_sub := (current_setting('request.jwt.claims', true)::json->>'sub')::uuid;
  
  -- Delete the specified session if it belongs to the current user
  DELETE FROM auth.refresh_session
  WHERE jti = refresh_session_jti AND user_id = (SELECT id FROM auth.user WHERE sub = user_sub);
  
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  
  RETURN affected_rows > 0;
END;
$$;

-- Function to get current user's UUID from JWT
CREATE OR REPLACE FUNCTION auth.sub()
RETURNS UUID
LANGUAGE SQL
AS
$$
  SELECT (nullif(current_setting('request.jwt.claims', true), '')::json->>'sub')::uuid;
$$;

-- Function to get current user's ID (integer) from UUID
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS INTEGER
LANGUAGE SQL
SECURITY DEFINER
AS
$$
  SELECT id FROM auth.user WHERE sub = auth.sub();
$$;

-- Gets the User role from the request JWT
CREATE OR REPLACE FUNCTION auth.role() 
RETURNS text 
LANGUAGE sql 
STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true), '')::json->>'role';
$$ ;

-- Gets the User email from the request JWT
CREATE OR REPLACE FUNCTION auth.email() 
RETURNS text 
LANGUAGE sql 
STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true), '')::json->>'email';
$$ ;

-- Gets the User's statbus_role from the request JWT
CREATE OR REPLACE FUNCTION auth.statbus_role() 
RETURNS public.statbus_role 
LANGUAGE sql 
STABLE
AS $$
  SELECT (nullif(current_setting('request.jwt.claims', true), '')::json->>'statbus_role')::public.statbus_role;
$$ ;


-- Function to get current authentication status
CREATE OR REPLACE FUNCTION public.auth_status()
RETURNS json
LANGUAGE plpgsql
AS $auth_status$
DECLARE
  claims json;
  user_sub uuid;
  user_record auth.user;
  is_authenticated boolean;
  token_expiring boolean;
  current_epoch integer;
  expiration_time integer;
BEGIN
  -- Get current JWT claims
  claims := nullif(current_setting('request.jwt.claims', true), '')::json;
  
  -- Check if we have valid claims
  IF claims IS NULL OR claims->>'sub' IS NULL THEN
    -- No valid claims found
    RETURN json_build_object(
      'isAuthenticated', false,
      'user', null,
      'tokenExpiring', false
    );
  END IF;
  
  -- Extract user ID from claims
  user_sub := (claims->>'sub')::uuid;
  
  -- Get user record
  SELECT * INTO user_record
  FROM auth.user
  WHERE sub = user_sub AND deleted_at IS NULL;
  
  -- Check if user exists
  IF NOT FOUND THEN
    -- User not found or deleted
    RETURN json_build_object(
      'isAuthenticated', false,
      'user', null,
      'tokenExpiring', false
    );
  END IF;
  
  -- Check if token is about to expire (within 5 minutes)
  current_epoch := extract(epoch from clock_timestamp())::integer;
  expiration_time := (claims->>'exp')::integer;
  token_expiring := expiration_time - current_epoch < 300; -- 5 minutes in seconds
  
  -- Return authentication status
  RETURN json_build_object(
    'isAuthenticated', true,
    'tokenExpiring', token_expiring,
    'user', json_build_object(
      'id', user_record.sub,
      'email', user_record.email,
      'role', user_record.email,
      'statbus_role', user_record.statbus_role,
      'last_sign_in_at', user_record.last_sign_in_at,
      'created_at', user_record.created_at
    )
  );
END;
$auth_status$;

-- Grant execute to both anonymous and authenticated users
GRANT EXECUTE ON FUNCTION public.auth_status TO anon, authenticated;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.logout TO authenticated;
GRANT EXECUTE ON FUNCTION public.login TO anon;
GRANT EXECUTE ON FUNCTION public.refresh TO authenticated;
GRANT EXECUTE ON FUNCTION public.grant_role TO admin_user;
GRANT EXECUTE ON FUNCTION public.revoke_role TO admin_user;
GRANT EXECUTE ON FUNCTION public.list_active_sessions TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_session TO authenticated;

-- Grant usage on auth functions to API roles
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.uid TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.role TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.email TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.statbus_role TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.sub TO anon, authenticated;

-- Grant monitoring capabilities to admin role
GRANT pg_monitor TO admin_user;

-- Function to build a JWT claims object for a user
CREATE OR REPLACE FUNCTION auth.build_jwt_claims(
  p_email text,
  p_sub uuid DEFAULT NULL,
  p_statbus_role public.statbus_role DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL,
  p_type text DEFAULT 'access',
  p_additional_claims jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user auth.user;
  v_sub uuid;
  v_statbus_role public.statbus_role;
  v_expires_at timestamptz;
  v_claims jsonb;
BEGIN
  -- Find user if email is provided
  IF p_email IS NOT NULL THEN
    SELECT * INTO v_user
    FROM auth.user
    WHERE email = p_email
      AND deleted_at IS NULL;
      
    IF NOT FOUND THEN
      RAISE EXCEPTION 'User with email % not found', p_email;
    END IF;
    
    v_sub := COALESCE(p_sub, v_user.sub);
    v_statbus_role := COALESCE(p_statbus_role, v_user.statbus_role);
  ELSE
    -- Use provided values directly if no email
    v_sub := p_sub;
    v_statbus_role := p_statbus_role;
    
    IF v_sub IS NULL THEN
      RAISE EXCEPTION 'Either email or sub must be provided';
    END IF;
  END IF;
  
  -- Set expiration time
  v_expires_at := COALESCE(
    p_expires_at,
    clock_timestamp() + (coalesce(current_setting('app.settings.access_jwt_exp', true)::int, 3600) || ' seconds')::interval
  );
  
  -- Build the base claims object with PostgREST compatible structure
  -- role must be the database role name for PostgREST to work correctly
  v_claims := jsonb_build_object(
    'role', p_email,
    'statbus_role', v_statbus_role::text,
    'sub', v_sub::text,
    'email', p_email,
    'type', p_type,
    'iat', extract(epoch from clock_timestamp())::integer,
    'exp', extract(epoch from v_expires_at)::integer
  );
  
  -- Only add JTI if not already in additional claims
  IF NOT p_additional_claims ? 'jti' THEN
    v_claims := v_claims || jsonb_build_object('jti', gen_random_uuid()::text);
  END IF;
  
  -- Merge any additional claims
  v_claims := v_claims || p_additional_claims;
  
  RETURN v_claims;
END;
$$;

-- Function to set the current session context from JWT claims
CREATE OR REPLACE FUNCTION auth.use_jwt_claims_in_session(claims jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Store the full claims object
  PERFORM set_config('request.jwt.claims', claims::text, true);
END;
$$;

-- Create a function to extract refresh token from cookies
CREATE OR REPLACE FUNCTION auth.extract_refresh_token_from_cookies()
RETURNS text
LANGUAGE plpgsql
AS $extract_refresh_token$
DECLARE
  cookie_str text;
  cookie_pattern text;
  refresh_token text;
BEGIN
  -- Get cookie string from request headers
  cookie_str := nullif(current_setting('request.headers', true), '')::json->>'cookie';
  
  IF cookie_str IS NULL THEN
    RETURN NULL;
  END IF;
  
  -- Format is: statbus-<slot>-refresh=<token>; other cookies...
  cookie_pattern := 'statbus-' || 
                   coalesce(current_setting('app.settings.deployment_slot_code', true), 'dev') || 
                   '-refresh=([^;]+)';
  
  -- Extract the token using regex
  refresh_token := substring(cookie_str FROM cookie_pattern);
  
  RETURN refresh_token;
END;
$extract_refresh_token$;

-- Create a function to build a standard auth response object
CREATE OR REPLACE FUNCTION auth.build_auth_response(
  access_jwt text,
  refresh_jwt text,
  user_id integer,
  user_email text,
  user_statbus_role public.statbus_role
)
RETURNS json
LANGUAGE plpgsql
AS $build_auth_response$
BEGIN
  RETURN json_build_object(
    'access_jwt', access_jwt,
    'refresh_jwt', refresh_jwt,
    'user_id', user_id,
    'email', user_email,
    'role', user_email,
    'statbus_role', user_statbus_role
  );
END;
$build_auth_response$;

-- Function to set user context from email
CREATE OR REPLACE FUNCTION auth.set_user_context_from_email(p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_claims jsonb;
BEGIN
  -- Build claims for the user
  v_claims := auth.build_jwt_claims(p_email);
  
  -- Set the claims in the current session
  PERFORM auth.use_jwt_claims_in_session(v_claims);
END;
$$;

-- Function to generate a signed JWT token from claims
CREATE OR REPLACE FUNCTION auth.generate_jwt(claims jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $generate_jwt$
DECLARE
  token text;
BEGIN
  SELECT sign(
    claims::json,
    current_setting('app.settings.jwt_secret')
  ) INTO token;
  
  RETURN token;
END;
$generate_jwt$;

-- Function to reset the session context
CREATE OR REPLACE FUNCTION auth.reset_session_context()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Clear JWT claims
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION auth.build_jwt_claims TO authenticated;
GRANT EXECUTE ON FUNCTION auth.use_jwt_claims_in_session TO authenticated;
GRANT EXECUTE ON FUNCTION auth.set_user_context_from_email TO authenticated;
GRANT EXECUTE ON FUNCTION auth.reset_session_context TO authenticated;
GRANT EXECUTE ON FUNCTION auth.build_auth_response TO authenticated;
GRANT EXECUTE ON FUNCTION auth.set_auth_cookies TO authenticated;
GRANT EXECUTE ON FUNCTION auth.extract_refresh_token_from_cookies TO authenticated;
GRANT EXECUTE ON FUNCTION auth.generate_jwt TO authenticated;

-- Create a scheduled job to clean up expired sessions (if pg_cron is available)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('cleanup-expired-sessions', '0 0 * * *', 'SELECT auth.cleanup_expired_sessions()');
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- pg_cron not available, that's fine
END;
$$;

COMMIT;

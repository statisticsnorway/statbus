-- Migration: Create auth schema tables for user, sessions, and refresh tokens
BEGIN;

-- Create domain for application/json media type if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'application/json') THEN
    CREATE DOMAIN "application/json" AS json;
  END IF;
END$$;

-- Create auth schema
CREATE SCHEMA IF NOT EXISTS auth;

-- Create login error code enum
DROP TYPE IF EXISTS auth.login_error_code CASCADE; -- Drop if exists to recreate with new values
CREATE TYPE auth.login_error_code AS ENUM (
  'USER_NOT_FOUND',
  'USER_NOT_CONFIRMED_EMAIL',
  'USER_DELETED',
  'USER_MISSING_PASSWORD',
  'WRONG_PASSWORD',
  'REFRESH_NO_TOKEN_COOKIE',
  'REFRESH_INVALID_TOKEN_TYPE',
  'REFRESH_USER_NOT_FOUND_OR_DELETED',
  'REFRESH_SESSION_INVALID_OR_SUPERSEDED'
);

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


-- Function to get current user's UUID based on the session role
CREATE OR REPLACE FUNCTION auth.sub()
RETURNS UUID
LANGUAGE SQL STABLE
SECURITY INVOKER
AS
$$
  -- Find the user UUID based on the current database role (email)
  SELECT sub FROM auth.user WHERE email = current_user;
$$;

-- Function to get current user's ID (integer) based on the session role
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS INTEGER
LANGUAGE SQL STABLE -- Ensures it reads the setting for the current query context
SECURITY INVOKER
AS
$$
  -- Find the user ID based on the current database role, which should match the email
  SELECT id FROM auth.user WHERE email = current_user;
$$;

-- Grant execute on helper functions needed by RLS policies and other functions
GRANT EXECUTE ON FUNCTION auth.sub() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, anon;

-- Function to get the client's IP address from request headers
CREATE OR REPLACE FUNCTION auth.get_request_ip()
RETURNS inet
LANGUAGE plpgsql
VOLATILE -- Changed from STABLE to ensure it re-evaluates based on current GUCs
AS $$
DECLARE
  raw_ip_text text;
BEGIN
  -- Extract the first IP from X-Forwarded-For header
  raw_ip_text := split_part(nullif(current_setting('request.headers', true),'')::json->>'x-forwarded-for', ',', 1);
  
  IF raw_ip_text IS NOT NULL AND raw_ip_text != '' THEN
    -- Conditionally strip port:
    -- Only if a colon is present AND the string ends with :digits.
    IF raw_ip_text LIKE '%:%' AND raw_ip_text ~ ':\d+$' THEN
      DECLARE
        temp_ip_after_port_strip text;
      BEGIN
        temp_ip_after_port_strip := regexp_replace(raw_ip_text, ':\d+$', '');
        -- If stripping the port results in just ":" or "" (empty string),
        -- it means the original was likely a short IPv6 like "::1" or an invalid IP.
        -- In this case, don't use the stripped version; let inet() parse the original.
        IF temp_ip_after_port_strip <> ':' AND temp_ip_after_port_strip <> '' THEN
          raw_ip_text := temp_ip_after_port_strip;
        END IF;
      END;
    END IF;
    
    -- Unconditionally strip brackets if present on the (potentially) port-stripped IP.
    -- inet() does not accept brackets around IPv6 addresses.
    IF raw_ip_text ~ '^\[.+\]$' THEN
      raw_ip_text := substring(raw_ip_text from 2 for length(raw_ip_text) - 2);
    END IF;
    
    RETURN inet(raw_ip_text);
  ELSE
    RETURN NULL;
  END IF;
  -- Errors from inet() conversion (e.g., invalid IP format) will propagate.
END;
$$;

GRANT EXECUTE ON FUNCTION auth.get_request_ip() TO authenticated, anon;


-- Create a table for refresh sessions
CREATE TABLE IF NOT EXISTS auth.refresh_session (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  jti uuid UNIQUE NOT NULL DEFAULT public.gen_random_uuid(),
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

GRANT SELECT, UPDATE, DELETE ON auth.refresh_session TO authenticated;

-- Enable Row-Level Security for the refresh_session table
ALTER TABLE auth.refresh_session ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can see their own refresh sessions
CREATE POLICY select_own_refresh_sessions ON auth.refresh_session
  FOR SELECT
  USING (user_id = auth.uid()); -- Use helper function to get current user ID

-- RLS Policy: Users can insert their own refresh sessions
CREATE POLICY insert_own_refresh_sessions ON auth.refresh_session
  FOR INSERT
  WITH CHECK (user_id = auth.uid()); -- Ensure they can only insert sessions for themselves

-- RLS Policy: Users can update their own refresh sessions
CREATE POLICY update_own_refresh_sessions ON auth.refresh_session
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid()); -- Ensure they can't change user_id

-- RLS Policy: Users can delete their own refresh sessions
CREATE POLICY delete_own_refresh_sessions ON auth.refresh_session
  FOR DELETE
  USING (user_id = auth.uid());

-- RLS Policy: Admin users have full access to all refresh sessions
CREATE POLICY admin_all_refresh_sessions ON auth.refresh_session
  FOR ALL -- Covers SELECT, INSERT, UPDATE, DELETE
  USING (pg_has_role(current_user, 'admin_user', 'MEMBER'))
  WITH CHECK (pg_has_role(current_user, 'admin_user', 'MEMBER'));

-- Cleanup function for expired sessions
CREATE OR REPLACE FUNCTION auth.cleanup_expired_sessions()
RETURNS void
LANGUAGE sql
SECURITY DEFINER -- Any user can remove expired refresh sessions; it's an amortized cleanup.
AS $$
  DELETE FROM auth.refresh_session WHERE expires_at < now();
$$;

-- Grant permissions
GRANT SELECT, UPDATE, DELETE ON auth.user TO authenticated;

-- Enable Row-Level Security for the user table
ALTER TABLE auth.user ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can see and update their own user record
CREATE POLICY select_own_user ON auth.user
  FOR SELECT
  USING (email = current_user);

-- RLS Policy: Users can update their own user record
CREATE POLICY update_own_user ON auth.user
  FOR UPDATE
  USING (email = current_user)
  WITH CHECK (email = current_user);

-- RLS Policy: Admin users have full access to all user records
-- This checks if the current PostgreSQL user has the 'admin_user' role granted (directly or indirectly)
CREATE POLICY admin_all_access ON auth.user
  FOR ALL -- Covers SELECT, INSERT, UPDATE, DELETE
  USING (pg_has_role(current_user, 'admin_user', 'MEMBER'))
  WITH CHECK (pg_has_role(current_user, 'admin_user', 'MEMBER'));

-- Grant necessary permissions for the admin RLS policy
GRANT INSERT, UPDATE, DELETE ON auth.user TO admin_user;
-- Note: SELECT permission is already granted via the 'authenticated' role


-- Create table for API keys
CREATE TABLE IF NOT EXISTS auth.api_key (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  jti uuid UNIQUE NOT NULL DEFAULT public.gen_random_uuid(), -- Corresponds to JWT ID claim
  user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE CASCADE,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL, -- Copied from JWT for reference
  -- last_used_on removed as it cannot be reliably updated in read-only transactions
  revoked_at timestamptz, -- NULL if active
  token text -- Stores the generated JWT token
);

-- Index for user lookup
CREATE INDEX ON auth.api_key (user_id);

GRANT SELECT, UPDATE, DELETE ON auth.api_key TO authenticated;

-- Enable Row-Level Security
ALTER TABLE auth.api_key ENABLE ROW LEVEL SECURITY;


-- RLS Policy: Users can see their own API keys
CREATE POLICY select_own_api_keys ON auth.api_key
  FOR SELECT
  USING (user_id = auth.uid()); -- Use helper function to get current user ID

-- RLS Policy: Users can insert their own API keys
CREATE POLICY insert_own_api_keys ON auth.api_key
  FOR INSERT
  WITH CHECK (user_id = auth.uid()); -- Ensure they can only insert keys for themselves

-- RLS Policy: Users can revoke (update revoked_at) their own API keys
CREATE POLICY revoke_own_api_keys ON auth.api_key
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid()); -- Ensure they can't change user_id

-- RLS Policy: Users can delete their own API keys
CREATE POLICY delete_own_api_keys ON auth.api_key
  FOR DELETE
  USING (user_id = auth.uid());

-- Grant table permissions to authenticated users (RLS handles row access)
GRANT SELECT, UPDATE (description, revoked_at), DELETE ON auth.api_key TO authenticated;
GRANT USAGE ON SEQUENCE auth.api_key_id_seq TO authenticated;


-- SECURITY INVOKER trigger function to check role assignment permissions.
-- This runs BEFORE the SECURITY DEFINER trigger that syncs credentials and roles.
CREATE OR REPLACE FUNCTION auth.check_role_permission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER -- Run as the user performing the INSERT/UPDATE
AS $check_role_permission$
BEGIN
  -- Check role assignment permission
  -- This check only applies if a role is being assigned (INSERT) or changed (UPDATE)
  RAISE DEBUG '[check_role_permission] Trigger fired. TG_OP: %, current_user: %, NEW.email: %, NEW.statbus_role: %', TG_OP, current_user, NEW.email, NEW.statbus_role;
  IF TG_OP = 'UPDATE' THEN
    RAISE DEBUG '[check_role_permission] OLD.statbus_role: %', OLD.statbus_role;
  END IF;

  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.statbus_role IS DISTINCT FROM NEW.statbus_role) THEN
    RAISE DEBUG '[check_role_permission] Checking role assignment: current_user % trying to assign/change to role %.', current_user, NEW.statbus_role;
    -- Check if the current user (invoker) is a member of the role they are trying to assign.
    -- This prevents users from assigning roles they don't possess themselves.
    -- Note: Role hierarchy (e.g., admin_user GRANTed regular_user) means admins can assign lower roles.
    IF NOT pg_has_role(current_user, NEW.statbus_role::text, 'MEMBER') THEN
      RAISE DEBUG '[check_role_permission] Permission check FAILED: current_user % is NOT a member of %.', current_user, NEW.statbus_role;
      RAISE EXCEPTION 'Permission denied: Cannot assign role %.', NEW.statbus_role
        USING HINT = 'The current user (' || current_user || ') must be a member of the target role.';
    ELSE
      RAISE DEBUG '[check_role_permission] Permission check PASSED: current_user % is a member of %.', current_user, NEW.statbus_role;
    END IF;
  END IF;

  -- Return NEW to allow the operation to proceed to the next trigger
  RETURN NEW;
END;
$check_role_permission$;

-- Trigger to run the permission check first
DROP TRIGGER IF EXISTS check_role_permission_trigger ON auth.user;
CREATE TRIGGER check_role_permission_trigger
BEFORE INSERT OR UPDATE ON auth.user
FOR EACH ROW
EXECUTE FUNCTION auth.check_role_permission();

-- SECURITY DEFINER function to encrypt password and synchronize database role.
-- Handles password encryption, role creation/rename, role grants, and DB role password sync.
-- Runs AFTER the check_role_permission trigger.
CREATE OR REPLACE FUNCTION auth.sync_user_credentials_and_roles()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Needs elevated privileges to manage roles and encrypt password securely
AS $sync_user_credentials_and_roles$
DECLARE
  role_name text;
  old_role_name text;
  db_password text;
BEGIN
  RAISE DEBUG '[sync_user_credentials_and_roles] Trigger fired. TG_OP: %, current_user (definer context): %, NEW.email: %, NEW.statbus_role: %', TG_OP, current_user, NEW.email, NEW.statbus_role;
  IF TG_OP = 'UPDATE' THEN
    RAISE DEBUG '[sync_user_credentials_and_roles] OLD.email: %, OLD.statbus_role: %', OLD.email, OLD.statbus_role;
  END IF;

  -- Use the email as the role name for the PostgreSQL role
  role_name := NEW.email;

  -- For UPDATE operations where email has changed, rename the corresponding database role
  IF TG_OP = 'UPDATE' AND OLD.email IS DISTINCT FROM NEW.email THEN
    old_role_name := OLD.email;
    
    -- Check if the old role exists
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = old_role_name) THEN
      -- Check if the old role exists before trying to rename
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = old_role_name) THEN
        -- Rename the role to match the new email
        EXECUTE format('ALTER ROLE %I RENAME TO %I', old_role_name, role_name);
        -- Role permissions (membership in authenticated, statbus_role) are retained after rename.
      ELSE
        -- If the old role doesn't exist, we might need to create the new one.
        -- This case handles scenarios where the role might have been manually dropped
        -- or if the email change happens before the role was initially created.
        -- The logic below will handle the creation if needed.
        RAISE DEBUG 'Old role % not found for renaming to %, will ensure new role exists.', old_role_name, role_name;
      END IF;
    -- If email didn't change, role_name is the same as OLD.email
    END IF; -- The old role didn't exists, mabye we are in a transaction with delayed triggers?
  END IF;

  -- Ensure the database role exists for the NEW.email
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
    -- Create the role with INHERIT (default) to ensure permissions flow through
    -- INHERIT is ESSENTIAL for the role hierarchy to work properly
    -- Without INHERIT, users would not get permissions from authenticated or their statbus role
    EXECUTE format('CREATE ROLE %I LOGIN INHERIT', role_name);
    
    -- Grant authenticated role to the user role
    -- This provides the base permissions needed for application functionality
    -- With INHERIT, the user will automatically have all permissions from authenticated
    EXECUTE format('GRANT authenticated TO %I', role_name);
    
    -- Grant the user role to authenticator to allow role switching via JWT impersonation
    EXECUTE format('GRANT %I TO authenticator', role_name);
    
    -- Grant the appropriate statbus role to the new role
    -- This determines the user's permission level (admin, regular, restricted, external)
    -- The user inherits all permissions from their statbus_role through role inheritance
    EXECUTE format('GRANT %I TO %I', NEW.statbus_role::text, role_name);
  -- If the role already exists, ensure its statbus_role membership is correct
  ELSIF TG_OP = 'UPDATE' AND OLD.statbus_role IS DISTINCT FROM NEW.statbus_role THEN
    -- If the statbus_role has changed, update the role grants for the database role
    IF OLD.statbus_role IS NOT NULL THEN
      EXECUTE format('REVOKE %I FROM %I', OLD.statbus_role::text, role_name);
    END IF;
    EXECUTE format('GRANT %I TO %I', NEW.statbus_role::text, role_name);
  END IF;

  -- 1. Encrypt password if provided in NEW.password (plain text)
  IF NEW.password IS NOT NULL THEN
    -- Set the encrypted password for application authentication
    NEW.encrypted_password := public.crypt(NEW.password, public.gen_salt('bf'));
    
    -- Set/Update the database role's password using the plain text password from NEW.password
    -- This ensures the database role password stays in sync with the application password.
    -- This needs to happen *before* we clear NEW.password.
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.encrypted_password IS DISTINCT FROM NEW.encrypted_password) THEN
      RAISE DEBUG '[sync_user_credentials_and_roles] Password provided/changed. Updating DB role % password.', role_name;
      EXECUTE format('ALTER ROLE %I WITH PASSWORD %L', role_name, NEW.password);
      RAISE DEBUG '[sync_user_credentials_and_roles] Set database role password for %', role_name;
    END IF;

    -- Clear the plain text password immediately after encryption and potential DB role update
    NEW.password := NULL;
  END IF;

  RETURN NEW;
END;
$sync_user_credentials_and_roles$;

-- Trigger to synchronize credentials and the database role after the permission check
DROP TRIGGER IF EXISTS sync_user_credentials_and_roles_trigger ON auth.user;
CREATE TRIGGER sync_user_credentials_and_roles_trigger
BEFORE INSERT OR UPDATE ON auth.user
FOR EACH ROW
EXECUTE FUNCTION auth.sync_user_credentials_and_roles();

-- Create a function to drop user role when user is deleted
CREATE OR REPLACE FUNCTION auth.drop_user_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $drop_user_role$
BEGIN
  -- Only drop the role if it exists and matches the user's email
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = OLD.email) THEN
    EXECUTE format('DROP ROLE %I', OLD.email);
  END IF;

  RETURN OLD;
END;
$drop_user_role$;

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
  refresh_expires timestamptz
) RETURNS void
LANGUAGE plpgsql
AS $set_auth_cookies$
DECLARE
  secure boolean;
  current_headers jsonb;
  new_headers jsonb;
BEGIN
  -- Check if the request is using HTTPS by examining the X-Forwarded-Proto header (case-insensitive)
  IF lower(nullif(current_setting('request.headers', true), '')::json->>'x-forwarded-proto') IS NOT DISTINCT FROM 'https' THEN
    secure := true;
  ELSE
    secure := false;
  END IF;
  
  -- Get current headers and prepare new ones
  current_headers := coalesce(nullif(current_setting('response.headers', true), '')::jsonb, '[]'::jsonb);
  new_headers := current_headers;
  
  -- Add access token cookie
  new_headers := new_headers || jsonb_build_array(
    jsonb_build_object(
      'Set-Cookie',
      format(
        'statbus=%s; Path=/; HttpOnly; SameSite=Strict; %sExpires=%s',
        access_jwt,
        CASE WHEN secure THEN 'Secure; ' ELSE '' END,
        to_char(access_expires, 'Dy, DD Mon YYYY HH24:MI:SS') || ' GMT'
      )
    )
  );
  
  -- Add refresh token cookie
  new_headers := new_headers || jsonb_build_array(
    jsonb_build_object(
      'Set-Cookie',
      format(
        'statbus-refresh=%s; Path=/rest/rpc/refresh; HttpOnly; SameSite=Strict; %sExpires=%s', -- Changed Path
        refresh_jwt,
        CASE WHEN secure THEN 'Secure; ' ELSE '' END,
        to_char(refresh_expires, 'Dy, DD Mon YYYY HH24:MI:SS') || ' GMT'
      )
    )
  );
  
  -- Set the headers in the response
  PERFORM set_config('response.headers', new_headers::text, true);
END;
$set_auth_cookies$;

-- Create a function to clear auth cookies
CREATE OR REPLACE FUNCTION auth.clear_auth_cookies()
RETURNS void
LANGUAGE plpgsql
AS $clear_auth_cookies$
DECLARE
  current_headers jsonb;
  new_headers jsonb;
BEGIN
  current_headers := coalesce(nullif(current_setting('response.headers', true), '')::jsonb, '[]'::jsonb);
  new_headers := current_headers;
  
  -- Add expired cookies (set to epoch)
  new_headers := new_headers || jsonb_build_array(
    jsonb_build_object(
      'Set-Cookie',
      'statbus=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Strict'
    )
  );
  
  new_headers := new_headers || jsonb_build_array(
    jsonb_build_object(
      'Set-Cookie',
      'statbus-refresh=; Path=/rest/rpc/refresh; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Strict' -- Changed Path
    )
  );
  
  PERFORM set_config('response.headers', new_headers::text, true);
END;
$clear_auth_cookies$;

-- Create auth response type
DROP TYPE IF EXISTS auth.auth_response CASCADE; -- Drop if exists to recreate with new field
CREATE TYPE auth.auth_response AS (
  is_authenticated boolean,
  token_expiring boolean,
  uid integer,
  sub uuid,
  email text,
  role text,
  statbus_role public.statbus_role,
  last_sign_in_at timestamptz,
  created_at timestamptz,
  error_code auth.login_error_code -- New field for login error details
);


-- Helper function to build the standard authentication response object
CREATE OR REPLACE FUNCTION auth.build_auth_response(
  p_user_record auth.user DEFAULT NULL,
  p_claims jsonb DEFAULT NULL,
  p_error_code auth.login_error_code DEFAULT NULL -- New parameter for error code
)
RETURNS auth.auth_response
LANGUAGE plpgsql
SECURITY INVOKER -- Runs with the privileges of the calling function
AS $build_auth_response$
DECLARE
  result auth.auth_response;
  current_epoch integer;
  expiration_time integer;
BEGIN
  IF p_user_record IS NULL THEN
    result.is_authenticated := false;
    result.token_expiring := false;
    result.uid := NULL;
    result.sub := NULL;
    result.email := NULL;
    result.role := NULL;
    result.statbus_role := NULL;
    result.last_sign_in_at := NULL;
    result.created_at := NULL;
    result.error_code := p_error_code; -- Assign the passed error code
  ELSE
    result.is_authenticated := true;
    result.uid := p_user_record.id;
    result.sub := p_user_record.sub;
    result.email := p_user_record.email;
    result.role := p_user_record.email; -- Role is typically the email for PostgREST
    result.statbus_role := p_user_record.statbus_role;
    result.last_sign_in_at := p_user_record.last_sign_in_at;
    result.created_at := p_user_record.created_at;
    result.error_code := NULL; -- Explicitly NULL on success

    -- Check token_expiring only if claims are provided and user is authenticated
    IF p_claims IS NOT NULL AND p_claims->>'exp' IS NOT NULL THEN
      current_epoch := extract(epoch from clock_timestamp())::integer;
      expiration_time := (p_claims->>'exp')::integer;
      result.token_expiring := expiration_time - current_epoch < 300; -- 5 minutes
    ELSE
      -- If no claims or no 'exp' in claims, token is not considered expiring by this check
      result.token_expiring := false;
    END IF;
  END IF;
  RETURN result;
END;
$build_auth_response$;

GRANT EXECUTE ON FUNCTION auth.build_auth_response(auth.user, jsonb, auth.login_error_code) TO authenticated, anon; -- Grant to roles that will call definer functions


-- Create login function that returns JWT token
CREATE OR REPLACE FUNCTION public.login(email text, password text)
RETURNS auth.auth_response
LANGUAGE plpgsql
SECURITY DEFINER
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
  -- Reject NULL passwords immediately
  IF login.password IS NULL THEN
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true); -- Unauthorized
    RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, 'USER_MISSING_PASSWORD'::auth.login_error_code);
  END IF;

  -- Find user by email
  SELECT u.* INTO _user
  FROM auth.user u
  WHERE u.email = login.email;

  -- If user not found
  IF NOT FOUND THEN
    -- Perform dummy crypt for timing resistance if email was provided
    IF login.email IS NOT NULL THEN
       PERFORM crypt(login.password, '$2a$10$0000000000000000000000000000000000000000000000000000');
    END IF;
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, 'USER_NOT_FOUND'::auth.login_error_code);
  END IF;

  -- If user is deleted
  IF _user.deleted_at IS NOT NULL THEN
    PERFORM crypt(login.password, _user.encrypted_password); -- Perform for timing
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, 'USER_DELETED'::auth.login_error_code);
  END IF;

  -- If user email is not confirmed
  IF _user.email_confirmed_at IS NULL THEN
    PERFORM crypt(login.password, _user.encrypted_password); -- Perform for timing
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, 'USER_NOT_CONFIRMED_EMAIL'::auth.login_error_code);
  END IF;

  -- At this point, user exists, is not deleted, and email is confirmed.
  -- Now, verify password.
  IF crypt(login.password, _user.encrypted_password) IS DISTINCT FROM _user.encrypted_password THEN
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true); -- Unauthorized
    RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, 'WRONG_PASSWORD'::auth.login_error_code);
  END IF;

  -- Set expiration times
  access_expires := clock_timestamp() + (coalesce(nullif(current_setting('app.settings.access_jwt_exp', true),'')::int, 3600) || ' seconds')::interval;
  refresh_expires := clock_timestamp() + (coalesce(nullif(current_setting('app.settings.refresh_jwt_exp', true),'')::int, 2592000) || ' seconds')::interval;
  
  -- Get client information
  user_ip := auth.get_request_ip();
  user_agent := nullif(current_setting('request.headers', true),'')::json->>'user-agent';

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
    p_expires_at => access_expires, 
    p_type => 'access'
  );

  -- Generate refresh token claims using the shared function
  refresh_claims := auth.build_jwt_claims(
    p_email => _user.email,
    p_expires_at => refresh_expires,
    p_type => 'refresh',
    p_additional_claims => jsonb_build_object(
      'jti', refresh_session_jti::text,
      'version', 0,  -- Initial version for this session
      'ip', user_ip::text  -- Include IP in token for verification
    )
  );

  -- Sign the tokens
  SELECT auth.generate_jwt(access_claims) INTO access_jwt;
  SELECT auth.generate_jwt(refresh_claims) INTO refresh_jwt;

  -- Update last sign in
  UPDATE auth.user
  SET last_sign_in_at = clock_timestamp(),
      updated_at = clock_timestamp()
  WHERE id = _user.id;

  -- Set cookies in response headers
  PERFORM auth.set_auth_cookies(
    access_jwt => access_jwt,
    refresh_jwt => refresh_jwt,
    access_expires => access_expires,
    refresh_expires => refresh_expires
  );

  -- Return the authentication response
  -- Note: We are no longer setting request.jwt.claims here.
  -- The returned auth_response is the source of truth for the new state.
  -- The client will use the new token for subsequent requests,
  -- at which point PostgREST's pre-request hook will set request.jwt.claims.
  RETURN auth.build_auth_response(_user, access_claims, NULL::auth.login_error_code);
END;
$login$;

-- Grant execute to anonymous users only
GRANT EXECUTE ON FUNCTION public.login TO anon;

-- Function to switch role using JWT token
CREATE OR REPLACE FUNCTION auth.switch_role_from_jwt(access_jwt text)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $switch_role_from_jwt$
DECLARE
  _claims json;
  _user_email text;
  _role_exists boolean;
BEGIN
  -- Verify and extract claims from JWT
  BEGIN
    SELECT payload::json INTO _claims 
    FROM verify(access_jwt, current_setting('app.settings.jwt_secret'));
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Invalid token: %', SQLERRM;
  END;
  
  -- Verify this is an access token
  IF _claims->>'type' != 'access' THEN
    RAISE EXCEPTION 'Invalid token type: expected access token';
  END IF;
  
  -- Extract user email from claims (which is also the role name)
  _user_email := _claims->>'role';
  
  IF _user_email IS NULL THEN
    RAISE EXCEPTION 'Token does not contain role claim';
  END IF;
  
  -- Check if a role exists for this user
  SELECT EXISTS(
    SELECT 1 FROM pg_roles WHERE rolname = _user_email
  ) INTO _role_exists;

  -- Ensure this function is called within a transaction, as SET ROLE is transaction-scoped.
  IF transaction_timestamp() = statement_timestamp() THEN
    RAISE EXCEPTION 'SET ROLE must be called within a transaction block (BEGIN...COMMIT/ROLLBACK).';
  END IF;

  IF NOT _role_exists THEN
    RAISE EXCEPTION 'Role % does not exist', _user_email;
  ELSE
    -- Switch to user-specific role
    EXECUTE format('SET ROLE %I', _user_email);
  END IF;
END;
$switch_role_from_jwt$;

-- Grant execute to authenticator role
GRANT EXECUTE ON FUNCTION auth.switch_role_from_jwt(text) TO authenticator;
-- Grant schema usage to authenticator role so it can access the function
GRANT USAGE ON SCHEMA auth TO authenticator;


-- Create refresh function that returns a new JWT token
CREATE OR REPLACE FUNCTION public.refresh()
RETURNS auth.auth_response
LANGUAGE plpgsql
SECURITY DEFINER
AS $refresh$
DECLARE
  _user auth.user;
  _session auth.refresh_session;
  claims json;
  token_version integer;
  refresh_session_jti uuid;
  current_ip inet;
  current_ua text;
  -- raw_ip_text text; -- No longer needed here, handled by auth.get_request_ip()
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
      PERFORM auth.reset_session_context(); -- Ensure context is cleared
      PERFORM set_config('response.status', '401', true);
      RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, 'REFRESH_NO_TOKEN_COOKIE'::auth.login_error_code);
    END IF;
    
    -- Decode the JWT to get the claims
    SELECT payload::json INTO claims
    FROM verify(refresh_token, current_setting('app.settings.jwt_secret'));
  END;
  
  -- Verify this is actually a refresh token
  IF claims->>'type' != 'refresh' THEN
    PERFORM auth.clear_auth_cookies();
    PERFORM auth.reset_session_context();
    PERFORM set_config('response.status', '401', true);
    RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, 'REFRESH_INVALID_TOKEN_TYPE'::auth.login_error_code);
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
    RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, 'REFRESH_USER_NOT_FOUND_OR_DELETED'::auth.login_error_code);
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
    RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, 'REFRESH_SESSION_INVALID_OR_SUPERSEDED'::auth.login_error_code);
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
  RETURN auth.build_auth_response(_user, access_claims, NULL::auth.login_error_code);
END;
$refresh$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.refresh TO authenticated;


-- Create logout response type
CREATE TYPE auth.logout_response AS (
  success boolean
);

-- Create a logout function
CREATE OR REPLACE FUNCTION public.logout()
RETURNS auth.auth_response
LANGUAGE plpgsql
SECURITY DEFINER
AS $logout$
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
  END IF;

  -- Set cookies in response headers to clear them
  PERFORM auth.clear_auth_cookies();

  -- Reset session context and return the "not authenticated" status
  PERFORM auth.reset_session_context();
  RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, NULL::auth.login_error_code);
END;
$logout$;

-- Create session info type
CREATE TYPE auth.session_info AS (
  id integer,
  created_at timestamptz,
  last_used_at timestamptz,
  user_agent text,
  ip_address inet,
  current_session boolean
);

-- Function to list a user's active sessions
CREATE OR REPLACE FUNCTION public.list_active_sessions()
RETURNS SETOF auth.session_info
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_sub uuid;
BEGIN
  -- Get current user ID from JWT claims
  user_sub := (current_setting('request.jwt.claims', true)::json->>'sub')::uuid;
  
  RETURN QUERY
  SELECT 
    s.id,
    s.created_at,
    s.last_used_at,
    s.user_agent,
    s.ip_address,
    (current_setting('request.jwt.claims', true)::json->>'jti')::uuid = s.jti AS current_session
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
  target_user_id integer;
BEGIN
  -- Get current user ID from JWT claims
  RAISE DEBUG '[revoke_session] Attempting to revoke session JTI: %. Current request.jwt.claims: %', refresh_session_jti, nullif(current_setting('request.jwt.claims', true), '');
  user_sub := (current_setting('request.jwt.claims', true)::jsonb->>'sub')::uuid;
  RAISE DEBUG '[revoke_session] User sub from claims: %', user_sub;

  SELECT id INTO target_user_id FROM auth.user WHERE sub = user_sub;
  RAISE DEBUG '[revoke_session] Target user ID resolved from sub % is %', user_sub, target_user_id;
  
  -- Delete the specified session if it belongs to the current user
  DELETE FROM auth.refresh_session
  WHERE jti = refresh_session_jti AND user_id = target_user_id;
  
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  RAISE DEBUG '[revoke_session] Rows affected by DELETE: % for JTI % and user_id %', affected_rows, refresh_session_jti, target_user_id;
  
  RETURN affected_rows > 0;
END;
$$;

-- Gets the User role (which is their email and the current_user)
CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT current_user;
$$ ;

-- Gets the User email (which is their email and the current_user)
CREATE OR REPLACE FUNCTION auth.email()
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT current_user;
$$ ;

-- Gets the User's statbus_role from the auth.user table based on current_user
CREATE OR REPLACE FUNCTION auth.statbus_role()
RETURNS public.statbus_role
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT statbus_role FROM auth.user WHERE email = current_user;
$$ ;


-- Function to get current authentication status
CREATE OR REPLACE FUNCTION public.auth_status()
RETURNS auth.auth_response
LANGUAGE plpgsql
SECURITY DEFINER
AS $auth_status$
DECLARE
  claims jsonb;
  user_sub uuid;
  user_record auth.user;
  is_authenticated boolean := false;
  token_expiring boolean := false;
  current_epoch integer;
  expiration_time integer;
  access_token text;
  refresh_token text;
  jwt_secret text;
BEGIN
  RAISE DEBUG '[auth_status] Starting. request.cookies: %, request.jwt.claims: %', nullif(current_setting('request.cookies', true), ''), nullif(current_setting('request.jwt.claims', true), '');
  jwt_secret := current_setting('app.settings.jwt_secret', true);
  
  -- Try to get tokens from cookies
  access_token := auth.extract_access_token_from_cookies();
  refresh_token := auth.extract_refresh_token_from_cookies();
    
  -- First try access token
  IF access_token IS NOT NULL THEN
    BEGIN
      SELECT payload::jsonb INTO claims
      FROM verify(access_token, jwt_secret);
      RAISE DEBUG '[auth_status] Claims from access_token cookie: %', claims;
      -- DO NOT set request.jwt.claims here. auth_status should be read-only regarding session GUCs.
    EXCEPTION WHEN OTHERS THEN
      RAISE DEBUG '[auth_status] Error verifying access_token cookie: %', SQLERRM;
      claims := NULL;
    END;
  END IF;
  
  -- If access token failed, try refresh token
  IF claims IS NULL AND refresh_token IS NOT NULL THEN
    BEGIN
      SELECT payload::jsonb INTO claims
      FROM verify(refresh_token, jwt_secret);
      
      IF claims->>'type' = 'refresh' THEN
        RAISE DEBUG '[auth_status] Claims from refresh_token cookie: %', claims;
        -- DO NOT set request.jwt.claims here.
        NULL; -- Claims from refresh token are valid for determining status.
      ELSE
        RAISE DEBUG '[auth_status] refresh_token cookie was not type "refresh", ignoring. Type: %', claims->>'type';
        claims := NULL; -- Not a refresh token, so ignore for this path.
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE DEBUG '[auth_status] Error verifying refresh_token cookie: %', SQLERRM;
      claims := NULL;
    END;
  END IF;
  
  -- If no claims from cookies, try request context
  IF claims IS NULL THEN
    RAISE DEBUG '[auth_status] No claims from cookies, trying request.jwt.claims GUC.';
    claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
    RAISE DEBUG '[auth_status] Claims from GUC: %', claims;
  END IF;
    
  -- Check if we have valid claims and a user can be found
  IF claims IS NOT NULL AND claims->>'sub' IS NOT NULL THEN
    user_sub := (claims->>'sub')::uuid;
    RAISE DEBUG '[auth_status] Attempting to find user by sub: %', user_sub;
    SELECT * INTO user_record
    FROM auth.user
    WHERE sub = user_sub AND deleted_at IS NULL;
    
    -- If user found, build response with user and claims
    IF FOUND THEN
      RAISE DEBUG '[auth_status] User found: %. Building authenticated response.', row_to_json(user_record);
      RETURN auth.build_auth_response(user_record, claims, NULL::auth.login_error_code);
    ELSE
      RAISE DEBUG '[auth_status] User with sub % NOT FOUND.', user_sub;
    END IF;
  ELSE
    RAISE DEBUG '[auth_status] No valid claims (or sub missing in claims) to find user. Claims: %', claims;
  END IF;
  
  -- If no valid claims, or user not found, return unauthenticated status
  RAISE DEBUG '[auth_status] Building unauthenticated response.';
  RETURN auth.build_auth_response(NULL::auth.user, NULL::jsonb, NULL::auth.login_error_code);
END;
$auth_status$;


-- Create token info type
CREATE TYPE auth.token_info AS (
  present boolean,
  token_length integer,
  claims json,
  valid boolean,
  expired boolean,
  jti text,
  version text
);

-- Create auth test response type
CREATE TYPE auth.auth_test_response AS (
  headers json,
  cookies json,
  claims json,
  access_token auth.token_info,
  refresh_token auth.token_info,
  timestamp timestamptz,
  deployment_slot text,
  is_https boolean,
  current_db_user text, -- Added
  current_db_role text  -- Added
);

-- Create a type to hold JWT verification results
DROP TYPE IF EXISTS auth.jwt_verification_result CASCADE;
CREATE TYPE auth.jwt_verification_result AS (
  is_valid boolean,
  claims jsonb,
  error_message text,
  expired boolean
);

-- Create a function to debug authentication inputs
CREATE OR REPLACE FUNCTION public.auth_test()
RETURNS auth.auth_test_response
LANGUAGE plpgsql
SECURITY INVOKER -- Reverted to INVOKER
AS $auth_test$
DECLARE
  headers jsonb; -- Changed to jsonb for consistency
  cookies jsonb; -- Changed to jsonb
  transactional_claims jsonb; -- Claims from PostgREST's GUC
  access_token_value text;
  refresh_token_value text;
  access_verification_result auth.jwt_verification_result;
  refresh_verification_result auth.jwt_verification_result;
  result auth.auth_test_response;
  access_token_info auth.token_info;
  refresh_token_info auth.token_info;
BEGIN
  -- Get headers, cookies, and claims from the current request context
  headers := nullif(current_setting('request.headers', true), '')::jsonb;
  cookies := nullif(current_setting('request.cookies', true), '')::jsonb;
  transactional_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;

  RAISE LOG '[public.auth_test] INVOKER context. current_user: %, request.jwt.claims GUC: %', current_user, transactional_claims;
  
  -- Get token strings from cookies
  access_token_value := cookies->>'statbus';
  refresh_token_value := cookies->>'statbus-refresh';
  
  -- Initialize token info structures
  access_token_info.present := false;
  refresh_token_info.present := false;

  -- Report on access token found in 'statbus' cookie (if any)
  IF access_token_value IS NOT NULL THEN
    access_verification_result := auth.verify_jwt_with_secret(access_token_value);
    access_token_info.present := TRUE;
    access_token_info.token_length := length(access_token_value);
    access_token_info.claims := access_verification_result.claims;
    access_token_info.valid := access_verification_result.is_valid;
    access_token_info.expired := access_verification_result.expired;
    IF NOT access_verification_result.is_valid THEN
      access_token_info.claims := coalesce(access_token_info.claims, '{}'::jsonb) || jsonb_build_object('verification_error', access_verification_result.error_message);
    END IF;
  ELSE
    access_token_info.present := FALSE;
    access_token_info.claims := jsonb_build_object('note', 'No statbus cookie found or cookie was empty.');
  END IF;
  
  -- Report on refresh token found in 'statbus-refresh' cookie (if any)
  IF refresh_token_value IS NOT NULL THEN
    refresh_verification_result := auth.verify_jwt_with_secret(refresh_token_value);
    refresh_token_info.present := TRUE;
    refresh_token_info.token_length := length(refresh_token_value);
    refresh_token_info.claims := refresh_verification_result.claims;
    refresh_token_info.valid := refresh_verification_result.is_valid;
    refresh_token_info.expired := refresh_verification_result.expired;
    IF NOT refresh_verification_result.is_valid THEN
      refresh_token_info.claims := coalesce(refresh_token_info.claims, '{}'::jsonb) || jsonb_build_object('verification_error', refresh_verification_result.error_message);
    ELSE
      refresh_token_info.jti := refresh_verification_result.claims->>'jti';
      refresh_token_info.version := refresh_verification_result.claims->>'version';
    END IF;
  END IF;
  
  -- Build result
  result.headers := headers; -- Use jsonb directly
  result.cookies := cookies; -- Use jsonb directly
  result.claims := transactional_claims; -- This will now reflect the actual authenticated user's claims
  result.access_token := access_token_info;
  result.refresh_token := refresh_token_info;
  result.timestamp := clock_timestamp();
  result.deployment_slot := coalesce(current_setting('app.settings.deployment_slot_code', true), 'dev');
  result.current_db_user := current_user; -- current_user reflects the role after SET ROLE
  result.current_db_role := current_role; -- current_role is the effective role of the user.
  
  -- Ensure headers is not null before trying to access a key
  IF headers IS NOT NULL AND headers ? 'x-forwarded-proto' THEN
    result.is_https := lower(headers->>'x-forwarded-proto') = 'https'; -- Case-insensitive check
  ELSE
    result.is_https := false; -- Default if header is missing
  END IF;
  
  RETURN result;
END;
$auth_test$;

-- Grant execute to both anonymous and authenticated users
GRANT EXECUTE ON FUNCTION public.auth_test TO authenticated, anon; -- Changed to include anon as it's SECURITY INVOKER

-- Grant execute to authenticated users only (relies on auth helpers now)
GRANT EXECUTE ON FUNCTION public.auth_status TO authenticated; -- Removed anon

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.logout TO authenticated;
GRANT EXECUTE ON FUNCTION public.login TO anon;
GRANT EXECUTE ON FUNCTION public.refresh TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_active_sessions TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_session TO authenticated;

-- Grant usage on auth functions to API roles to authenticated and anon users for RLS checks.
GRANT USAGE ON SCHEMA auth TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.uid TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.role TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.email TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.statbus_role TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.sub TO authenticated, anon;

-- Grant monitoring capabilities to admin role
GRANT pg_monitor TO admin_user;

-- Function to build a JWT claims object for a user based on their email
CREATE OR REPLACE FUNCTION auth.build_jwt_claims(
  p_email text, -- User's email address (required)
  p_expires_at timestamptz DEFAULT NULL, -- Optional expiration time override
  p_type text DEFAULT 'access', -- Type of token ('access', 'refresh', 'api_key')
  p_additional_claims jsonb DEFAULT '{}'::jsonb -- Optional additional claims to merge
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_user auth.user;
  v_expires_at timestamptz;
  v_claims jsonb;
BEGIN
  -- Find user by email (required)
  SELECT * INTO v_user
  FROM auth.user
  WHERE email = p_email AND deleted_at IS NULL;
    
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User with email % not found', p_email;
  END IF;
  
  -- Set expiration time using provided value or default based on type
  v_expires_at := COALESCE(
    p_expires_at,
    clock_timestamp() + (coalesce(current_setting('app.settings.access_jwt_exp', true)::int, 3600) || ' seconds')::interval
  );
  
  -- Build claims with PostgREST compatible structure, deriving sub and role from user record
  v_claims := jsonb_build_object(
    'role', v_user.email, -- PostgREST does a 'SET LOCAL ROLE $role' to ensure security for all of the API
    'statbus_role', v_user.statbus_role::text,
    'sub', v_user.sub::text,
    'uid', v_user.id, -- Add the integer user ID
    'email', v_user.email,
    'type', p_type,
    'iat', extract(epoch from clock_timestamp())::integer,
    'exp', extract(epoch from v_expires_at)::integer
  );
  
  -- Add JTI if not in additional claims
  IF NOT p_additional_claims ? 'jti' THEN
    v_claims := v_claims || jsonb_build_object('jti', public.gen_random_uuid()::text);
  END IF;
  
  -- Merge additional claims
  RETURN v_claims || p_additional_claims;
END;
$$;

-- Function to set the current session context from JWT claims
CREATE OR REPLACE FUNCTION auth.use_jwt_claims_in_session(claims jsonb)
RETURNS void
LANGUAGE plpgsql
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
AS $extract_refresh_token_from_cookies$
DECLARE
  cookies json;
BEGIN
  cookies := nullif(current_setting('request.cookies', true), '')::json;
  
  IF cookies IS NULL THEN
    RETURN NULL;
  END IF;
  
  RETURN cookies->>'statbus-refresh';
END;
$extract_refresh_token_from_cookies$;

-- Function to set user context from email
CREATE OR REPLACE FUNCTION auth.set_user_context_from_email(p_email text)
RETURNS void
LANGUAGE plpgsql
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
AS $generate_jwt$
DECLARE
  token text;
BEGIN
  SELECT public.sign(
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
AS $$
BEGIN
  -- Clear JWT claims
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

-- Create a function to extract access token from cookies
CREATE OR REPLACE FUNCTION auth.extract_access_token_from_cookies()
RETURNS text
LANGUAGE plpgsql
AS $extract_access_token_from_cookies$
DECLARE
  cookies json;
BEGIN
  cookies := nullif(current_setting('request.cookies', true), '')::json;
  
  IF cookies IS NULL THEN
    RETURN NULL;
  END IF;
  
  RETURN cookies->>'statbus';
END;
$extract_access_token_from_cookies$;


-- Create a SECURITY DEFINER function to verify a JWT using the secret
CREATE OR REPLACE FUNCTION auth.verify_jwt_with_secret(token_value text)
RETURNS auth.jwt_verification_result
LANGUAGE plpgsql
SECURITY DEFINER
AS $verify_jwt_with_secret$
DECLARE
  _claims jsonb;
  _jwt_secret text;
  _result auth.jwt_verification_result;
BEGIN
  _jwt_secret := current_setting('app.settings.jwt_secret', true);
  _result.is_valid := false;
  _result.error_message := 'Token verification not attempted';
  _result.expired := null;

  IF token_value IS NULL THEN
    _result.error_message := 'Token is NULL';
    RETURN _result;
  END IF;

  BEGIN
    SELECT payload::jsonb INTO _claims
    FROM public.verify(token_value, _jwt_secret);

    _result.is_valid := TRUE;
    _result.claims := _claims;
    _result.error_message := NULL;
    IF (_claims->>'exp')::numeric < extract(epoch from clock_timestamp()) THEN
      _result.expired := TRUE;
    ELSE
      _result.expired := FALSE;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    _result.is_valid := FALSE;
    _result.claims := NULL;
    _result.error_message := SQLERRM;
    -- Check if the error message indicates an expired signature specifically
    IF SQLERRM LIKE '%expired_signature%' THEN
        _result.expired := TRUE;
    ELSE
        _result.expired := NULL; -- Unknown if expired if another error occurred
    END IF;
  END;

  RETURN _result;
END;
$verify_jwt_with_secret$;

-- Grant execute to authenticated and anon roles so SECURITY INVOKER functions can call it
GRANT EXECUTE ON FUNCTION auth.verify_jwt_with_secret(text) TO authenticated, anon;


-- Grant execute to authenticated users (though likely only used internally by SECURITY DEFINER functions)
GRANT EXECUTE ON FUNCTION auth.extract_access_token_from_cookies TO authenticated; -- Removed anon

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION auth.build_jwt_claims TO authenticated;
GRANT EXECUTE ON FUNCTION auth.use_jwt_claims_in_session TO authenticated;
GRANT EXECUTE ON FUNCTION auth.set_user_context_from_email TO authenticated;
GRANT EXECUTE ON FUNCTION auth.reset_session_context TO authenticated;
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

-- Create a trigger function to generate JWT token for API keys
CREATE OR REPLACE FUNCTION auth.generate_api_key_token()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Needs access to JWT secret
AS $generate_api_key_token$
DECLARE
  _user auth.user;
  _claims jsonb;
  _api_key_jwt text;
BEGIN
  -- Get the user for this API key
  SELECT * INTO _user
  FROM auth.user
  WHERE id = NEW.user_id
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found for API key creation';
  END IF;

  -- Build claims for the API key JWT
  _claims := auth.build_jwt_claims(
    p_email => _user.email,
    p_expires_at => NEW.expires_at,
    p_type => 'api_key',
    p_additional_claims => jsonb_build_object(
      'description', NEW.description,
      'jti', NEW.jti::text
    )
  );

  -- Generate the signed JWT
  SELECT auth.generate_jwt(_claims) INTO _api_key_jwt;
  
  -- Store the token in the record
  NEW.token := _api_key_jwt;
  
  RETURN NEW;
END;
$generate_api_key_token$;

-- Create the trigger to automatically generate the token
DROP TRIGGER IF EXISTS generate_api_key_token_trigger ON auth.api_key;
CREATE TRIGGER generate_api_key_token_trigger
BEFORE INSERT ON auth.api_key
FOR EACH ROW
EXECUTE FUNCTION auth.generate_api_key_token();

-- Create a public view for API keys with SECURITY INVOKER
CREATE OR REPLACE VIEW public.api_key
WITH (security_invoker=true) AS
SELECT 
  id,
  jti,
  user_id,
  description,
  created_at,
  expires_at,
  revoked_at,
  token
FROM auth.api_key;

-- Grant access to the view
GRANT SELECT, INSERT, UPDATE (description, revoked_at), DELETE ON public.api_key TO authenticated;

-- Note: Explicit RLS on the view is not needed with security_invoker=true
-- as the view already inherits the security context of the calling user
-- and the underlying table's RLS policies will be applied.

-- Grant direct access to the auth.api_key table (for the view to work)
GRANT SELECT, INSERT, UPDATE (description, revoked_at), DELETE ON auth.api_key TO authenticated;


-- Function for a user to change their own password
CREATE OR REPLACE FUNCTION public.change_password(
    new_password text
)
RETURNS boolean -- Returns true on success
LANGUAGE plpgsql
SECURITY INVOKER -- The user must have the rights to update their own password
AS $change_password$
DECLARE
  _user auth.user;
  _claims jsonb;
BEGIN
  -- Get claims from the current JWT
  _claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;

  -- Ensure this function is called with an 'access' token, not refresh or api_key
  IF _claims IS NOT NULL AND _claims->>'type' IS DISTINCT FROM 'access' THEN
    RAISE EXCEPTION 'Password change requires a valid access token.';
  END IF;

  -- Get the current user based on the JWT's sub claim
  SELECT * INTO _user
  FROM auth.user
  WHERE email = current_user;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found.'; -- Should not happen if JWT is valid
  END IF;

  -- Check new password strength/requirements if needed (add logic here)
  IF length(new_password) < 8 THEN -- Example minimum length check
     RAISE EXCEPTION 'New password is too short (minimum 8 characters).';
  END IF;

  -- Update the user's password
  -- The sync_user_credentials_and_roles_trigger will handle password hashing
  -- and updating the DB role password.
  UPDATE auth.user
  SET
    password = new_password,
    updated_at = clock_timestamp()
  WHERE id = _user.id;
  
  -- Invalidate all existing refresh sessions for this user
  DELETE FROM auth.refresh_session
  WHERE user_id = _user.id;
  
  -- Clear auth cookies
  PERFORM auth.clear_auth_cookies();

  RAISE DEBUG 'Password changed successfully for user % (%)', _user.email, _user.sub;

  RETURN true;
END;
$change_password$;

-- Grant execute permission to authenticated users for changing their own password
GRANT EXECUTE ON FUNCTION public.change_password(text) TO authenticated;


-- Function for an admin to change any user's password
CREATE OR REPLACE FUNCTION public.admin_change_password(
    user_sub uuid,
    new_password text
)
RETURNS boolean -- Returns true on success
LANGUAGE plpgsql
SECURITY INVOKER -- BY RLS admin can call this.
AS $admin_change_password$
DECLARE
  _target_user auth.user;
BEGIN
  -- Check if the caller is an admin
  IF NOT pg_has_role(current_user, 'admin_user', 'MEMBER') THEN
     RAISE EXCEPTION 'Permission denied: Only admin users can change other users passwords.';
  END IF;

  -- Get the target user
  SELECT * INTO _target_user
  FROM auth.user
  WHERE sub = user_sub
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target user not found.';
  END IF;

  -- Check new password strength/requirements if needed
  IF length(new_password) < 8 THEN
     RAISE EXCEPTION 'New password is too short (minimum 8 characters).';
  END IF;

  -- Update the target user's password
  -- The sync_user_credentials_and_roles_trigger will handle password hashing
  -- and updating the DB role password.
  UPDATE auth.user
  SET
    password = new_password,
    updated_at = clock_timestamp()
  WHERE id = _target_user.id;

  -- Invalidate all existing refresh sessions for the target user
  DELETE FROM auth.refresh_session
  WHERE user_id = _target_user.id;
  
  RAISE DEBUG 'Password changed successfully for user % (%) by %',
    _target_user.email, _target_user.sub, current_user;

  RETURN true;
END;
$admin_change_password$;

-- Grant execute permission only to admin users
GRANT EXECUTE ON FUNCTION public.admin_change_password(uuid, text) TO admin_user;

-- Pre-request function to check API key revocation
CREATE OR REPLACE FUNCTION auth.check_api_key_revocation()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- Check happens after role switch, but define as SECURITY DEFINER for safety
AS $check_api_key_revocation$
DECLARE
  _claims jsonb;
  _token_type text;
  _jti uuid;
  _revoked_at timestamptz; -- Store only the revocation timestamp
  _current_date date := current_date; -- Get date once
BEGIN
  -- Get claims from the current JWT
  _claims := current_setting('request.jwt.claims', true)::jsonb;
  _token_type := _claims->>'type';

  -- Only perform checks for API keys
  IF _token_type = 'api_key' THEN
    _jti := (_claims->>'jti')::uuid;

    IF _jti IS NULL THEN
      RAISE EXCEPTION 'Invalid API Key: Missing JTI claim.' USING ERRCODE = 'P0001';
    END IF;

    -- Check if the key exists and is revoked
    SELECT revoked_at INTO _revoked_at
    FROM auth.api_key
    WHERE jti = _jti;

    IF NOT FOUND THEN
      -- Key might have been deleted or never existed
      RAISE EXCEPTION 'Invalid API Key: Key not found.' USING ERRCODE = 'P0001';
    END IF;

    IF _revoked_at IS NOT NULL THEN
      RAISE EXCEPTION 'API Key has been revoked.' USING ERRCODE = 'P0001';
    END IF;

    -- last_used_on update removed due to issues with read-only transactions

  END IF;

  -- If not an API key or if key is valid and not revoked, proceed
  RETURN;
END;
$check_api_key_revocation$;

-- Grant execute permission to authenticated role (covers all user roles)
GRANT EXECUTE ON FUNCTION auth.check_api_key_revocation() TO authenticated;




-- Helper function to create an API key through the public view
CREATE OR REPLACE FUNCTION public.create_api_key(
    description text DEFAULT 'Default API Key',
    duration interval DEFAULT '1 year'
)
RETURNS public.api_key
LANGUAGE plpgsql
SECURITY INVOKER
AS $create_api_key$
DECLARE
  _user_id integer;
  _expires_at timestamptz;
  _jti uuid := public.gen_random_uuid();
  _result public.api_key;
BEGIN
  -- Get current user ID
  _user_id := auth.uid();
  
  -- Calculate expiration time
  _expires_at := clock_timestamp() + duration;
  
  -- Insert the new API key
  INSERT INTO public.api_key (
    jti, 
    user_id, 
    description, 
    expires_at
  ) 
  VALUES (
    _jti, 
    _user_id, 
    description, 
    _expires_at
  )
  RETURNING * INTO _result;
  
  RETURN _result;
END;
$create_api_key$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.create_api_key(text, interval) TO authenticated;

-- Function for users to revoke their own API key
CREATE OR REPLACE FUNCTION public.revoke_api_key(
    key_jti uuid
)
RETURNS boolean -- Returns true on success
LANGUAGE plpgsql
SECURITY INVOKER -- Run as the calling user (RLS handles access)
AS $revoke_api_key$
DECLARE
  _api_key_record public.api_key;
  _affected_rows integer;
BEGIN
  -- RLS policy ensures user can only update their own keys
  UPDATE public.api_key
  SET revoked_at = clock_timestamp()
  WHERE jti = key_jti
    -- RLS implicitly adds AND user_id = auth.uid()
    AND revoked_at IS NULL; -- Only revoke if not already revoked

  GET DIAGNOSTICS _affected_rows = ROW_COUNT;

  IF _affected_rows = 0 THEN
     -- Check if key exists at all (and belongs to user due to RLS)
     SELECT * INTO _api_key_record FROM public.api_key WHERE jti = key_jti;
     IF NOT FOUND THEN
        RAISE EXCEPTION 'API Key not found or permission denied.';
     ELSE
        -- Key exists but was already revoked or update failed
        RAISE WARNING 'API Key was already revoked or update failed.';
        RETURN false;
     END IF;
  END IF;

  RAISE DEBUG 'API Key revoked: %', key_jti;
  RETURN true;
END;
$revoke_api_key$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.revoke_api_key(uuid) TO authenticated;

COMMIT;

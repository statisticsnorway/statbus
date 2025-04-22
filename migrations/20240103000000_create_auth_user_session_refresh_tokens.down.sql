-- Down Migration: Remove auth schema tables
BEGIN;

-- Remove all inserted users to run cleanup triggers for their roles.
DELETE FROM auth.user;

-- Drop scheduled job if pg_cron is available
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('cleanup-expired-sessions');
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- pg_cron not available, that's fine
END;
$$;

-- Revoke permissions first, before dropping objects they apply to

-- Revoke execute permissions on public functions
REVOKE EXECUTE ON FUNCTION public.revoke_api_key(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.create_api_key(text, interval) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_change_password(uuid, text) FROM admin_user;
REVOKE EXECUTE ON FUNCTION public.change_password(text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.auth_test() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.auth_status() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.revoke_session(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.list_active_sessions() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.logout() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.refresh() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.login(text, text) FROM anon;

-- Revoke execute permissions on auth functions
REVOKE EXECUTE ON FUNCTION auth.check_api_key_revocation() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.generate_api_key_token() FROM authenticated; -- Trigger function, likely no direct grants needed, but revoke for safety
REVOKE EXECUTE ON FUNCTION auth.extract_access_token_from_cookies() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.reset_session_context() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.generate_jwt(jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.set_user_context_from_email(text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.build_auth_response(text, text, auth.user) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.extract_refresh_token_from_cookies() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.use_jwt_claims_in_session(jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.build_jwt_claims(text, timestamptz, text, jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.clear_auth_cookies() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.set_auth_cookies(text, text, timestamptz, timestamptz) FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION auth.drop_user_role() FROM ...; -- SECURITY DEFINER, no direct grants expected
-- REVOKE EXECUTE ON FUNCTION auth.sync_user_credentials_and_roles() FROM ...; -- SECURITY DEFINER, no direct grants expected
-- REVOKE EXECUTE ON FUNCTION auth.check_role_permission() FROM ...; -- SECURITY INVOKER, no direct grants expected
-- REVOKE EXECUTE ON FUNCTION auth.cleanup_expired_sessions() FROM ...; -- SECURITY DEFINER, no direct grants expected
REVOKE EXECUTE ON FUNCTION auth.uid() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION auth.sub() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION auth.statbus_role() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION auth.email() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION auth.role() FROM authenticated, anon;

-- Revoke table/view/sequence permissions
REVOKE SELECT, INSERT, UPDATE (description, revoked_at), DELETE ON public.api_key FROM authenticated;
REVOKE SELECT, UPDATE (description, revoked_at), DELETE ON auth.api_key FROM authenticated; -- Revoke direct access if granted
REVOKE USAGE ON SEQUENCE auth.api_key_id_seq FROM authenticated;
REVOKE SELECT, UPDATE, DELETE ON auth.refresh_session FROM authenticated;
REVOKE SELECT, UPDATE, DELETE ON auth.user FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON auth.user FROM admin_user; -- Revoked from admin role

-- Revoke schema usage
REVOKE USAGE ON SCHEMA auth FROM authenticated, anon;

-- Revoke role memberships
REVOKE pg_monitor FROM admin_user;

-- Now drop objects in reverse order of creation

-- Drop public functions
DROP FUNCTION IF EXISTS public.revoke_api_key(uuid);
DROP FUNCTION IF EXISTS public.create_api_key(text, interval);
DROP FUNCTION IF EXISTS public.admin_change_password(uuid, text);
DROP FUNCTION IF EXISTS public.change_password(text);
DROP FUNCTION IF EXISTS public.auth_test();
DROP FUNCTION IF EXISTS public.auth_status();
DROP FUNCTION IF EXISTS public.revoke_session(uuid);
DROP FUNCTION IF EXISTS public.list_active_sessions();
DROP FUNCTION IF EXISTS public.logout();
DROP FUNCTION IF EXISTS public.refresh();
DROP FUNCTION IF EXISTS public.login(text, text);

-- Drop public view
DROP VIEW IF EXISTS public.api_key;

-- Drop triggers (before functions they use or tables they are on)
DROP TRIGGER IF EXISTS generate_api_key_token_trigger ON auth.api_key;
DROP TRIGGER IF EXISTS drop_user_role_trigger ON auth.user;
DROP TRIGGER IF EXISTS sync_user_credentials_and_roles_trigger ON auth.user;
DROP TRIGGER IF EXISTS check_role_permission_trigger ON auth.user;

-- Drop RLS policies (before functions like auth.uid they might use)
-- Policies on auth.api_key (depend on auth.uid)
DROP POLICY IF EXISTS delete_own_api_keys ON auth.api_key;
DROP POLICY IF EXISTS revoke_own_api_keys ON auth.api_key;
DROP POLICY IF EXISTS select_own_api_keys ON auth.api_key;
DROP POLICY IF EXISTS insert_own_api_keys ON auth.api_key;
-- Policies on auth.user (depend on pg_has_role, current_user)
DROP POLICY IF EXISTS admin_all_access ON auth.user;
DROP POLICY IF EXISTS update_own_user ON auth.user;
DROP POLICY IF EXISTS select_own_user ON auth.user;
-- Policies on auth.refresh_session (depend on auth.uid, pg_has_role)
DROP POLICY IF EXISTS admin_all_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS delete_own_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS update_own_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS insert_own_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS select_own_refresh_sessions ON auth.refresh_session;

-- Drop auth functions (reverse order of creation/dependency)
DROP FUNCTION IF EXISTS auth.check_api_key_revocation();
DROP FUNCTION IF EXISTS auth.generate_api_key_token();
DROP FUNCTION IF EXISTS auth.extract_access_token_from_cookies();
DROP FUNCTION IF EXISTS auth.reset_session_context();
DROP FUNCTION IF EXISTS auth.generate_jwt(jsonb);
DROP FUNCTION IF EXISTS auth.set_user_context_from_email(text);
DROP FUNCTION IF EXISTS auth.build_auth_response(text, text, auth.user); -- Depends on auth.user type
DROP FUNCTION IF EXISTS auth.extract_refresh_token_from_cookies();
DROP FUNCTION IF EXISTS auth.use_jwt_claims_in_session(jsonb);
DROP FUNCTION IF EXISTS auth.build_jwt_claims(text, timestamptz, text, jsonb);
DROP FUNCTION IF EXISTS auth.clear_auth_cookies();
DROP FUNCTION IF EXISTS auth.set_auth_cookies(text, text, timestamptz, timestamptz);
DROP FUNCTION IF EXISTS auth.drop_user_role();
DROP FUNCTION IF EXISTS auth.sync_user_credentials_and_roles();
DROP FUNCTION IF EXISTS auth.check_role_permission();
DROP FUNCTION IF EXISTS auth.cleanup_expired_sessions();
DROP FUNCTION IF EXISTS auth.uid(); -- Drop after policies that use it
DROP FUNCTION IF EXISTS auth.sub(); -- Drop after policies/functions that use it
DROP FUNCTION IF EXISTS auth.statbus_role();
DROP FUNCTION IF EXISTS auth.email();
DROP FUNCTION IF EXISTS auth.role();

-- Drop tables (reverse order of dependency)
DROP TABLE IF EXISTS auth.api_key;
DROP TABLE IF EXISTS auth.refresh_session;
DROP TABLE IF EXISTS auth.user; -- Drops auth.user type implicitly

-- Drop auth types (reverse order of creation/dependency)
DROP TYPE IF EXISTS auth.auth_test_response;
DROP TYPE IF EXISTS auth.token_info;
DROP TYPE IF EXISTS auth.auth_status_response;
DROP TYPE IF EXISTS auth.session_info;
DROP TYPE IF EXISTS auth.logout_response;
DROP TYPE IF EXISTS auth.auth_response;

-- Find and drop all user-specific roles created by the system
DO $$
DECLARE
  role_record RECORD;
BEGIN
  -- Find all roles that were granted the 'authenticated' role
  -- These are likely the user-specific roles we created
  FOR role_record IN
    SELECT r.rolname
    FROM pg_roles r
    JOIN pg_auth_members m ON m.member = r.oid
    JOIN pg_roles g ON g.oid = m.roleid
    WHERE g.rolname = 'authenticated'
      AND r.rolname <> 'authenticator' -- Exclude authenticator role
      AND r.rolname NOT IN ('admin_user', 'regular_user', 'restricted_user', 'external_user') -- Exclude hierarchy roles
  LOOP
    -- For each role, revoke memberships and drop it.
    -- REVOKE and DROP ROLE IF EXISTS are idempotent, so no need for exception handling.

    -- Revoke memberships from hierarchy roles if they exist
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
      EXECUTE format('REVOKE %I FROM admin_user', role_record.rolname);
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'regular_user') THEN
      EXECUTE format('REVOKE %I FROM regular_user', role_record.rolname);
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'restricted_user') THEN
      EXECUTE format('REVOKE %I FROM restricted_user', role_record.rolname);
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'external_user') THEN
      EXECUTE format('REVOKE %I FROM external_user', role_record.rolname);
    END IF;
    -- Revoke membership in 'authenticated'
    EXECUTE format('REVOKE authenticated FROM %I', role_record.rolname);
    -- Revoke role from authenticator
    EXECUTE format('REVOKE %I FROM authenticator', role_record.rolname);
    -- Drop the role
    EXECUTE format('DROP ROLE IF EXISTS %I', role_record.rolname);
    RAISE DEBUG 'Dropped user-specific role: %', role_record.rolname;
  END LOOP;
END
$$;


SET client_min_messages TO DEBUG2;
-- Revoke hierarchy grants and drop hierarchy roles
DO $$
DECLARE
  role_name text;
  r record; -- For iterating over views/tables/etc.
  hierarchy_roles text[] := ARRAY['admin_user', 'regular_user', 'restricted_user', 'external_user'];
BEGIN
  RAISE DEBUG 'Starting revocation of privileges from hierarchy roles: %', hierarchy_roles;

  -- Iterate through each hierarchy role to revoke privileges
  FOREACH role_name IN ARRAY hierarchy_roles
  LOOP
    -- Check if the role actually exists before attempting revocations
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      RAISE DEBUG 'Processing revocations for existing role: %', role_name;

      -- Revoke privileges on all existing public views
      RAISE DEBUG 'Revoking privileges on public views for role %', role_name;
      -- Cannot use REVOKE ALL ON ALL VIEWS, must iterate
      FOR r IN SELECT schemaname, viewname FROM pg_views WHERE schemaname = 'public'
      LOOP
        -- REVOKE is idempotent, no need for exception handling
        EXECUTE format('REVOKE ALL PRIVILEGES ON %I.%I FROM %I', r.schemaname, r.viewname, role_name);
        RAISE DEBUG 'Revoked ALL privileges on view %I.%I from %I', r.schemaname, r.viewname, role_name;
      END LOOP;

      -- Revoke privileges on all existing public tables, sequences, functions
      RAISE DEBUG 'Revoking privileges on public tables, sequences, functions for role %', role_name;
      EXECUTE format('REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM %I', role_name);
      EXECUTE format('REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM %I', role_name);
      EXECUTE format('REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public FROM %I', role_name);

      -- Revoke default privileges granted TO this role in the public schema
      RAISE DEBUG 'Revoking default privileges in schema public for role %', role_name;
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM %I', role_name);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM %I', role_name);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM %I', role_name);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TYPES FROM %I', role_name);

      -- Revoke usage on the public schema itself
      RAISE DEBUG 'Revoking usage on schema public for role %', role_name;
      EXECUTE format('REVOKE USAGE ON SCHEMA public FROM %I', role_name);

      -- Attempt to reassign ownership if needed (less common for hierarchy roles, more for user roles)
      -- Consider if objects might be owned by these hierarchy roles. If so, reassign before dropping.
      -- EXECUTE format('REASSIGN OWNED BY %I TO postgres', role_name); -- Or another appropriate role

    ELSE
      RAISE DEBUG 'Hierarchy role % does not exist, skipping revocations.', role_name;
    END IF; -- End check for role existence
  END LOOP; -- End loop through hierarchy roles

  RAISE DEBUG 'Finished revoking potentially problematic privileges.';
  RAISE DEBUG 'Proceeding to revoke role hierarchy memberships.';

  -- Now, revoke role hierarchy memberships (must happen after object privilege revocations)
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
    EXECUTE 'REVOKE regular_user FROM admin_user';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'regular_user') THEN
    EXECUTE 'REVOKE restricted_user FROM regular_user';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'restricted_user') THEN
    EXECUTE 'REVOKE external_user FROM restricted_user';
  END IF;

  -- Drop the roles in reverse order of hierarchy
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'external_user') THEN
    EXECUTE 'DROP ROLE IF EXISTS external_user';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'restricted_user') THEN
    EXECUTE 'DROP ROLE IF EXISTS restricted_user';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'regular_user') THEN
    EXECUTE 'DROP ROLE IF EXISTS regular_user';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
    EXECUTE 'DROP ROLE IF EXISTS admin_user';
  END IF;
END -- End of DO block
$$;

-- Drop public type
DROP TYPE IF EXISTS public.statbus_role;

-- Drop the domain type
DROP DOMAIN IF EXISTS "application/json";

-- Drop auth schema
DROP SCHEMA IF EXISTS auth;

COMMIT;

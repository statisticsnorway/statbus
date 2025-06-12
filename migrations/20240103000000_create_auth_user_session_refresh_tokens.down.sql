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

-- 3. Revoke auth function grants
REVOKE EXECUTE ON FUNCTION auth.check_api_key_revocation() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.extract_access_token_from_cookies() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.generate_jwt(jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.reset_session_context() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.set_user_context_from_email(text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.extract_refresh_token_from_cookies() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.set_auth_cookies(text, text, timestamptz, timestamptz) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.clear_auth_cookies() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.use_jwt_claims_in_session(jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.build_jwt_claims(text, timestamptz, text, jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.build_auth_response(auth.user, jsonb, auth.login_error_code) FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION auth.switch_role_from_jwt(text) FROM authenticator; -- Added
REVOKE EXECUTE ON FUNCTION auth.statbus_role() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION auth.email() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION auth.role() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION auth.uid() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION auth.sub() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION auth.get_request_ip() FROM authenticated, anon;

-- 4. Revoke table/view/sequence grants
REVOKE SELECT, INSERT, UPDATE (description, revoked_at), DELETE ON public.api_key FROM authenticated;
REVOKE SELECT, INSERT, UPDATE (description, revoked_at), DELETE ON auth.api_key FROM authenticated; -- Corrected: Revoke from the table
REVOKE USAGE ON SEQUENCE auth.api_key_id_seq FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON auth.user FROM admin_user;
REVOKE SELECT, UPDATE, DELETE ON auth.user FROM authenticated;
REVOKE SELECT, UPDATE, DELETE ON auth.refresh_session FROM authenticated;

-- 5. Revoke schema usage grants
REVOKE USAGE ON SCHEMA auth FROM authenticator; -- Added
REVOKE USAGE ON SCHEMA auth FROM authenticated, anon;

-- 6. Revoke role membership grants
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

-- 8. Drop public view
DROP VIEW IF EXISTS public.api_key;

-- 9. Drop triggers
DROP TRIGGER IF EXISTS generate_api_key_token_trigger ON auth.api_key;
DROP TRIGGER IF EXISTS drop_user_role_trigger ON auth.user;
DROP TRIGGER IF EXISTS sync_user_credentials_and_roles_trigger ON auth.user;
DROP TRIGGER IF EXISTS check_role_permission_trigger ON auth.user;

-- 10. Drop RLS policies
-- Policies on auth.api_key
DROP POLICY IF EXISTS delete_own_api_keys ON auth.api_key;
DROP POLICY IF EXISTS revoke_own_api_keys ON auth.api_key;
DROP POLICY IF EXISTS insert_own_api_keys ON auth.api_key;
DROP POLICY IF EXISTS select_own_api_keys ON auth.api_key;
-- Policies on auth.user
DROP POLICY IF EXISTS admin_all_access ON auth.user;
DROP POLICY IF EXISTS update_own_user ON auth.user;
DROP POLICY IF EXISTS select_own_user ON auth.user;
-- Policies on auth.refresh_session
DROP POLICY IF EXISTS admin_all_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS delete_own_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS update_own_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS insert_own_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS select_own_refresh_sessions ON auth.refresh_session;

-- 11. Disable RLS
ALTER TABLE auth.api_key DISABLE ROW LEVEL SECURITY; -- Added
ALTER TABLE auth.user DISABLE ROW LEVEL SECURITY; -- Added
ALTER TABLE auth.refresh_session DISABLE ROW LEVEL SECURITY; -- Added

-- 12. Drop auth functions (reverse order)
DROP FUNCTION IF EXISTS auth.check_api_key_revocation();
DROP FUNCTION IF EXISTS auth.generate_api_key_token();
DROP FUNCTION IF EXISTS auth.extract_access_token_from_cookies();
DROP FUNCTION IF EXISTS auth.reset_session_context();
DROP FUNCTION IF EXISTS auth.generate_jwt(jsonb);
DROP FUNCTION IF EXISTS auth.set_user_context_from_email(text);
DROP FUNCTION IF EXISTS auth.extract_refresh_token_from_cookies();
DROP FUNCTION IF EXISTS auth.use_jwt_claims_in_session(jsonb);
DROP FUNCTION IF EXISTS auth.build_jwt_claims(text, timestamptz, text, jsonb);
DROP FUNCTION IF EXISTS auth.build_auth_response(auth.user, jsonb);
DROP FUNCTION IF EXISTS auth.switch_role_from_jwt(text); -- Added
DROP FUNCTION IF EXISTS auth.clear_auth_cookies();
DROP FUNCTION IF EXISTS auth.set_auth_cookies(text, text, timestamptz, timestamptz);
-- Note: auth.clear_auth_cookies() is now explicitly dropped above if it was added to REVOKE list.
-- If it wasn't added to REVOKE list, this explicit drop is still good.
-- Ensuring it's dropped (removed duplicate from here):
DROP FUNCTION IF EXISTS auth.drop_user_role();
DROP FUNCTION IF EXISTS auth.sync_user_credentials_and_roles();
DROP FUNCTION IF EXISTS auth.check_role_permission();
DROP FUNCTION IF EXISTS auth.cleanup_expired_sessions();
DROP FUNCTION IF EXISTS auth.statbus_role();
DROP FUNCTION IF EXISTS auth.email();
DROP FUNCTION IF EXISTS auth.role();
DROP FUNCTION IF EXISTS auth.uid();
DROP FUNCTION IF EXISTS auth.sub();
DROP FUNCTION IF EXISTS auth.get_request_ip();

-- 13. Drop indexes
DROP INDEX IF EXISTS auth.api_key_user_id_idx; -- Added
DROP INDEX IF EXISTS auth.refresh_session_expires_at_idx; -- Added
DROP INDEX IF EXISTS auth.refresh_session_user_id_idx; -- Added

-- 14. Drop tables
DROP TABLE IF EXISTS auth.api_key;
DROP TABLE IF EXISTS auth.refresh_session;
DROP TABLE IF EXISTS auth.user; -- Drops auth.user type implicitly

-- 15. Drop auth types
DROP TYPE IF EXISTS auth.auth_test_response;
DROP TYPE IF EXISTS auth.token_info;
DROP TYPE IF EXISTS auth.auth_response;
DROP TYPE IF EXISTS auth.session_info;
DROP TYPE IF EXISTS auth.logout_response;

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

-- 17. Drop hierarchy roles
SET client_min_messages TO DEBUG2;
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

-- 18. Drop public type
DROP TYPE IF EXISTS public.statbus_role;

-- 19. Drop domain
DROP DOMAIN IF EXISTS "application/json";

-- 20. Drop schema
DROP SCHEMA IF EXISTS auth;

-- Drop test-specific schema and functions
DROP FUNCTION IF EXISTS auth_test.reset_request_gucs();
DROP SCHEMA IF EXISTS auth_test;

COMMIT;

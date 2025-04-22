-- Down Migration: Remove auth schema tables
BEGIN;

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

-- Drop the public view for API keys with security_invoker=true
DROP VIEW IF EXISTS public.api_key;

-- Drop the trigger for API key token generation
DROP TRIGGER IF EXISTS generate_api_key_token_trigger ON auth.api_key;

-- Revoke execute permissions on functions
REVOKE EXECUTE ON FUNCTION public.logout() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.login FROM anon;
REVOKE EXECUTE ON FUNCTION public.refresh FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.list_active_sessions FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.revoke_session FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.auth_status FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.auth_test FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.create_api_key(text, interval) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.change_password(text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_change_password(uuid, text) FROM admin_user;
REVOKE EXECUTE ON FUNCTION public.revoke_api_key(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.check_api_key_revocation() FROM authenticated;

-- Revoke schema usage
REVOKE USAGE ON SCHEMA auth FROM anon, authenticated;

-- Revoke table permissions
REVOKE SELECT, UPDATE (description, revoked_at), DELETE ON auth.api_key FROM authenticated;
REVOKE USAGE ON SEQUENCE auth.api_key_id_seq FROM authenticated;
REVOKE SELECT, UPDATE, DELETE ON auth.user FROM authenticated;

-- Revoke execute permissions on auth helper functions
REVOKE EXECUTE ON FUNCTION auth.uid FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth.role FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth.email FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth.statbus_role FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth.sub FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth.build_jwt_claims FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.use_jwt_claims_in_session FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.set_user_context_from_email FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.reset_session_context FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.build_auth_response FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.set_auth_cookies FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.extract_refresh_token_from_cookies FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.extract_access_token_from_cookies FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.generate_jwt FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.clear_auth_cookies FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.check_api_key_revocation() FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.generate_api_key_token() FROM authenticated;

-- Revoke pg_monitor from admin role
REVOKE pg_monitor FROM admin_user;

-- Drop public functions first
DROP FUNCTION IF EXISTS public.auth_test();
DROP FUNCTION IF EXISTS public.auth_status();
DROP FUNCTION IF EXISTS public.revoke_session(uuid);
DROP FUNCTION IF EXISTS public.list_active_sessions();
DROP FUNCTION IF EXISTS public.logout();
DROP FUNCTION IF EXISTS public.refresh();
DROP FUNCTION IF EXISTS public.login(text, text);
DROP FUNCTION IF EXISTS public.create_api_key(text, interval);
DROP FUNCTION IF EXISTS public.change_password(text);
DROP FUNCTION IF EXISTS public.admin_change_password(uuid, text);
DROP FUNCTION IF EXISTS public.revoke_api_key(uuid);

-- Drop triggers before dropping the functions they use or the table they are on
DROP TRIGGER IF EXISTS drop_user_role_trigger ON auth.user;
DROP TRIGGER IF EXISTS sync_user_credentials_and_roles_trigger ON auth.user;
DROP TRIGGER IF EXISTS check_role_permission_trigger ON auth.user;

-- Drop auth functions first (including trigger functions and cleanup)
DROP FUNCTION IF EXISTS auth.cleanup_expired_sessions();
DROP FUNCTION IF EXISTS auth.sync_user_credentials_and_roles(); -- Renamed function
DROP FUNCTION IF EXISTS auth.check_role_permission(); -- Renamed function
DROP FUNCTION IF EXISTS auth.drop_user_role();
DROP FUNCTION IF EXISTS auth.clear_auth_cookies();
DROP FUNCTION IF EXISTS auth.extract_access_token_from_cookies();
DROP FUNCTION IF EXISTS auth.reset_session_context();
DROP FUNCTION IF EXISTS auth.generate_jwt(jsonb);
DROP FUNCTION IF EXISTS auth.extract_refresh_token_from_cookies();
DROP FUNCTION IF EXISTS auth.check_api_key_revocation();
DROP FUNCTION IF EXISTS auth.generate_api_key_token();
-- Drop build_auth_response earlier as it depends on the auth.user type
DROP FUNCTION IF EXISTS auth.build_auth_response(text, text, auth.user);
DROP FUNCTION IF EXISTS auth.set_user_context_from_email(text);
DROP FUNCTION IF EXISTS auth.use_jwt_claims_in_session(jsonb);
DROP FUNCTION IF EXISTS auth.build_jwt_claims(p_email text, p_expires_at timestamptz, p_type text, p_additional_claims jsonb);
-- Corrected signature for set_auth_cookies
DROP FUNCTION IF EXISTS auth.set_auth_cookies(text, text, timestamptz, timestamptz);
DROP FUNCTION IF EXISTS auth.statbus_role();
DROP FUNCTION IF EXISTS auth.email();
DROP FUNCTION IF EXISTS auth.role();
DROP FUNCTION IF EXISTS auth.sub();

-- Drop RLS policies before dropping the functions they depend on (like auth.uid)
-- Policies on auth.refresh_session
DROP POLICY IF EXISTS admin_all_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS delete_own_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS update_own_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS insert_own_refresh_sessions ON auth.refresh_session;
DROP POLICY IF EXISTS select_own_refresh_sessions ON auth.refresh_session;

-- No need to drop policies on public.api_key view as they're automatically dropped with the view

-- Policies on auth.api_key
DROP POLICY IF EXISTS delete_own_api_keys ON auth.api_key;
DROP POLICY IF EXISTS revoke_own_api_keys ON auth.api_key;
DROP POLICY IF EXISTS select_own_api_keys ON auth.api_key;
DROP POLICY IF EXISTS insert_own_api_keys ON auth.api_key;

-- Policies on auth.user (depend on pg_has_role, not auth.uid/sub)
DROP POLICY IF EXISTS admin_all_access ON auth.user;
DROP POLICY IF EXISTS update_own_user ON auth.user;
DROP POLICY IF EXISTS select_own_user ON auth.user;

-- Now it's safe to drop auth.uid()
DROP FUNCTION IF EXISTS auth.uid();

-- Drop tables in reverse order of dependency (api_key -> user, refresh_session -> user)
DROP TABLE IF EXISTS auth.api_key;
DROP TABLE IF EXISTS auth.refresh_session;
DROP TABLE IF EXISTS auth.user; -- Drop user table last among auth tables

-- Now drop types (auth.user type is implicitly dropped with the table)
DROP TYPE IF EXISTS auth.auth_test_response;
DROP TYPE IF EXISTS auth.token_info;
-- Duplicate DROP TYPE removed
DROP TYPE IF EXISTS auth.auth_status_response;
DROP TYPE IF EXISTS auth.session_info;
DROP TYPE IF EXISTS auth.logout_response;
DROP TYPE IF EXISTS auth.auth_response; -- This type uses auth.user, ensure it's dropped after the function using it

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
  LOOP
    -- For each role, revoke memberships and drop it
    BEGIN
      EXECUTE format('REVOKE authenticated FROM %I', role_record.rolname);
      EXECUTE format('REVOKE admin_user FROM %I', role_record.rolname);
      EXECUTE format('REVOKE regular_user FROM %I', role_record.rolname);
      EXECUTE format('REVOKE restricted_user FROM %I', role_record.rolname);
      EXECUTE format('REVOKE external_user FROM %I', role_record.rolname);
      EXECUTE format('DROP ROLE IF EXISTS %I', role_record.rolname);
    EXCEPTION WHEN OTHERS THEN
      -- Ignore errors, continue with next role
      RAISE NOTICE 'Could not drop role %: %', role_record.rolname, SQLERRM;
    END;
  END LOOP;
END
$$;

-- Handle role dependencies with a simpler approach
DO $$
BEGIN
  -- Revoke role hierarchy first
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
    EXECUTE 'REVOKE regular_user FROM admin_user';
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'regular_user') THEN
    EXECUTE 'REVOKE restricted_user FROM regular_user';
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'restricted_user') THEN
    EXECUTE 'REVOKE external_user FROM restricted_user';
  END IF;
  
  -- Revoke permissions from specific schemas
  BEGIN
    EXECUTE 'REVOKE ALL ON SCHEMA public FROM admin_user, regular_user, restricted_user, external_user';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error revoking schema permissions: %', SQLERRM;
  END;
  
  BEGIN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM admin_user, regular_user, restricted_user, external_user';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error revoking table permissions: %', SQLERRM;
  END;
  
  BEGIN
    EXECUTE 'REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM admin_user, regular_user, restricted_user, external_user';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error revoking sequence permissions: %', SQLERRM;
  END;
  
  BEGIN
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM admin_user, regular_user, restricted_user, external_user';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error revoking function permissions: %', SQLERRM;
  END;
  
  -- Now try to drop the roles in reverse order of hierarchy
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'external_user') THEN
    BEGIN
      EXECUTE 'DROP ROLE IF EXISTS external_user';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not drop role external_user: %', SQLERRM;
    END;
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'restricted_user') THEN
    BEGIN
      EXECUTE 'DROP ROLE IF EXISTS restricted_user';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not drop role restricted_user: %', SQLERRM;
    END;
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'regular_user') THEN
    BEGIN
      EXECUTE 'DROP ROLE IF EXISTS regular_user';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not drop role regular_user: %', SQLERRM;
    END;
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
    BEGIN
      EXECUTE 'DROP ROLE IF EXISTS admin_user';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not drop role admin_user: %', SQLERRM;
    END;
  END IF;
END
$$;

-- Now we can safely drop the type
DROP TYPE IF EXISTS public.statbus_role;

-- Drop the domain type
DROP DOMAIN IF EXISTS "application/json";

-- Drop auth schema
DROP SCHEMA IF EXISTS auth;

COMMIT;

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

-- Revoke execute permissions on functions
REVOKE EXECUTE ON FUNCTION public.logout() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.login FROM anon;
REVOKE EXECUTE ON FUNCTION public.refresh FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.grant_role FROM admin_user;
REVOKE EXECUTE ON FUNCTION public.revoke_role FROM admin_user;
REVOKE EXECUTE ON FUNCTION public.list_active_sessions FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.revoke_session FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.auth_status FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.auth_test FROM anon, authenticated;

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
REVOKE EXECUTE ON FUNCTION auth.extract_access_token_from_cookies FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION auth.generate_jwt FROM authenticated;
REVOKE EXECUTE ON FUNCTION auth.clear_auth_cookies FROM authenticated;

-- Revoke pg_monitor from admin role
REVOKE pg_monitor FROM admin_user;

-- Drop types
DROP TYPE IF EXISTS auth.auth_test_response;
DROP TYPE IF EXISTS auth.token_info;
DROP TYPE IF EXISTS auth.auth_status_response;
DROP TYPE IF EXISTS auth.session_info;
DROP TYPE IF EXISTS auth.logout_response;
DROP TYPE IF EXISTS auth.auth_response;

-- Drop public functions
DROP FUNCTION IF EXISTS public.auth_test();
DROP FUNCTION IF EXISTS public.auth_status();
DROP FUNCTION IF EXISTS public.revoke_session(uuid);
DROP FUNCTION IF EXISTS public.list_active_sessions();
DROP FUNCTION IF EXISTS public.revoke_role(uuid);
DROP FUNCTION IF EXISTS public.grant_role(uuid, public.statbus_role);
DROP FUNCTION IF EXISTS public.logout();
DROP FUNCTION IF EXISTS public.refresh();
DROP FUNCTION IF EXISTS public.login(text, text);

-- Drop auth functions
DROP FUNCTION IF EXISTS auth.clear_auth_cookies();
DROP FUNCTION IF EXISTS auth.extract_access_token_from_cookies();
DROP FUNCTION IF EXISTS auth.reset_session_context();
DROP FUNCTION IF EXISTS auth.generate_jwt(jsonb);
DROP FUNCTION IF EXISTS auth.extract_refresh_token_from_cookies();
DROP FUNCTION IF EXISTS auth.build_auth_response(text, text, integer, text, public.statbus_role);
DROP FUNCTION IF EXISTS auth.set_user_context_from_email(text);
DROP FUNCTION IF EXISTS auth.use_jwt_claims_in_session(jsonb);
DROP FUNCTION IF EXISTS auth.build_jwt_claims(text, uuid, public.statbus_role, timestamptz, text, jsonb);
DROP FUNCTION IF EXISTS auth.set_auth_cookies(text, text, timestamptz, timestamptz, integer, text);
DROP FUNCTION IF EXISTS auth.statbus_role();
DROP FUNCTION IF EXISTS auth.email();
DROP FUNCTION IF EXISTS auth.role();
DROP FUNCTION IF EXISTS auth.sub();
DROP FUNCTION IF EXISTS auth.uid();
DROP FUNCTION IF EXISTS auth.cleanup_expired_sessions();

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

-- Drop the trigger that drops user roles
DROP TRIGGER IF EXISTS drop_user_role_trigger ON auth.user;

-- Drop the function that drops user roles
DROP FUNCTION IF EXISTS auth.drop_user_role();

-- Drop the trigger that creates user roles
DROP TRIGGER IF EXISTS create_user_role_trigger ON auth.user;

-- Drop the function that creates user roles
DROP FUNCTION IF EXISTS auth.create_user_role();

-- Drop tables in reverse order to handle dependencies
DROP TABLE IF EXISTS auth.refresh_session;
DROP TABLE IF EXISTS auth.user;

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

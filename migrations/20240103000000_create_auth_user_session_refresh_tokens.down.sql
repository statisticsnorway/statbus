-- Down Migration: Remove auth schema tables
BEGIN;

-- Drop role management functions that depend on statbus_role_type
DROP FUNCTION IF EXISTS public.grant_role(uuid, text);
DROP FUNCTION IF EXISTS public.revoke_role(uuid);

-- Drop auth functions
DROP FUNCTION IF EXISTS auth.uid();
DROP FUNCTION IF EXISTS auth.role();
DROP FUNCTION IF EXISTS auth.email();
DROP FUNCTION IF EXISTS auth.statbus_role();
DROP FUNCTION IF EXISTS auth.sub();
DROP FUNCTION IF EXISTS auth.uuid();
DROP FUNCTION IF EXISTS public.login(text, text);
DROP FUNCTION IF EXISTS public.refresh();
DROP FUNCTION IF EXISTS public.list_active_sessions();
DROP FUNCTION IF EXISTS public.revoke_session(uuid);
DROP FUNCTION IF EXISTS auth.set_auth_cookies(text, text, timestamptz, timestamptz, integer, text);
DROP FUNCTION IF EXISTS auth.clear_auth_cookies();
DROP FUNCTION IF EXISTS auth.extract_refresh_token_from_cookies();
DROP FUNCTION IF EXISTS auth.build_auth_response(text, text, integer, text, public.statbus_role);
DROP FUNCTION IF EXISTS auth.generate_jwt(jsonb);

-- Revoke execute permission on logout function
REVOKE EXECUTE ON FUNCTION public.logout() FROM authenticated;

-- Drop the logout function
DROP FUNCTION IF EXISTS public.logout();

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

-- Drop function for session cleanup
DROP FUNCTION IF EXISTS auth.cleanup_expired_sessions();

-- Drop tables in reverse order to handle dependencies
DROP TABLE IF EXISTS auth.refresh_session;
DROP TABLE IF EXISTS auth.user;

-- Drop the new function
DROP FUNCTION IF EXISTS auth.uuid();

-- Drop PostgreSQL roles in reverse order of hierarchy
DO $$
BEGIN
  -- Revoke role hierarchy first
  EXECUTE 'REVOKE regular_user FROM admin_user';
  EXECUTE 'REVOKE restricted_user FROM regular_user';
  EXECUTE 'REVOKE external_user FROM restricted_user';
  
  -- Drop the roles
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
    EXECUTE 'DROP ROLE IF EXISTS admin_user';
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'regular_user') THEN
    EXECUTE 'DROP ROLE IF EXISTS regular_user';
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'restricted_user') THEN
    EXECUTE 'DROP ROLE IF EXISTS restricted_user';
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'external_user') THEN
    EXECUTE 'DROP ROLE IF EXISTS external_user';
  END IF;
END
$$;

-- Now we can safely drop the type
DROP TYPE IF EXISTS public.statbus_role;

-- Drop auth schema
DROP SCHEMA IF EXISTS auth;

COMMIT;

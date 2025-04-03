-- Migration: Make view for user editing
BEGIN;

-- Create a view to manage users and their roles
CREATE VIEW public.user_with_role WITH (security_barrier = true) AS
SELECT
    u.id,
    u.email,
    u.statbus_role
FROM
    auth.user u;

-- Check if current user is a system account with database privileges
CREATE FUNCTION auth.check_is_system_account() RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = current_user
    AND rolbypassrls = true
  );
END;
$$ LANGUAGE plpgsql;

-- Check if current user has application-level admin role
CREATE FUNCTION auth.check_is_admin_user() RETURNS boolean 
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM auth.user 
    WHERE id = auth.uid()
    AND pg_has_role(email, 'admin_user', 'member')
  );
$$;

-- Combined check for either system account or admin user
CREATE FUNCTION auth.assert_is_admin_user_or_system_account() RETURNS void AS $$
BEGIN
  IF NOT (auth.check_is_system_account() OR auth.check_is_admin_user()) THEN
    RAISE EXCEPTION 'Only admin users or system accounts can perform this action';
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION auth.check_is_system_account TO authenticated;
GRANT EXECUTE ON FUNCTION auth.check_is_admin_user TO authenticated;
GRANT EXECUTE ON FUNCTION auth.assert_is_admin_user_or_system_account TO authenticated;

-- Create test schema for test helpers
CREATE SCHEMA IF NOT EXISTS test;

-- Helper to automatically set request.jwt.claim.sub for testing
CREATE OR REPLACE PROCEDURE test.set_user_from_email(p_email text) AS $$
DECLARE
    v_user auth.user;
    v_claims jsonb;
BEGIN
    SELECT * INTO v_user
    FROM auth.user
    WHERE email = p_email;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User with email % not found', p_email;
    END IF;

    -- Set role for the current transaction
    EXECUTE format('SET LOCAL ROLE %I;', v_user.email);
    
    -- Create a complete claims object as jsonb
    v_claims := jsonb_build_object(
        'role', v_user.email,
        'statbus_role', v_user.statbus_role,
        'sub', v_user.sub::text,
        'email', v_user.email,
        'type', 'access',
        'exp', extract(epoch from (now() + interval '1 hour'))::integer
    );
    
    -- Set the complete claims object
    EXECUTE format('SET LOCAL "request.jwt.claims" TO %L;', v_claims::text);
    
    -- Also set individual claims for backward compatibility
    EXECUTE format('SET LOCAL "request.jwt.claim.sub" TO %L;', v_user.sub);
    EXECUTE format('SET LOCAL "request.jwt.claim.role" TO %L;', v_user.email);
    EXECUTE format('SET LOCAL "request.jwt.claim.statbus_role" TO %L;', v_user.statbus_role);
    EXECUTE format('SET LOCAL "request.jwt.claim.email" TO %L;', v_user.email);
    
    -- For debugging
    RAISE DEBUG 'Set user context: email=%, role=%, statbus_role=%', 
                 v_user.email, v_user.email, v_user.statbus_role;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON PROCEDURE test.set_user_from_email TO authenticated;
GRANT USAGE ON SCHEMA test TO authenticated;

-- Trigger function to handle user role updates
CREATE FUNCTION admin.trigger_update_user_with_role()
RETURNS TRIGGER AS $$
BEGIN
    RAISE DEBUG 'Trigger executing for user: %, session user: %, current user: %',
                auth.uid(), session_user, current_user;
    RAISE DEBUG 'Attempting to update role from % to % for email %',
                OLD.statbus_role, NEW.statbus_role, NEW.email;
    RAISE DEBUG 'Checking system account: %', auth.check_is_system_account();
    RAISE DEBUG 'Checking admin user: %', auth.check_is_admin_user();

    PERFORM auth.assert_is_admin_user_or_system_account();

    PERFORM public.user_update_role(OLD.email, NEW.statbus_role);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for the view
CREATE TRIGGER update_user_with_role
    INSTEAD OF UPDATE ON public.user_with_role
    FOR EACH ROW
    EXECUTE FUNCTION admin.trigger_update_user_with_role();

-- Helper function to handle the actual role update
CREATE FUNCTION public.user_update_role(
    p_email text,
    p_statbus_role public.statbus_role
) RETURNS void AS $$
DECLARE
    v_user_id integer;
    v_current_role public.statbus_role;
BEGIN
    -- Get the user ID and current role
    SELECT id, statbus_role INTO v_user_id, v_current_role
    FROM auth.user
    WHERE email = p_email;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User with email % not found', p_email;
    END IF;

    -- Revoke the old role from the user's PostgreSQL role
    EXECUTE format('REVOKE %I FROM %I', v_current_role::text, p_email);

    -- Grant the new role to the user's PostgreSQL role
    EXECUTE format('GRANT %I TO %I', p_statbus_role::text, p_email);

    -- Update the user record
    UPDATE auth.user
    SET statbus_role = p_statbus_role,
        updated_at = now()
    WHERE id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant appropriate permissions
GRANT SELECT ON public.user_with_role TO authenticated;
GRANT UPDATE ON public.user_with_role TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_update_role TO authenticated;

-- Function to create a new user
CREATE FUNCTION public.user_create(
    p_email text,
    p_statbus_role public.statbus_role,
    p_password text DEFAULT NULL
) RETURNS TABLE (
    email text,
    password text
)
    LANGUAGE plpgsql
    SECURITY DEFINER
AS $$
DECLARE
    v_password text;
    v_user_id integer;
    v_encrypted_password text;
    v_email text;
BEGIN
    -- Ensure email is lowercase
    v_email := lower(p_email);

    -- Check if the caller has permission
    PERFORM auth.assert_is_admin_user_or_system_account();

    -- Use provided password or generate a secure random one
    IF p_password IS NULL THEN
        SELECT string_agg(substr('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*', ceil(random()*75)::integer, 1), '')
        FROM generate_series(1, 12)
        INTO v_password;
    ELSE
        v_password := p_password;
    END IF;

    -- Insert or update auth.user
    INSERT INTO auth.user (
        email,
        password,
        statbus_role,
        email_confirmed_at
    ) VALUES (
        v_email, -- email
        v_password, -- password (will be encrypted by trigger)
        p_statbus_role, -- statbus_role
        now() -- email_confirmed_at
    )
    ON CONFLICT ON CONSTRAINT user_email_key DO UPDATE
    SET
        password = v_password, -- Will be encrypted by trigger
        statbus_role = EXCLUDED.statbus_role,
        email_confirmed_at = EXCLUDED.email_confirmed_at
    RETURNING id INTO v_user_id;

    -- Return the email and password
    RETURN QUERY SELECT v_email::text, v_password::text;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.user_create TO authenticated;

END;

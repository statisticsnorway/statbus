-- Migration: Make view for user editing
BEGIN;

-- Create a view to manage users and their roles
-- This view is automatically updatable for email, statbus_role, and password.
-- Selecting password returns NULL by desing of auth.user, but it can be updated (trigger handles encryption).
CREATE VIEW public.user WITH (security_barrier = true) AS
SELECT u.id
     , u.sub
     , u.email
     , u.password
     , u.statbus_role
     , u.created_at
     , u.updated_at
     , u.last_sign_in_at
     , u.email_confirmed_at
     , u.deleted_at
FROM
    auth.user u;

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

-- Grant appropriate permissions
-- The view allows SELECT for authenticated users.
-- Updates to email and statbus_role are allowed for authenticated users,
-- relying on RLS policies on auth.user and the auth triggers
-- (check_role_permission_trigger, sync_user_credentials_and_roles_trigger).
GRANT SELECT ON public.user TO authenticated;
GRANT UPDATE (email, statbus_role, password) ON public.user TO authenticated;

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
    SECURITY INVOKER -- Run as the calling user; RLS on auth.user handles permissions.
AS $$
DECLARE
    v_password text;
    v_user_id integer;
    v_encrypted_password text;
    v_email text;
BEGIN
    -- Ensure email is lowercase
    v_email := lower(p_email);

    -- Use provided password or generate a secure random one
    -- The RLS policy 'admin_all_access' on auth.user ensures only admins can INSERT/UPDATE.
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
        password, -- Plain text password; will be encrypted by the sync_user_credentials_and_roles_trigger
        statbus_role,
        email_confirmed_at
    ) VALUES (
        v_email,
        v_password,
        p_statbus_role,
        clock_timestamp() -- email_confirmed_at (set immediately for new users via this function)
    )
    -- Specify the constraint name to resolve ambiguity.
    ON CONFLICT ON CONSTRAINT user_email_key DO UPDATE
    SET
        password = EXCLUDED.password, -- Pass on the NULL password.
        encrypted_password = EXCLUDED.encrypted_password, -- The EXCLUDED.password is cleared by a before trigger that populated EXCLUDED.encrypted_password
        statbus_role = EXCLUDED.statbus_role,
        email_confirmed_at = COALESCE(auth.user.email_confirmed_at, EXCLUDED.email_confirmed_at), -- Don't reset confirmation
        updated_at = clock_timestamp() -- Explicitly set updated_at on conflict
    RETURNING id INTO v_user_id;

    -- Return the email and password
    RETURN QUERY SELECT v_email::text, v_password::text;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.user_create TO authenticated;

END;

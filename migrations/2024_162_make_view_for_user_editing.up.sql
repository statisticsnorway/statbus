-- Migration 0003: Make view for user editing
BEGIN;

-- Add unique constraint for email
ALTER TABLE auth.users
ADD CONSTRAINT users_email_key
UNIQUE (email);

CREATE VIEW statbus_user_with_email_and_role WITH (security_barrier = true) AS
SELECT
    au.email,
    sr.type AS role_type
FROM
    auth.users au
JOIN
    public.statbus_user su ON au.id = su.uuid
JOIN
    public.statbus_role sr ON su.role_id = sr.id;

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

-- Check if current user has application-level super user role
CREATE FUNCTION auth.check_is_super_user() RETURNS boolean AS $$
BEGIN
  RETURN (auth.uid() IS NOT NULL)
    AND auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Combined check for either system account or super user
CREATE FUNCTION auth.assert_is_super_user_or_system_account() RETURNS void AS $$
BEGIN
  IF NOT (auth.check_is_system_account() OR auth.check_is_super_user()) THEN
    RAISE EXCEPTION 'Only super users or system accounts can perform this action';
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION auth.check_is_system_account TO authenticated;
GRANT EXECUTE ON FUNCTION auth.check_is_super_user TO authenticated;
GRANT EXECUTE ON FUNCTION auth.assert_is_super_user_or_system_account TO authenticated;

-- Create test schema for test helpers
CREATE SCHEMA IF NOT EXISTS test;

-- Helper to automatically set request.jwt.claim.sub for testing
CREATE PROCEDURE test.set_user_from_email(p_email text) AS $$
DECLARE
    v_user_id text;
BEGIN
    SELECT id::text INTO v_user_id
    FROM auth.users
    WHERE email = p_email;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User with email % not found', p_email;
    END IF;

    SET LOCAL ROLE authenticated;
    EXECUTE 'SET LOCAL "request.jwt.claim.sub" TO ''' || v_user_id || '''';
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON PROCEDURE test.set_user_from_email TO authenticated;
GRANT USAGE ON SCHEMA test TO authenticated;

CREATE FUNCTION trigger_update_statbus_user_with_email_and_role()
RETURNS TRIGGER AS $$
BEGIN
    RAISE DEBUG 'Trigger executing for user: %, session user: %, current user: %',
                auth.uid(), session_user, current_user;
    RAISE DEBUG 'Attempting to update role from % to % for email %',
                OLD.role_type, NEW.role_type, NEW.email;
    RAISE DEBUG 'Checking system account: %', auth.check_is_system_account();
    RAISE DEBUG 'Checking super user: %', auth.check_is_super_user();

    PERFORM auth.assert_is_super_user_or_system_account();

    PERFORM public.statbus_user_update_role(OLD.email, NEW.role_type);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_statbus_user_with_email_and_role
    INSTEAD OF UPDATE ON statbus_user_with_email_and_role
    FOR EACH ROW
    EXECUTE FUNCTION trigger_update_statbus_user_with_email_and_role();

-- Helper function to handle the actual update
CREATE FUNCTION public.statbus_user_update_role(
    p_email text,
    p_role_type statbus_role_type
) RETURNS void AS $$
BEGIN
    UPDATE public.statbus_user
    SET role_id = (SELECT id FROM public.statbus_role WHERE type = p_role_type)
    WHERE uuid IN (
        SELECT au.id
        FROM auth.users au
        WHERE au.email = p_email
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant appropriate permissions
GRANT SELECT ON statbus_user_with_email_and_role TO authenticated;
GRANT UPDATE ON statbus_user_with_email_and_role TO authenticated;
GRANT EXECUTE ON FUNCTION public.statbus_user_update_role TO authenticated;

CREATE FUNCTION public.statbus_user_create(
    p_email text,
    p_role_type statbus_role_type,
    p_password text DEFAULT NULL
) RETURNS TABLE (
    email text,
    password text
)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
AS $$
DECLARE
    v_password text;
    v_user_id uuid;
    v_encrypted_password text;
    v_role_id integer;
    v_email text;
BEGIN
    -- Ensure email is lowercase
    v_email := lower(p_email);
    PERFORM auth.assert_is_super_user_or_system_account();

    -- Use provided password or generate a secure random one
    IF p_password IS NULL THEN
        SELECT string_agg(substr('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*', ceil(random()*75)::integer, 1), '')
        FROM generate_series(1, 12)
        INTO v_password;
    ELSE
        v_password := p_password;
    END IF;

    -- Get encrypted password using pgcrypto with bcrypt (Supabase format)
    SELECT extensions.crypt(v_password, extensions.gen_salt('bf', 10)) INTO v_encrypted_password;

    -- Generate UUID for new user
    SELECT gen_random_uuid() INTO v_user_id;

    -- Get role_id for the specified role_type
    SELECT id INTO v_role_id
    FROM public.statbus_role
    WHERE type = p_role_type;

    IF v_role_id IS NULL THEN
        RAISE EXCEPTION 'Invalid role_type: %', p_role_type;
    END IF;

    -- Insert or update auth.users
    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        phone_confirmed_at,
        recovery_sent_at,
        last_sign_in_at,
        confirmation_sent_at,
        confirmation_token,
        email_change,
        email_change_token_new,
        recovery_token,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        is_sso_user,
        is_anonymous
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', -- instance_id -- For use with multiple installations, and NULL would have been a better absent marker.
        v_user_id, -- id
        'authenticated', -- aud
        'authenticated', -- role
        v_email, -- email
        v_encrypted_password, -- encrypted_password
        now(), -- email_confirmed_at
        NULL, -- phone_confirmed_at
        NULL, -- recovery_sent_at
        NULL, -- last_sign_in_at
        NULL, -- confirmation_sent_at
        '', -- confirmation_token
        '', -- email_change
        '', -- email_change_token_new
        '', -- recovery_token
        '{"provider": "email", "providers": ["email"]}'::jsonb, -- raw_app_meta_data
        '{}'::jsonb, -- raw_user_meta_data
        now(), -- created_at
        now(), -- updated_at
        false, -- is_sso_user
        false -- is_anonymous
    )
    ON CONFLICT ON CONSTRAINT "users_email_key" DO UPDATE
    SET
        encrypted_password = EXCLUDED.encrypted_password,
        updated_at = now(),
        email_confirmed_at = EXCLUDED.email_confirmed_at,
        raw_app_meta_data = EXCLUDED.raw_app_meta_data
    RETURNING id INTO v_user_id;

    -- Insert or update auth.identities
    INSERT INTO auth.identities (
        provider_id,
        user_id,
        identity_data,
        provider,
        created_at,
        updated_at
    ) VALUES (
        v_user_id, -- provider_id -- Same as user_id if email is provider
        v_user_id, -- user_id
        json_build_object(
            'sub', v_user_id,
            'email', v_email,
            'email_verified', false,
            'phone_verified', false
        ), -- identity_data
        'email', -- provider
        now(), -- created_at
        now() -- updated_at
    )
    ON CONFLICT ON CONSTRAINT identities_provider_id_provider_unique DO UPDATE
    SET
        identity_data = EXCLUDED.identity_data,
        updated_at = now();

    -- statbus_user will be created automatically via the on_auth_user_created trigger
    -- Update the role_id
    UPDATE public.statbus_user
    SET role_id = v_role_id
    WHERE uuid = v_user_id;

    RETURN QUERY SELECT v_email::text, v_password::text;
END;
$$;

-- Only grant execute to authenticated, but function checks for super_user role internally
GRANT EXECUTE ON FUNCTION public.statbus_user_create TO authenticated;


END;

```sql
CREATE OR REPLACE FUNCTION public.user_create(p_display_name text, p_email text, p_statbus_role statbus_role, p_password text DEFAULT NULL::text)
 RETURNS TABLE(email text, password text)
 LANGUAGE plpgsql
AS $function$
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
        display_name,
        email,
        password, -- Plain text password; will be encrypted by the sync_user_credentials_and_roles_trigger
        statbus_role,
        email_confirmed_at
    ) VALUES (
        p_display_name,
        v_email,
        v_password,
        p_statbus_role,
        clock_timestamp() -- email_confirmed_at (set immediately for new users via this function)
    )
    -- Specify the constraint name to resolve ambiguity.
    ON CONFLICT ON CONSTRAINT user_email_key DO UPDATE
    SET
        display_name = EXCLUDED.display_name,
        password = EXCLUDED.password, -- Pass on the NULL password.
        encrypted_password = EXCLUDED.encrypted_password, -- The EXCLUDED.password is cleared by a before trigger that populated EXCLUDED.encrypted_password
        statbus_role = EXCLUDED.statbus_role,
        email_confirmed_at = COALESCE(auth.user.email_confirmed_at, EXCLUDED.email_confirmed_at), -- Don't reset confirmation
        updated_at = clock_timestamp() -- Explicitly set updated_at on conflict
    RETURNING id INTO v_user_id;

    -- Return the email and password
    RETURN QUERY SELECT v_email::text, v_password::text;
END;
$function$
```

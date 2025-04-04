```sql
CREATE OR REPLACE FUNCTION public.user_create(p_email text, p_statbus_role statbus_role, p_password text DEFAULT NULL::text)
 RETURNS TABLE(email text, password text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
```

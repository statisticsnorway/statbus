```sql
CREATE OR REPLACE FUNCTION public.user_update_role(p_email text, p_statbus_role statbus_role)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
```

```sql
CREATE OR REPLACE PROCEDURE auth.set_request_user_by_email(IN p_email text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $procedure$
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
$procedure$
```

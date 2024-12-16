```sql
CREATE OR REPLACE PROCEDURE auth.set_request_user(IN p_user_id uuid)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    SET LOCAL ROLE authenticated;
    EXECUTE 'SET LOCAL "request.jwt.claim.sub" TO ''' || p_user_id::text || '''';
END;
$procedure$
```

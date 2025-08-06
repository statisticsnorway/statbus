```sql
CREATE OR REPLACE FUNCTION public.revoke_session(refresh_session_jti uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  user_sub uuid;
  affected_rows integer;
  target_user_id integer;
BEGIN
  -- Get current user ID from JWT claims
  RAISE DEBUG '[revoke_session] Attempting to revoke session JTI: %. Current request.jwt.claims: %', refresh_session_jti, nullif(current_setting('request.jwt.claims', true), '');
  user_sub := (current_setting('request.jwt.claims', true)::jsonb->>'sub')::uuid;
  RAISE DEBUG '[revoke_session] User sub from claims: %', user_sub;

  SELECT id INTO target_user_id FROM auth.user WHERE sub = user_sub;
  RAISE DEBUG '[revoke_session] Target user ID resolved from sub % is %', user_sub, target_user_id;
  
  -- Delete the specified session if it belongs to the current user
  DELETE FROM auth.refresh_session
  WHERE jti = refresh_session_jti AND user_id = target_user_id;
  
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  RAISE DEBUG '[revoke_session] Rows affected by DELETE: % for JTI % and user_id %', affected_rows, refresh_session_jti, target_user_id;
  
  RETURN affected_rows > 0;
END;
$function$
```

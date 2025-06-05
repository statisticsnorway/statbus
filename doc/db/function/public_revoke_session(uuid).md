```sql
CREATE OR REPLACE FUNCTION public.revoke_session(refresh_session_jti uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  user_sub uuid;
  affected_rows integer;
BEGIN
  -- Get current user ID from JWT claims
  user_sub := (current_setting('request.jwt.claims', true)::json->>'sub')::uuid;
  
  -- Delete the specified session if it belongs to the current user
  DELETE FROM auth.refresh_session
  WHERE jti = refresh_session_jti AND user_id = (SELECT id FROM auth.user WHERE sub = user_sub);
  
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  
  RETURN affected_rows > 0;
END;
$function$
```

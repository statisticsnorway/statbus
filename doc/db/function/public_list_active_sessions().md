```sql
CREATE OR REPLACE FUNCTION public.list_active_sessions()
 RETURNS SETOF auth.session_info
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  user_sub uuid;
BEGIN
  -- Get current user ID from JWT claims
  user_sub := (current_setting('request.jwt.claims', true)::json->>'sub')::uuid;
  
  RETURN QUERY
  SELECT 
    s.id,
    s.created_at,
    s.last_used_at,
    s.user_agent,
    s.ip_address,
    (current_setting('request.jwt.claims', true)::json->>'jti')::uuid = s.jti AS current_session
  FROM auth.refresh_session s
  WHERE s.user_id = (SELECT id FROM auth.user WHERE sub = user_sub)
  ORDER BY s.last_used_at DESC;
END;
$function$
```

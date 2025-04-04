```sql
CREATE OR REPLACE FUNCTION public.list_active_sessions()
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  user_sub uuid;
BEGIN
  -- Get current user ID from JWT claims
  user_sub := (current_setting('request.jwt.claims', true)::json->>'sub')::uuid;
  
  RETURN QUERY
  SELECT json_build_object(
    'id', s.id,
    'created_at', s.created_at,
    'last_used_at', s.last_used_at,
    'user_agent', s.user_agent,
    'ip_address', s.ip_address,
    'current_session', (current_setting('request.jwt.claims', true)::json->>'jti')::uuid = s.jti
  )
  FROM auth.refresh_session s
  WHERE s.user_id = (SELECT id FROM auth.user WHERE sub = user_sub)
  ORDER BY s.last_used_at DESC;
END;
$function$
```

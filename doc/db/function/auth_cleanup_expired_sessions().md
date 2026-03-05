```sql
CREATE OR REPLACE FUNCTION auth.cleanup_expired_sessions()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
  DELETE FROM auth.refresh_session WHERE expires_at < now();
$function$
```

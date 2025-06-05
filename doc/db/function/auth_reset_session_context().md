```sql
CREATE OR REPLACE FUNCTION auth.reset_session_context()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Clear JWT claims
  PERFORM set_config('request.jwt.claims', '', true);
END;
$function$
```

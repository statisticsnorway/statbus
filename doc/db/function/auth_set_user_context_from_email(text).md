```sql
CREATE OR REPLACE FUNCTION auth.set_user_context_from_email(p_email text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_claims jsonb;
BEGIN
  -- Build claims for the user
  v_claims := auth.build_jwt_claims(p_email);
  
  -- Set the claims in the current session
  PERFORM auth.use_jwt_claims_in_session(v_claims);
END;
$function$
```

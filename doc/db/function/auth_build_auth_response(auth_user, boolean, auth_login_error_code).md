```sql
CREATE OR REPLACE FUNCTION auth.build_auth_response(p_user_record auth."user" DEFAULT NULL::auth."user", p_expired_access_token_call_refresh boolean DEFAULT false, p_error_code auth.login_error_code DEFAULT NULL::auth.login_error_code)
 RETURNS auth.auth_response
 LANGUAGE plpgsql
AS $function$
DECLARE
  result auth.auth_response;
BEGIN
  IF p_user_record IS NULL THEN
    result.is_authenticated := false;
    result.uid := NULL;
    result.sub := NULL;
    result.email := NULL;
    result.display_name := NULL;    
    result.role := NULL;
    result.statbus_role := NULL;
    result.last_sign_in_at := NULL;
    result.created_at := NULL;
    result.error_code := p_error_code;
    result.expired_access_token_call_refresh := p_expired_access_token_call_refresh; -- Set based on parameter
  ELSE
    result.is_authenticated := true;
    result.uid := p_user_record.id;
    result.sub := p_user_record.sub;
    result.email := p_user_record.email;
    result.display_name := p_user_record.display_name;
    result.role := p_user_record.email; -- Role is typically the email for PostgREST
    result.statbus_role := p_user_record.statbus_role;
    result.last_sign_in_at := p_user_record.last_sign_in_at;
    result.created_at := p_user_record.created_at;
    result.error_code := NULL; -- Explicitly NULL on success
    result.expired_access_token_call_refresh := p_expired_access_token_call_refresh; -- Typically false for an authenticated user
  END IF;
  RETURN result;
END;
$function$
```

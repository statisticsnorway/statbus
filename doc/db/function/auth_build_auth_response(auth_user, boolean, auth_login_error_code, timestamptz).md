```sql
CREATE OR REPLACE FUNCTION auth.build_auth_response(p_user_record auth."user" DEFAULT NULL::auth."user", p_expired_access_token_call_refresh boolean DEFAULT false, p_error_code auth.login_error_code DEFAULT NULL::auth.login_error_code, p_token_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
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
    result.expired_access_token_call_refresh := p_expired_access_token_call_refresh;
    result.token_expires_at := p_token_expires_at;
  ELSE
    result.is_authenticated := true;
    result.uid := p_user_record.id;
    result.sub := p_user_record.sub;
    result.email := p_user_record.email;
    result.display_name := p_user_record.display_name;
    result.role := p_user_record.email;
    result.statbus_role := p_user_record.statbus_role;
    result.last_sign_in_at := p_user_record.last_sign_in_at;
    result.created_at := p_user_record.created_at;
    result.error_code := NULL;
    result.expired_access_token_call_refresh := p_expired_access_token_call_refresh;
    result.token_expires_at := p_token_expires_at;
  END IF;
  RETURN result;
END;
$function$
```

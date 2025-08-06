```sql
CREATE OR REPLACE FUNCTION public.auth_test()
 RETURNS auth.auth_test_response
 LANGUAGE plpgsql
AS $function$
DECLARE
  headers jsonb; -- Changed to jsonb for consistency
  cookies jsonb; -- Changed to jsonb
  transactional_claims jsonb; -- Claims from PostgREST's GUC
  access_token_value text;
  refresh_token_value text;
  access_verification_result auth.jwt_verification_result;
  refresh_verification_result auth.jwt_verification_result;
  result auth.auth_test_response;
  access_token_info auth.token_info;
  refresh_token_info auth.token_info;
BEGIN
  -- Get headers, cookies, and claims from the current request context
  headers := nullif(current_setting('request.headers', true), '')::jsonb;
  cookies := nullif(current_setting('request.cookies', true), '')::jsonb;
  transactional_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;

  RAISE LOG '[public.auth_test] Context ---- Start ----';
  RAISE LOG '[public.auth_test] current_user: %', current_user;
  RAISE LOG '[public.auth_test] request.jwt.claims GUC: %', transactional_claims;
  RAISE LOG '[public.auth_test] request.headers GUC: %', headers;
  RAISE LOG '[public.auth_test] request.cookies GUC: %', cookies;
  RAISE LOG '[public.auth_test] Context ---- End ----';
  
  -- Get token strings from cookies
  access_token_value := cookies->>'statbus';
  refresh_token_value := cookies->>'statbus-refresh';
  
  -- Initialize token info structures
  access_token_info.present := false;
  refresh_token_info.present := false;

  -- Report on access token found in 'statbus' cookie (if any)
  IF access_token_value IS NOT NULL THEN
    access_verification_result := auth.verify_jwt_with_secret(access_token_value);
    access_token_info.present := TRUE;
    access_token_info.token_length := length(access_token_value);
    access_token_info.claims := access_verification_result.claims;
    access_token_info.valid := access_verification_result.is_valid;
    access_token_info.expired := access_verification_result.expired;
    IF NOT access_verification_result.is_valid THEN
      access_token_info.claims := coalesce(access_token_info.claims, '{}'::jsonb) || jsonb_build_object('verification_error', access_verification_result.error_message);
    END IF;
  ELSE
    access_token_info.present := FALSE;
    access_token_info.claims := jsonb_build_object('note', 'No statbus cookie found or cookie was empty.');
  END IF;
  
  -- Report on refresh token found in 'statbus-refresh' cookie (if any)
  IF refresh_token_value IS NOT NULL THEN
    refresh_verification_result := auth.verify_jwt_with_secret(refresh_token_value);
    refresh_token_info.present := TRUE;
    refresh_token_info.token_length := length(refresh_token_value);
    refresh_token_info.claims := refresh_verification_result.claims;
    refresh_token_info.valid := refresh_verification_result.is_valid;
    refresh_token_info.expired := refresh_verification_result.expired;
    IF NOT refresh_verification_result.is_valid THEN
      refresh_token_info.claims := coalesce(refresh_token_info.claims, '{}'::jsonb) || jsonb_build_object('verification_error', refresh_verification_result.error_message);
    ELSE
      refresh_token_info.jti := refresh_verification_result.claims->>'jti';
      refresh_token_info.version := refresh_verification_result.claims->>'version';
    END IF;
  END IF;
  
  -- Build result
  result.headers := headers; -- Use jsonb directly
  result.cookies := cookies; -- Use jsonb directly
  result.claims := transactional_claims; -- This will now reflect the actual authenticated user's claims
  result.access_token := access_token_info;
  result.refresh_token := refresh_token_info;
  result.timestamp := clock_timestamp();
  result.deployment_slot := coalesce(current_setting('app.settings.deployment_slot_code', true), 'dev');
  result.current_db_user := current_user; -- current_user reflects the role after SET ROLE
  result.current_db_role := current_role; -- current_role is the effective role of the user.
  
  -- Ensure headers is not null before trying to access a key
  IF headers IS NOT NULL AND headers ? 'x-forwarded-proto' THEN
    result.is_https := lower(headers->>'x-forwarded-proto') = 'https'; -- Case-insensitive check
  ELSE
    result.is_https := false; -- Default if header is missing
  END IF;
  
  RETURN result;
END;
$function$
```

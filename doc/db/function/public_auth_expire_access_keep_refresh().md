```sql
CREATE OR REPLACE FUNCTION public.auth_expire_access_keep_refresh()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _claims jsonb;
  _user_email text;
  _expired_access_claims jsonb;
  _expired_access_jwt text;
  _refresh_expires timestamptz;
  _secure boolean;
BEGIN
  -- Get claims from the current (valid) JWT to identify the user
  _claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  
  IF _claims IS NULL OR _claims->>'email' IS NULL THEN
    RAISE EXCEPTION 'No valid session found to expire.';
  END IF;
  
  _user_email := _claims->>'email';

  -- Build new claims for an access token that is already expired
  _expired_access_claims := auth.build_jwt_claims(
    p_email => _user_email,
    p_expires_at => clock_timestamp() - '1 second'::interval, -- Set expiry in the past
    p_type => 'access'
  );
  
  -- Sign the expired token
  SELECT auth.generate_jwt(_expired_access_claims) INTO _expired_access_jwt;
  
  -- The cookie itself needs a future expiry date so the browser sends it.
  -- We'll set it to the standard refresh token lifetime.
  _refresh_expires := clock_timestamp() + (coalesce(nullif(current_setting('app.settings.refresh_jwt_exp', true),'')::int, 2592000) || ' seconds')::interval;

  -- Check for HTTPS
  IF lower(nullif(current_setting('request.headers', true), '')::json->>'x-forwarded-proto') IS NOT DISTINCT FROM 'https' THEN
    _secure := true;
  ELSE
    _secure := false;
  END IF;

  -- Set only the access token cookie with the new, expired JWT.
  PERFORM set_config(
    'response.headers',
    jsonb_build_array(
      jsonb_build_object(
        'Set-Cookie',
        format(
          'statbus=%s; Path=/; HttpOnly; SameSite=Strict; %sExpires=%s',
          _expired_access_jwt,
          CASE WHEN _secure THEN 'Secure; ' ELSE '' END,
          to_char(_refresh_expires, 'Dy, DD Mon YYYY HH24:MI:SS') || ' GMT'
        )
      )
    )::text,
    true
  );

  RETURN json_build_object('status', 'access_token_expired_and_set');
END;
$function$
```

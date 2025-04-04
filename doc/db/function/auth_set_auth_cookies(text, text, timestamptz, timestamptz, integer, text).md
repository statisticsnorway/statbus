```sql
CREATE OR REPLACE FUNCTION auth.set_auth_cookies(access_jwt text, refresh_jwt text, access_expires timestamp with time zone, refresh_expires timestamp with time zone, user_id integer, user_email text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM set_config('response.headers',
    json_build_array(
      json_build_object(
        'Set-Cookie',
        format('statbus-%s=%s; Path=/; Expires=%s; HttpOnly; SameSite=Strict',
               current_setting('app.settings.deployment_slot_code', true),
               access_jwt,
               to_char(access_expires at time zone 'GMT', 'Dy, DD Mon YYYY HH24:MI:SS GMT'))
      ),
      json_build_object(
        'Set-Cookie',
        format('statbus-%s-refresh=%s; Path=/; Expires=%s; HttpOnly; SameSite=Strict',
               current_setting('app.settings.deployment_slot_code', true),
               refresh_jwt,
               to_char(refresh_expires at time zone 'GMT', 'Dy, DD Mon YYYY HH24:MI:SS GMT'))
      ),
      json_build_object(
        'App-Auth-Token', access_jwt
      ),
      json_build_object(
        'App-Auth-Role', user_email
      ),
      json_build_object(
        'App-Auth-User', user_id
      )
    )::text,
    true
  );
END;
$function$
```

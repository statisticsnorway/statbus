```sql
CREATE OR REPLACE FUNCTION auth.clear_auth_cookies()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM set_config('response.headers',
    json_build_array(
      json_build_object(
        'Set-Cookie',
        format('statbus-%s=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Strict',
               current_setting('app.settings.deployment_slot_code', true))
      ),
      json_build_object(
        'Set-Cookie',
        format('statbus-%s-refresh=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Strict',
               current_setting('app.settings.deployment_slot_code', true))
      )
    )::text,
    true
  );
END;
$function$
```

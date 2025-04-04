```sql
CREATE OR REPLACE FUNCTION auth.build_auth_response(access_jwt text, refresh_jwt text, user_id integer, user_email text, user_statbus_role statbus_role)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN json_build_object(
    'access_jwt', access_jwt,
    'refresh_jwt', refresh_jwt,
    'user_id', user_id,
    'email', user_email,
    'role', user_email,
    'statbus_role', user_statbus_role
  );
END;
$function$
```

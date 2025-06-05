```sql
CREATE OR REPLACE FUNCTION auth.build_auth_response(access_jwt text, refresh_jwt text, user_record auth."user")
 RETURNS auth.auth_response
 LANGUAGE plpgsql
AS $function$
DECLARE
  result auth.auth_response;
BEGIN
  result.access_jwt := access_jwt;
  result.refresh_jwt := refresh_jwt;
  result.uid := user_record.id;
  result.sub := user_record.sub;
  result.email := user_record.email;
  result.role := user_record.email;
  result.statbus_role := user_record.statbus_role;
  
  RETURN result;
END;
$function$
```

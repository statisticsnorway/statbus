```sql
CREATE OR REPLACE FUNCTION public.grant_role(user_sub uuid, new_role statbus_role)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _user auth.user;
  _is_admin boolean;
BEGIN
  -- Check if current user is admin or superuser
  _is_admin := (current_setting('request.jwt.claims', true)::json->>'statbus_role')::public.statbus_role = 'admin_user' OR 
               (SELECT usesuper FROM pg_user WHERE usename = current_user);
               
  IF NOT _is_admin THEN
    RAISE EXCEPTION 'Only admin users can grant roles';
  END IF;
  
  -- Get the target user
  SELECT * INTO _user FROM auth.user WHERE sub = user_sub;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found';
  END IF;
  
  -- Revoke the old statbus role from the user's role
  EXECUTE format('REVOKE %I FROM %I', _user.statbus_role::text, _user.email);
  
  -- Grant the new statbus role to the user's role
  EXECUTE format('GRANT %I TO %I', new_role::text, _user.email);
  
  -- Update the user record
  UPDATE auth.user SET 
    statbus_role = new_role,
    updated_at = now()
  WHERE sub = user_sub;
  
  RETURN true;
END;
$function$
```

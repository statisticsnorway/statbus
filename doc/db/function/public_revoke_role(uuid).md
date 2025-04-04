```sql
CREATE OR REPLACE FUNCTION public.revoke_role(user_sub uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _user auth.user;
  _current_user_role public.statbus_role;
  _is_admin boolean;
BEGIN
  -- Get the current user's role from JWT claims
  _current_user_role := (current_setting('request.jwt.claims', true)::json->>'statbus_role')::public.statbus_role;
  
  -- Check if current user is admin or superuser
  _is_admin := _current_user_role = 'admin_user' OR 
               (SELECT usesuper FROM pg_user WHERE usename = current_user);
               
  IF NOT _is_admin THEN
    RAISE EXCEPTION 'Only admin users can revoke roles';
  END IF;
  
  -- Get the target user
  SELECT * INTO _user FROM auth.user WHERE sub = user_sub;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found';
  END IF;
  
  -- Revoke the current statbus role from the user's role
  EXECUTE format('REVOKE %I FROM %I', _user.statbus_role::text, _user.email);
  
  -- Grant the default role (regular_user) to the user's role
  EXECUTE format('GRANT regular_user TO %I', _user.email);
  
  -- Update the user record
  UPDATE auth.user SET 
    statbus_role = 'regular_user',
    updated_at = now()
  WHERE sub = user_sub;
  
  RETURN true;
END;
$function$
```

```sql
CREATE OR REPLACE FUNCTION public.change_password(new_password text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
  _user auth.user;
  _claims jsonb;
BEGIN
  -- Get claims from the current JWT
  _claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;

  -- Ensure this function is called with an 'access' token, not refresh or api_key
  IF _claims IS NOT NULL AND _claims->>'type' IS DISTINCT FROM 'access' THEN
    RAISE EXCEPTION 'Password change requires a valid access token.';
  END IF;

  -- Get the current user based on the JWT's sub claim
  SELECT * INTO _user
  FROM auth.user
  WHERE email = current_user;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found.'; -- Should not happen if JWT is valid
  END IF;

  -- Check new password strength/requirements if needed (add logic here)
  IF length(new_password) < 8 THEN -- Example minimum length check
     RAISE EXCEPTION 'New password is too short (minimum 8 characters).';
  END IF;

  -- Update the user's password
  -- The sync_user_credentials_and_roles_trigger will handle password hashing
  -- and updating the DB role password.
  UPDATE auth.user
  SET
    password = new_password,
    updated_at = clock_timestamp()
  WHERE id = _user.id;
  
  -- Invalidate all existing refresh sessions for this user
  DELETE FROM auth.refresh_session
  WHERE user_id = _user.id;
  
  -- Clear auth cookies
  PERFORM auth.clear_auth_cookies();

  RAISE DEBUG 'Password changed successfully for user % (%)', _user.email, _user.sub;

  RETURN true;
END;
$function$
```

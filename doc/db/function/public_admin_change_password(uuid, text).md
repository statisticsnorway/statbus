```sql
CREATE OR REPLACE FUNCTION public.admin_change_password(user_sub uuid, new_password text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
  _target_user auth.user;
BEGIN
  -- Check if the caller is an admin
  IF NOT pg_has_role(current_user, 'admin_user', 'MEMBER') THEN
     RAISE EXCEPTION 'Permission denied: Only admin users can change other users passwords.';
  END IF;

  -- Get the target user
  SELECT * INTO _target_user
  FROM auth.user
  WHERE sub = user_sub
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target user not found.';
  END IF;

  -- Check new password strength/requirements if needed
  IF length(new_password) < 8 THEN
     RAISE EXCEPTION 'New password is too short (minimum 8 characters).';
  END IF;

  -- Update the target user's password
  -- The sync_user_credentials_and_roles_trigger will handle password hashing
  -- and updating the DB role password.
  UPDATE auth.user
  SET
    password = new_password,
    updated_at = clock_timestamp()
  WHERE id = _target_user.id;

  -- Invalidate all existing refresh sessions for the target user
  DELETE FROM auth.refresh_session
  WHERE user_id = _target_user.id;
  
  RAISE DEBUG 'Password changed successfully for user % (%) by %',
    _target_user.email, _target_user.sub, current_user;

  RETURN true;
END;
$function$
```

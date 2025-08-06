```sql
CREATE OR REPLACE FUNCTION auth.check_role_permission()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Check role assignment permission
  -- This check only applies if a role is being assigned (INSERT) or changed (UPDATE)
  RAISE DEBUG '[check_role_permission] Trigger fired. TG_OP: %, current_user: %, NEW.email: %, NEW.statbus_role: %', TG_OP, current_user, NEW.email, NEW.statbus_role;
  IF TG_OP = 'UPDATE' THEN
    RAISE DEBUG '[check_role_permission] OLD.statbus_role: %', OLD.statbus_role;
  END IF;

  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.statbus_role IS DISTINCT FROM NEW.statbus_role) THEN
    RAISE DEBUG '[check_role_permission] Checking role assignment: current_user % trying to assign/change to role %.', current_user, NEW.statbus_role;
    -- Check if the current user (invoker) is a member of the role they are trying to assign.
    -- This prevents users from assigning roles they don't possess themselves.
    -- Note: Role hierarchy (e.g., admin_user GRANTed regular_user) means admins can assign lower roles.
    IF NOT pg_has_role(current_user, NEW.statbus_role::text, 'MEMBER') THEN
      RAISE DEBUG '[check_role_permission] Permission check FAILED: current_user % is NOT a member of %.', current_user, NEW.statbus_role;
      RAISE EXCEPTION 'Permission denied: Cannot assign role %.', NEW.statbus_role
        USING HINT = 'The current user (' || current_user || ') must be a member of the target role.';
    ELSE
      RAISE DEBUG '[check_role_permission] Permission check PASSED: current_user % is a member of %.', current_user, NEW.statbus_role;
    END IF;
  END IF;

  -- Return NEW to allow the operation to proceed to the next trigger
  RETURN NEW;
END;
$function$
```

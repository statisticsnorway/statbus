```sql
CREATE OR REPLACE FUNCTION auth.sync_user_credentials_and_roles()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  role_name text;
  old_role_name text;
  db_password text;
BEGIN
  RAISE DEBUG '[sync_user_credentials_and_roles] Trigger fired. TG_OP: %, current_user (definer context): %, NEW.email: %, NEW.statbus_role: %', TG_OP, current_user, NEW.email, NEW.statbus_role;
  IF TG_OP = 'UPDATE' THEN
    RAISE DEBUG '[sync_user_credentials_and_roles] OLD.email: %, OLD.statbus_role: %', OLD.email, OLD.statbus_role;
  END IF;

  -- Use the email as the role name for the PostgreSQL role
  role_name := NEW.email;

  -- For UPDATE operations where email has changed, rename the corresponding database role
  IF TG_OP = 'UPDATE' AND OLD.email IS DISTINCT FROM NEW.email THEN
    old_role_name := OLD.email;
    
    -- Check if the old role exists
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = old_role_name) THEN
      -- Check if the old role exists before trying to rename
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = old_role_name) THEN
        -- Rename the role to match the new email
        EXECUTE format('ALTER ROLE %I RENAME TO %I', old_role_name, role_name);
        -- Role permissions (membership in authenticated, statbus_role) are retained after rename.
      ELSE
        -- If the old role doesn't exist, we might need to create the new one.
        -- This case handles scenarios where the role might have been manually dropped
        -- or if the email change happens before the role was initially created.
        -- The logic below will handle the creation if needed.
        RAISE DEBUG 'Old role % not found for renaming to %, will ensure new role exists.', old_role_name, role_name;
      END IF;
    -- If email didn't change, role_name is the same as OLD.email
    END IF; -- The old role didn't exists, mabye we are in a transaction with delayed triggers?
  END IF;

  -- Ensure the database role exists for the NEW.email
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
    -- Create the role with INHERIT (default) to ensure permissions flow through
    -- INHERIT is ESSENTIAL for the role hierarchy to work properly
    -- Without INHERIT, users would not get permissions from authenticated or their statbus role
    EXECUTE format('CREATE ROLE %I LOGIN INHERIT', role_name);
    
    -- Grant authenticated role to the user role
    -- This provides the base permissions needed for application functionality
    -- With INHERIT, the user will automatically have all permissions from authenticated
    EXECUTE format('GRANT authenticated TO %I', role_name);
    
    -- Grant the user role to authenticator to allow role switching via JWT impersonation
    EXECUTE format('GRANT %I TO authenticator', role_name);
    
    -- Grant the appropriate statbus role to the new role
    -- This determines the user's permission level (admin, regular, restricted, external)
    -- The user inherits all permissions from their statbus_role through role inheritance
    EXECUTE format('GRANT %I TO %I', NEW.statbus_role::text, role_name);
  -- If the role already exists, ensure its statbus_role membership is correct
  ELSIF TG_OP = 'UPDATE' AND OLD.statbus_role IS DISTINCT FROM NEW.statbus_role THEN
    -- If the statbus_role has changed, update the role grants for the database role
    IF OLD.statbus_role IS NOT NULL THEN
      EXECUTE format('REVOKE %I FROM %I', OLD.statbus_role::text, role_name);
    END IF;
    EXECUTE format('GRANT %I TO %I', NEW.statbus_role::text, role_name);
  END IF;

  -- 1. Encrypt password if provided in NEW.password (plain text)
  IF NEW.password IS NOT NULL THEN
    -- Set the encrypted password for application authentication
    NEW.encrypted_password := public.crypt(NEW.password, public.gen_salt('bf'));
    
    -- Set/Update the database role's password using the plain text password from NEW.password
    -- This ensures the database role password stays in sync with the application password.
    -- This needs to happen *before* we clear NEW.password.
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.encrypted_password IS DISTINCT FROM NEW.encrypted_password) THEN
      RAISE DEBUG '[sync_user_credentials_and_roles] Password provided/changed. Updating DB role % password.', role_name;
      EXECUTE format('ALTER ROLE %I WITH PASSWORD %L', role_name, NEW.password);
      RAISE DEBUG '[sync_user_credentials_and_roles] Set database role password for %', role_name;
    END IF;

    -- Clear the plain text password immediately after encryption and potential DB role update
    NEW.password := NULL;
  END IF;

  RETURN NEW;
END;
$function$
```

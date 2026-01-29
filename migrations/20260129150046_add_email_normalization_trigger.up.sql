-- Add email normalization trigger to ensure emails are always stored lowercase
-- This is necessary because:
-- 1. PostgreSQL role names are case-sensitive
-- 2. We use email as the role name for database authentication
-- 3. citext provides case-insensitive comparison but doesn't normalize storage

-- Create the normalization function
CREATE OR REPLACE FUNCTION auth.normalize_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
AS $normalize_email$
BEGIN
    -- Normalize email to lowercase for consistent storage and role naming
    IF NEW.email IS NOT NULL THEN
        NEW.email := lower(NEW.email);
    END IF;
    RETURN NEW;
END;
$normalize_email$;

-- Create trigger with 00_ prefix to ensure it fires first (alphabetically before other triggers)
-- Existing triggers on auth.user:
--   check_role_permission_trigger (BEFORE INSERT OR UPDATE)
--   sync_user_credentials_and_roles_trigger (BEFORE INSERT OR UPDATE)
-- This trigger must fire before sync_user_credentials_and_roles_trigger which uses email as role name
DROP TRIGGER IF EXISTS "00_normalize_email_trigger" ON auth.user;
CREATE TRIGGER "00_normalize_email_trigger"
BEFORE INSERT OR UPDATE OF email ON auth.user
FOR EACH ROW
EXECUTE FUNCTION auth.normalize_email();

-- Update sync_user_credentials_and_roles to use lower() defensively on role names
-- This handles any edge cases and makes the role name derivation explicit
CREATE OR REPLACE FUNCTION auth.sync_user_credentials_and_roles()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Needs elevated privileges to manage roles and encrypt password securely
AS $sync_user_credentials_and_roles$
DECLARE
  role_name text;
  old_role_name text;
  db_password text;
BEGIN
  RAISE DEBUG '[sync_user_credentials_and_roles] Trigger fired. TG_OP: %, current_user (definer context): %, NEW.email: %, NEW.statbus_role: %', TG_OP, current_user, NEW.email, NEW.statbus_role;
  IF TG_OP = 'UPDATE' THEN
    RAISE DEBUG '[sync_user_credentials_and_roles] OLD.email: %, OLD.statbus_role: %', OLD.email, OLD.statbus_role;
  END IF;

  -- Use the lowercase email as the role name for the PostgreSQL role
  -- The 00_normalize_email_trigger ensures NEW.email is already lowercase,
  -- but we use lower() defensively for clarity and safety
  role_name := lower(NEW.email);

  -- For UPDATE operations where email has changed, rename the corresponding database role
  IF TG_OP = 'UPDATE' AND OLD.email IS DISTINCT FROM NEW.email THEN
    old_role_name := lower(OLD.email);
    
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
$sync_user_credentials_and_roles$;

-- Normalize existing emails to lowercase
-- This will trigger the sync_user_credentials_and_roles function which will rename
-- the PostgreSQL roles to match the new lowercase emails
-- We use a DO block to handle each user individually and log progress
DO $$
DECLARE
  user_record RECORD;
  normalized_email text;
BEGIN
  FOR user_record IN 
    SELECT id, email 
    FROM auth.user 
    WHERE email IS DISTINCT FROM lower(email)
  LOOP
    normalized_email := lower(user_record.email);
    RAISE NOTICE 'Normalizing email for user %: % -> %', user_record.id, user_record.email, normalized_email;
    
    UPDATE auth.user 
    SET email = normalized_email 
    WHERE id = user_record.id;
  END LOOP;
END;
$$;

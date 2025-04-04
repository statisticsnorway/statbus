```sql
CREATE OR REPLACE FUNCTION auth.create_user_role()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  role_name text;
BEGIN
  -- Use the email as the role name for the PostgreSQL role
  -- This allows users to connect to the database using their email as username
  -- When PostgREST receives a JWT with 'role': email, it will execute SET LOCAL ROLE email
  role_name := NEW.email;

  -- Check if role already exists
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
    -- Create the role with INHERIT (default) to ensure permissions flow through
    -- INHERIT is ESSENTIAL for the role hierarchy to work properly
    -- Without INHERIT, users would not get permissions from authenticated or their statbus role
    EXECUTE format('CREATE ROLE %I LOGIN INHERIT', role_name);
    
    -- Grant authenticated role to the user role
    -- This provides the base permissions needed for application functionality
    -- With INHERIT, the user will automatically have all permissions from authenticated
    EXECUTE format('GRANT authenticated TO %I', role_name);
    
    -- Grant the appropriate statbus role to the new role
    -- This determines the user's permission level (admin, regular, restricted, external)
    -- The user inherits all permissions from their statbus_role through role inheritance
    EXECUTE format('GRANT %I TO %I', NEW.statbus_role::text, role_name);
    
    -- Set password for database access if provided
    -- This enables the user to connect directly to the database with the same password
    -- they use for the application
    IF NEW.password IS NOT NULL THEN
      -- Set the encrypted password for application authentication
      NEW.encrypted_password := crypt(NEW.password, gen_salt('bf'));
      
      -- Set the database role password for direct database access
      -- This allows psql and other PostgreSQL clients to connect using this user
      EXECUTE format('ALTER ROLE %I WITH PASSWORD %L', role_name, NEW.password);
      
      -- Clear the plain text password for security
      NEW.password := NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
```

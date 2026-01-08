BEGIN;

-- Table for auth-related secrets (JWT secret, etc.)
-- Located in auth schema because these are authentication secrets, not general admin credentials
CREATE TABLE auth.secrets (
    key text PRIMARY KEY,
    value text NOT NULL,
    description text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Force RLS to prevent any access without explicit policy
-- This protects against the table owner accidentally exposing data
ALTER TABLE auth.secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.secrets FORCE ROW LEVEL SECURITY;

-- No SELECT policy is created - this means NO ONE can SELECT directly
-- Only SECURITY DEFINER functions running as owner bypass RLS entirely
-- This is the key: SECURITY DEFINER functions ignore RLS, regular users hit the RLS wall
REVOKE ALL ON auth.secrets FROM PUBLIC;

COMMENT ON TABLE auth.secrets IS 
    'Secure storage for authentication secrets like JWT secret. FORCE ROW LEVEL SECURITY with no policy means direct access is impossible. SECURITY DEFINER functions bypass RLS and can access. SECURITY INVOKER functions inherit caller''s privileges - they can only access when called from SECURITY DEFINER context (which runs as owner and bypasses RLS).';

-- Single source of truth for JWT secret access
-- SECURITY INVOKER so it inherits caller's privileges (must be called from SECURITY DEFINER context)
CREATE FUNCTION auth.jwt_secret()
RETURNS text
LANGUAGE plpgsql
SECURITY INVOKER
STABLE
SET search_path = auth, pg_temp
AS $$
DECLARE
  _secret text;
BEGIN
  SELECT value INTO _secret FROM auth.secrets WHERE key = 'jwt_secret';
  
  IF _secret IS NULL THEN
    RAISE EXCEPTION 'JWT secret not found in auth.secrets. Either not loaded yet, or insufficient permissions (must be called from SECURITY DEFINER context).';
  END IF;
  
  RETURN _secret;
END;
$$;

COMMENT ON FUNCTION auth.jwt_secret IS 
    'Returns the JWT secret. Must be called from SECURITY DEFINER context to bypass RLS on auth.secrets. Raises exception if secret not found or insufficient permissions.';

COMMIT;

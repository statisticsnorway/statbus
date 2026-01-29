```sql
CREATE OR REPLACE FUNCTION auth.jwt_switch_role(access_jwt text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  _jwt_verify_result auth.jwt_verify_result;
  _user_email text;
  _role_exists boolean;
BEGIN
  -- Verify JWT using SECURITY DEFINER function that accesses the secret
  -- This function returns verification result without exposing the secret
  _jwt_verify_result := auth.jwt_verify(access_jwt);
  
  -- Check if token is valid
  IF NOT _jwt_verify_result.is_valid THEN
    RAISE EXCEPTION 'Invalid token: %', _jwt_verify_result.error_message;
  END IF;
  
  -- Check if token is expired
  IF _jwt_verify_result.expired THEN
    RAISE EXCEPTION 'Token has expired';
  END IF;
  
  -- Verify this is an access token
  IF _jwt_verify_result.claims->>'type' != 'access' THEN
    RAISE EXCEPTION 'Invalid token type: expected access token';
  END IF;
  
  -- Extract user email from claims (which is also the role name)
  _user_email := _jwt_verify_result.claims->>'role';
  
  IF _user_email IS NULL THEN
    RAISE EXCEPTION 'Token does not contain role claim';
  END IF;
  
  -- Check if a role exists for this user
  SELECT EXISTS(
    SELECT 1 FROM pg_roles WHERE rolname = _user_email
  ) INTO _role_exists;

  -- Ensure this function is called within a transaction, as SET ROLE is transaction-scoped.
  IF transaction_timestamp() = statement_timestamp() THEN
    RAISE EXCEPTION 'SET ROLE must be called within a transaction block (BEGIN...COMMIT/ROLLBACK).';
  END IF;

  IF NOT _role_exists THEN
    RAISE EXCEPTION 'Role % does not exist', _user_email;
  ELSE
    -- Switch to user-specific role
    EXECUTE format('SET ROLE %I', _user_email);
  END IF;
END;
$function$
```

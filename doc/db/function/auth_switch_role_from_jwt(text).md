```sql
CREATE OR REPLACE FUNCTION auth.switch_role_from_jwt(access_jwt text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  _claims json;
  _user_email text;
  _role_exists boolean;
BEGIN
  -- Verify and extract claims from JWT
  BEGIN
    SELECT payload::json INTO _claims 
    FROM verify(access_jwt, current_setting('app.settings.jwt_secret'));
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Invalid token: %', SQLERRM;
  END;
  
  -- Verify this is an access token
  IF _claims->>'type' != 'access' THEN
    RAISE EXCEPTION 'Invalid token type: expected access token';
  END IF;
  
  -- Extract user email from claims (which is also the role name)
  _user_email := _claims->>'role';
  
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

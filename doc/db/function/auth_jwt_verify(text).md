```sql
CREATE OR REPLACE FUNCTION auth.jwt_verify(token_value text)
 RETURNS auth.jwt_verify_result
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  _claims jsonb;
  _jwt_verify_result auth.jwt_verify_result;
BEGIN
  _jwt_verify_result.is_valid := false;
  _jwt_verify_result.error_message := 'Token verification not attempted';
  _jwt_verify_result.expired := null;

  IF token_value IS NULL THEN
    _jwt_verify_result.error_message := 'Token is NULL';
    RETURN _jwt_verify_result;
  END IF;

  BEGIN
    -- Use centralized jwt_secret() function
    SELECT payload::jsonb INTO _claims
    FROM public.verify(token_value, auth.jwt_secret());

    _jwt_verify_result.is_valid := TRUE;
    _jwt_verify_result.claims := _claims;
    _jwt_verify_result.error_message := NULL;
    IF (_claims->>'exp')::numeric < extract(epoch from clock_timestamp()) THEN
      _jwt_verify_result.expired := TRUE;
    ELSE
      _jwt_verify_result.expired := FALSE;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    _jwt_verify_result.is_valid := FALSE;
    _jwt_verify_result.claims := NULL;
    _jwt_verify_result.error_message := SQLERRM;
    -- Check if the error message indicates an expired signature specifically
    IF SQLERRM LIKE '%expired_signature%' THEN
        _jwt_verify_result.expired := TRUE;
    ELSE
        _jwt_verify_result.expired := NULL; -- Unknown if expired if another error occurred
    END IF;
  END;

  RETURN _jwt_verify_result;
END;
$function$
```

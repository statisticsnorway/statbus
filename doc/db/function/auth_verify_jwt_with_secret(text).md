```sql
CREATE OR REPLACE FUNCTION auth.verify_jwt_with_secret(token_value text)
 RETURNS auth.jwt_verification_result
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _claims jsonb;
  _jwt_secret text;
  _result auth.jwt_verification_result;
BEGIN
  _jwt_secret := current_setting('app.settings.jwt_secret', true);
  _result.is_valid := false;
  _result.error_message := 'Token verification not attempted';
  _result.expired := null;

  IF token_value IS NULL THEN
    _result.error_message := 'Token is NULL';
    RETURN _result;
  END IF;

  BEGIN
    SELECT payload::jsonb INTO _claims
    FROM public.verify(token_value, _jwt_secret);

    _result.is_valid := TRUE;
    _result.claims := _claims;
    _result.error_message := NULL;
    IF (_claims->>'exp')::numeric < extract(epoch from clock_timestamp()) THEN
      _result.expired := TRUE;
    ELSE
      _result.expired := FALSE;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    _result.is_valid := FALSE;
    _result.claims := NULL;
    _result.error_message := SQLERRM;
    -- Check if the error message indicates an expired signature specifically
    IF SQLERRM LIKE '%expired_signature%' THEN
        _result.expired := TRUE;
    ELSE
        _result.expired := NULL; -- Unknown if expired if another error occurred
    END IF;
  END;

  RETURN _result;
END;
$function$
```

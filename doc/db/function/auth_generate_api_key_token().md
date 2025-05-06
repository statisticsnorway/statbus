```sql
CREATE OR REPLACE FUNCTION auth.generate_api_key_token()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _user auth.user;
  _claims jsonb;
  _api_key_jwt text;
BEGIN
  -- Get the user for this API key
  SELECT * INTO _user
  FROM auth.user
  WHERE id = NEW.user_id
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found for API key creation';
  END IF;

  -- Build claims for the API key JWT
  _claims := auth.build_jwt_claims(
    p_email => _user.email,
    p_expires_at => NEW.expires_at,
    p_type => 'api_key',
    p_additional_claims => jsonb_build_object(
      'description', NEW.description,
      'jti', NEW.jti::text
    )
  );

  -- Generate the signed JWT
  SELECT auth.generate_jwt(_claims) INTO _api_key_jwt;
  
  -- Store the token in the record
  NEW.token := _api_key_jwt;
  
  RETURN NEW;
END;
$function$
```

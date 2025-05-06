```sql
CREATE OR REPLACE FUNCTION auth.check_api_key_revocation()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _claims jsonb;
  _token_type text;
  _jti uuid;
  _revoked_at timestamptz; -- Store only the revocation timestamp
  _current_date date := current_date; -- Get date once
BEGIN
  -- Get claims from the current JWT
  _claims := current_setting('request.jwt.claims', true)::jsonb;
  _token_type := _claims->>'type';

  -- Only perform checks for API keys
  IF _token_type = 'api_key' THEN
    _jti := (_claims->>'jti')::uuid;

    IF _jti IS NULL THEN
      RAISE EXCEPTION 'Invalid API Key: Missing JTI claim.' USING ERRCODE = 'P0001';
    END IF;

    -- Check if the key exists and is revoked
    SELECT revoked_at INTO _revoked_at
    FROM auth.api_key
    WHERE jti = _jti;

    IF NOT FOUND THEN
      -- Key might have been deleted or never existed
      RAISE EXCEPTION 'Invalid API Key: Key not found.' USING ERRCODE = 'P0001';
    END IF;

    IF _revoked_at IS NOT NULL THEN
      RAISE EXCEPTION 'API Key has been revoked.' USING ERRCODE = 'P0001';
    END IF;

    -- last_used_on update removed due to issues with read-only transactions

  END IF;

  -- If not an API key or if key is valid and not revoked, proceed
  RETURN;
END;
$function$
```

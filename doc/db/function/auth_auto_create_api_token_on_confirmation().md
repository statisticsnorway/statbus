```sql
CREATE OR REPLACE FUNCTION auth.auto_create_api_token_on_confirmation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _expires_at timestamptz;
  _description text;
  _existing_count integer;
BEGIN
  -- Only create API token when email_confirmed_at is NOT NULL
  -- For INSERT: NEW.email_confirmed_at IS NOT NULL
  -- For UPDATE: OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL
  IF (TG_OP = 'INSERT' AND NEW.email_confirmed_at IS NOT NULL) OR
     (TG_OP = 'UPDATE' AND OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL) THEN
    
    -- Check if user already has an API token
    SELECT COUNT(*) INTO _existing_count
    FROM auth.api_key
    WHERE user_id = NEW.id;
    
    -- Only create if user doesn't have any API tokens yet
    IF _existing_count = 0 THEN
      _expires_at := clock_timestamp() + interval '1 year';
      _description := 'Default API Key';
      
      INSERT INTO auth.api_key (
        user_id,
        description,
        expires_at
      ) VALUES (
        NEW.id,
        _description,
        _expires_at
      );
      
      RAISE DEBUG 'Auto-created API token for user % (%)', NEW.email, NEW.id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$
```

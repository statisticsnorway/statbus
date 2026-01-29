```sql
CREATE OR REPLACE FUNCTION public.create_api_key(description text DEFAULT 'Default API Key'::text, duration interval DEFAULT '1 year'::interval)
 RETURNS api_key
 LANGUAGE plpgsql
AS $function$
DECLARE
  _user_id integer;
  _expires_at timestamptz;
  _jti uuid := uuidv7();
  _result public.api_key;
BEGIN
  -- Get current user ID
  _user_id := auth.uid();
  
  -- Calculate expiration time
  _expires_at := clock_timestamp() + duration;
  
  -- Insert the new API key
  INSERT INTO public.api_key (
    jti, 
    user_id, 
    description, 
    expires_at
  ) 
  VALUES (
    _jti, 
    _user_id, 
    description, 
    _expires_at
  )
  RETURNING * INTO _result;
  
  RETURN _result;
END;
$function$
```

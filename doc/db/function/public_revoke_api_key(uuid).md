```sql
CREATE OR REPLACE FUNCTION public.revoke_api_key(key_jti uuid)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
  _api_key_record public.api_key;
  _affected_rows integer;
BEGIN
  -- RLS policy ensures user can only update their own keys
  UPDATE public.api_key
  SET revoked_at = clock_timestamp()
  WHERE jti = key_jti
    -- RLS implicitly adds AND user_id = auth.uid()
    AND revoked_at IS NULL; -- Only revoke if not already revoked

  GET DIAGNOSTICS _affected_rows = ROW_COUNT;

  IF _affected_rows = 0 THEN
     -- Check if key exists at all (and belongs to user due to RLS)
     SELECT * INTO _api_key_record FROM public.api_key WHERE jti = key_jti;
     IF NOT FOUND THEN
        RAISE EXCEPTION 'API Key not found or permission denied.';
     ELSE
        -- Key exists but was already revoked or update failed
        RAISE WARNING 'API Key was already revoked or update failed.';
        RETURN false;
     END IF;
  END IF;

  RAISE DEBUG 'API Key revoked: %', key_jti;
  RETURN true;
END;
$function$
```

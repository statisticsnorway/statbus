```sql
CREATE OR REPLACE FUNCTION auth.build_jwt_claims(p_email text, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_type text DEFAULT 'access'::text, p_additional_claims jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_user auth.user;
  v_expires_at timestamptz;
  v_claims jsonb;
BEGIN
  -- Find user by email (required)
  SELECT * INTO v_user
  FROM auth.user
  WHERE email = p_email AND deleted_at IS NULL;
    
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User with email % not found', p_email;
  END IF;
  
  -- Set expiration time using provided value or default based on type
  v_expires_at := COALESCE(
    p_expires_at,
    clock_timestamp() + (coalesce(current_setting('app.settings.access_jwt_exp', true)::int, 3600) || ' seconds')::interval
  );
  
  -- Build claims with PostgREST compatible structure, deriving sub and role from user record
  v_claims := jsonb_build_object(
    'role', v_user.email, -- PostgREST does a 'SET LOCAL ROLE $role' to ensure security for all of the API
    'statbus_role', v_user.statbus_role::text,
    'sub', v_user.sub::text,
    'uid', v_user.id, -- Add the integer user ID
    'display_name', v_user.display_name,
    'email', v_user.email,
    'type', p_type,
    'iat', extract(epoch from clock_timestamp())::integer,
    'exp', extract(epoch from v_expires_at)::integer
  );
  
  -- Add JTI if not in additional claims
  IF NOT p_additional_claims ? 'jti' THEN
    v_claims := v_claims || jsonb_build_object('jti', public.gen_random_uuid()::text);
  END IF;
  
  -- Merge additional claims
  RETURN v_claims || p_additional_claims;
END;
$function$
```

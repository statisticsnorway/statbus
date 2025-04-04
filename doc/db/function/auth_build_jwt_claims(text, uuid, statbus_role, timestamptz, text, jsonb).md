```sql
CREATE OR REPLACE FUNCTION auth.build_jwt_claims(p_email text, p_sub uuid DEFAULT NULL::uuid, p_statbus_role statbus_role DEFAULT NULL::statbus_role, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_type text DEFAULT 'access'::text, p_additional_claims jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_user auth.user;
  v_sub uuid;
  v_statbus_role public.statbus_role;
  v_expires_at timestamptz;
  v_claims jsonb;
BEGIN
  -- Find user if email is provided
  IF p_email IS NOT NULL THEN
    SELECT * INTO v_user
    FROM auth.user
    WHERE email = p_email
      AND deleted_at IS NULL;
      
    IF NOT FOUND THEN
      RAISE EXCEPTION 'User with email % not found', p_email;
    END IF;
    
    v_sub := COALESCE(p_sub, v_user.sub);
    v_statbus_role := COALESCE(p_statbus_role, v_user.statbus_role);
  ELSE
    -- Use provided values directly if no email
    v_sub := p_sub;
    v_statbus_role := p_statbus_role;
    
    IF v_sub IS NULL THEN
      RAISE EXCEPTION 'Either email or sub must be provided';
    END IF;
  END IF;
  
  -- Set expiration time
  v_expires_at := COALESCE(
    p_expires_at,
    clock_timestamp() + (coalesce(current_setting('app.settings.access_jwt_exp', true)::int, 3600) || ' seconds')::interval
  );
  
  -- Build the base claims object with PostgREST compatible structure
  -- role must be the database role name for PostgREST to work correctly
  v_claims := jsonb_build_object(
    'role', p_email,
    'statbus_role', v_statbus_role::text,
    'sub', v_sub::text,
    'email', p_email,
    'type', p_type,
    'iat', extract(epoch from clock_timestamp())::integer,
    'exp', extract(epoch from v_expires_at)::integer
  );
  
  -- Only add JTI if not already in additional claims
  IF NOT p_additional_claims ? 'jti' THEN
    v_claims := v_claims || jsonb_build_object('jti', gen_random_uuid()::text);
  END IF;
  
  -- Merge any additional claims
  v_claims := v_claims || p_additional_claims;
  
  RETURN v_claims;
END;
$function$
```

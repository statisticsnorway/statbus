BEGIN;

-- This type matches the errors defined in the OAuth2 Device Authorization Grant spec
CREATE TYPE auth.device_flow_error AS ENUM (
    'authorization_pending',
    'slow_down',
    'expired_token',
    'access_denied'
);

-- RPC function for clients (like psql) to poll for an access token
CREATE OR REPLACE FUNCTION public.poll_device_authorization(p_device_code text)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    v_req auth.device_authorization_request;
    v_user auth.user;
    v_access_token text;
    v_access_claims jsonb;
    v_access_expires timestamptz;
BEGIN
    -- Find the request by device code
    SELECT * INTO v_req
    FROM auth.device_authorization_request
    WHERE device_code = p_device_code;

    IF NOT FOUND THEN
        -- This could be a brute-force attempt, so we should be careful.
        -- Returning 'access_denied' is a safe default.
        PERFORM set_config('response.status', '400', true);
        RETURN json_build_object('error', 'access_denied', 'error_description', 'Invalid device code.');
    END IF;

    -- Check for expired request
    IF v_req.expires_at < now() THEN
        PERFORM set_config('response.status', '400', true);
        RETURN json_build_object('error', 'expired_token', 'error_description', 'The device code has expired.');
    END IF;

    -- Check if denied
    IF v_req.denied_at IS NOT NULL THEN
        PERFORM set_config('response.status', '400', true);
        RETURN json_build_object('error', 'access_denied', 'error_description', 'The authorization request was denied by the user.');
    END IF;

    -- Check if approved
    IF v_req.approved_at IS NOT NULL AND v_req.user_id IS NOT NULL THEN
        -- Check if a token has already been issued for this request
        IF v_req.token_issued_at IS NOT NULL THEN
            -- Per spec, a device code is single-use. If polled again, treat as expired.
            PERFORM set_config('response.status', '400', true);
            RETURN json_build_object('error', 'expired_token', 'error_description', 'This device code has already been used.');
        END IF;

        -- Get the user record
        SELECT * INTO v_user FROM auth.user WHERE id = v_req.user_id;

        -- Set token expiration
        v_access_expires := clock_timestamp() + (coalesce(nullif(current_setting('app.settings.access_jwt_exp', true),'')::int, 3600) || ' seconds')::interval;

        -- Generate access token claims
        v_access_claims := auth.build_jwt_claims(
            p_email => v_user.email,
            p_expires_at => v_access_expires,
            p_type => 'access',
            p_additional_claims => jsonb_build_object(
                'scope', v_req.scope,
                'client_id', v_req.client_id
            )
        );

        -- Sign the token
        SELECT auth.generate_jwt(v_access_claims) INTO v_access_token;
        
        -- Mark the request as completed
        UPDATE auth.device_authorization_request
        SET token_issued_at = now()
        WHERE id = v_req.id;

        -- Return the access token
        RETURN json_build_object(
            'access_token', v_access_token,
            'token_type', 'bearer',
            'expires_in', extract(epoch from (v_access_expires - now()))::integer
        );
    END IF;

    -- If not expired, denied, or approved, then it must be pending.
    PERFORM set_config('response.status', '400', true);
    RETURN json_build_object('error', 'authorization_pending', 'error_description', 'Waiting for user to authorize the device.');
END;
$$;

GRANT EXECUTE ON FUNCTION public.poll_device_authorization(text) TO anon;

COMMIT;

BEGIN;

-- Table to store pending device authorization requests
CREATE TABLE auth.device_authorization_request (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_code text UNIQUE NOT NULL,
    user_code text UNIQUE NOT NULL,
    client_id text NOT NULL,
    scope text,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    user_id integer REFERENCES auth.user(id) ON DELETE CASCADE,
    approved_at timestamptz,
    denied_at timestamptz,
    token_issued_at timestamptz
);

GRANT SELECT, INSERT, UPDATE ON auth.device_authorization_request TO authenticated;
GRANT USAGE ON SEQUENCE auth.device_authorization_request_id_seq TO authenticated;

-- Helper function to generate random strings for codes
CREATE OR REPLACE FUNCTION auth.generate_random_string(
    length integer,
    characters text DEFAULT 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
) RETURNS text AS $$
DECLARE
    result text := '';
    i integer;
    chars_len integer := length(characters);
BEGIN
    FOR i IN 1..length LOOP
        result := result || substr(characters, floor(random() * chars_len) + 1, 1);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- RPC function for clients to start the device authorization flow
CREATE OR REPLACE FUNCTION public.request_device_authorization(p_client_id text, p_scope text)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    v_device_code text;
    v_user_code text;
    v_verification_uri text;
    v_expires_in integer;
    v_interval integer;
BEGIN
    -- Generate unique codes
    LOOP
        v_device_code := auth.generate_random_string(40, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789');
        EXIT WHEN NOT EXISTS (SELECT 1 FROM auth.device_authorization_request WHERE device_code = v_device_code);
    END LOOP;

    LOOP
        v_user_code := auth.generate_random_string(8);
        EXIT WHEN NOT EXISTS (SELECT 1 FROM auth.device_authorization_request WHERE user_code = v_user_code);
    END LOOP;

    -- These app.settings are assumed to be set in the PostgREST configuration.
    v_verification_uri := coalesce(nullif(current_setting('app.settings.statbus_url', true), ''), 'http://localhost:3020') || '/device';
    v_expires_in := coalesce(nullif(current_setting('app.settings.device_code_exp', true),'')::int, 300); -- 5 minutes
    v_interval := coalesce(nullif(current_setting('app.settings.device_poll_interval', true),'')::int, 5); -- 5 seconds

    -- Store the request
    INSERT INTO auth.device_authorization_request (device_code, user_code, client_id, scope, expires_at)
    VALUES (v_device_code, v_user_code, p_client_id, p_scope, now() + (v_expires_in || ' seconds')::interval);

    -- Return the response required by the OAuth2 Device Authorization Grant spec
    RETURN json_build_object(
        'device_code', v_device_code,
        'user_code', v_user_code,
        'verification_uri', v_verification_uri,
        'expires_in', v_expires_in,
        'interval', v_interval
    );
END;
$$;

-- Grant access to the function. It's public, so `anon` should be able to call it.
GRANT EXECUTE ON FUNCTION public.request_device_authorization(text, text) TO anon;

COMMIT;

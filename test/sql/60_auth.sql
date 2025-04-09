-- Test file for authentication system
BEGIN;

\i test/setup.sql

-- Set up test environment
-- Set JWT secret for testing using local settings
SET LOCAL "app.settings.jwt_secret" TO 'test-jwt-secret-for-testing-only';
SET LOCAL "app.settings.jwt_exp" TO '3600';
SET LOCAL "app.settings.refresh_jwt_exp" TO '86400';
SET LOCAL "app.settings.deployment_slot_code" TO 'test';

-- Create test users if they don't exist
INSERT INTO auth.user (email, password, encrypted_password, email_confirmed_at, statbus_role)
VALUES 
    ('test.admin@example.com', 'admin123', crypt('admin123', gen_salt('bf')), now(), 'admin_user'),
    ('test.regular@example.com', 'regular123', crypt('regular123', gen_salt('bf')), now(), 'regular_user'),
    ('test.restricted@example.com', 'restricted123', crypt('restricted123', gen_salt('bf')), now(), 'restricted_user'),
    ('test.external@example.com', 'external123', crypt('external123', gen_salt('bf')), now(), 'external_user'),
    ('test.unconfirmed@example.com', 'unconfirmed123', crypt('unconfirmed123', gen_salt('bf')), NULL, 'regular_user')
ON CONFLICT (email) 
DO UPDATE SET 
    encrypted_password = EXCLUDED.encrypted_password,
    email_confirmed_at = EXCLUDED.email_confirmed_at,
    statbus_role = EXCLUDED.statbus_role;

-- Helper function to extract and verify JWT claims using pgjwt
CREATE OR REPLACE FUNCTION test.verify_jwt_claims(token text, expected_claims jsonb)
RETURNS boolean AS $$
DECLARE
    verification record;
    payload jsonb;
    claim_key text;
    claim_value jsonb;
BEGIN
    -- Use pgjwt's verify function to decode the token
    -- We're not verifying the signature here, just extracting the payload
    SELECT * INTO verification FROM verify(token, 'test-jwt-secret-for-testing-only', 'HS256');
    
    -- Convert payload to jsonb
    payload := verification.payload::jsonb;
    
    -- Check each expected claim
    FOR claim_key, claim_value IN SELECT * FROM jsonb_each(expected_claims)
    LOOP
        IF payload->claim_key IS DISTINCT FROM claim_value THEN
            RAISE NOTICE 'Claim % mismatch: expected %, got %', 
                claim_key, claim_value, payload->claim_key;
            RETURN false;
        END IF;
    END LOOP;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Helper function to extract cookies from response headers
CREATE OR REPLACE FUNCTION test.extract_cookies()
RETURNS TABLE(cookie_name text, cookie_value text, expires_at timestamptz) AS $$
DECLARE
    headers jsonb;
    header_obj jsonb;
    cookie_str text;
    cookie_parts text[];
    cookie_attrs text[];
    attr text;
    expires_str text;
    i integer;
BEGIN
    -- Get response headers
    headers := nullif(current_setting('response.headers', true), '')::jsonb;
    
    -- Process each header
    IF headers IS NOT NULL THEN
        FOR header_obj IN SELECT * FROM jsonb_array_elements(headers)
        LOOP
            IF header_obj ? 'Set-Cookie' THEN
                cookie_str := header_obj->>'Set-Cookie';
                
                -- Extract cookie name and value
                cookie_parts := regexp_split_to_array(split_part(cookie_str, ';', 1), '=');
                IF array_length(cookie_parts, 1) >= 2 THEN
                    cookie_name := cookie_parts[1];
                    cookie_value := cookie_parts[2];
                    
                    -- Extract expiration date if present
                    expires_at := NULL;
                    cookie_attrs := string_to_array(substring(cookie_str from position(';' in cookie_str) + 1), ';');
                    
                    IF cookie_attrs IS NOT NULL THEN
                        FOREACH attr IN ARRAY cookie_attrs
                        LOOP
                            attr := trim(attr);
                            IF position('Expires=' in attr) = 1 THEN
                                expires_str := substring(attr from 9); -- 'Expires=' is 8 chars + 1
                                
                                -- Try to convert to timestamptz
                                BEGIN
                                    -- HTTP date format is like: "Thu, 01 Jan 1970 00:00:00 GMT"
                                    -- Convert to timestamptz
                                    expires_at := to_timestamp(expires_str, 'Dy, DD Mon YYYY HH24:MI:SS GMT');
                                EXCEPTION WHEN OTHERS THEN
                                    -- If conversion fails, leave as NULL
                                    RAISE DEBUG 'Could not convert expires date: %', expires_str;
                                END;
                                
                                EXIT;
                            END IF;
                        END LOOP;
                    END IF;
                    
                    RETURN NEXT;
                END IF;
            END IF;
        END LOOP;
    END IF;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- Test 1: User Login Success
\echo '=== Test 1: User Login Success ==='
DO $$
DECLARE
    login_result jsonb;
    expected_claims jsonb;
    access_token text;
    refresh_jwt text;
    cookies record;
    has_access_cookie boolean := false;
    has_refresh_cookie boolean := false;
BEGIN
    -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
        )::text, 
        true
    );

    -- Perform login
    SELECT public.login('test.regular@example.com', 'regular123')::jsonb INTO login_result;
    
    -- Debug the login result
    RAISE DEBUG 'Login result: %', login_result;
    
    -- Debug the returned headers from the login function
    RAISE DEBUG 'Response headers: %', nullif(current_setting('response.headers', true), '')::jsonb;
    
    -- Verify login result contains expected fields
    ASSERT login_result ? 'access_jwt', 'Login result should contain access_jwt';
    ASSERT login_result ? 'refresh_jwt', 'Login result should contain refresh_jwt';
    ASSERT login_result ? 'user_id', 'Login result should contain user_id';
    ASSERT login_result ? 'role', 'Login result should contain role';
    ASSERT login_result ? 'statbus_role', 'Login result should contain statbus_role';
    ASSERT login_result ? 'email', 'Login result should contain email';
    
    -- Verify token claims
    access_token := login_result->>'access_jwt';
    expected_claims := jsonb_build_object(
        'role', 'test.regular@example.com',
        'statbus_role', 'regular_user',
        'email', 'test.regular@example.com',
        'type', 'access'
    );
    
    ASSERT test.verify_jwt_claims(access_token, expected_claims), 
        'Access token claims do not match expected values';
    
    -- Verify refresh token claims
    refresh_jwt := login_result->>'refresh_jwt';
    expected_claims := jsonb_build_object(
        'role', 'test.regular@example.com',
        'statbus_role', 'regular_user',
        'email', 'test.regular@example.com',
        'type', 'refresh'
    );
    
    ASSERT test.verify_jwt_claims(refresh_jwt, expected_claims), 
        'Refresh token claims do not match expected values';
    
    -- Verify cookies were set
    FOR cookies IN SELECT * FROM test.extract_cookies()
    LOOP
        IF cookies.cookie_name = 'statbus-test' THEN
            has_access_cookie := true;
            ASSERT cookies.cookie_value = access_token, 'Access cookie value does not match token';
        ELSIF cookies.cookie_name = 'statbus-test-refresh' THEN
            has_refresh_cookie := true;
            ASSERT cookies.cookie_value = refresh_jwt, 'Refresh cookie value does not match token';
        END IF;
    END LOOP;
    
    ASSERT has_access_cookie, 'Access cookie was not set';
    ASSERT has_refresh_cookie, 'Refresh cookie was not set';
    
    -- Verify session was created in database
    ASSERT EXISTS (
        SELECT 1 FROM auth.refresh_session rs
        JOIN auth.user u ON rs.user_id = u.id
        WHERE u.email = 'test.regular@example.com'
    ), 'Refresh session was not created in database';
    
    -- Verify last_sign_in_at was updated
    ASSERT (
        SELECT last_sign_in_at > now() - interval '1 minute'
        FROM auth.user
        WHERE email = 'test.regular@example.com'
    ), 'last_sign_in_at was not updated';
    
    RAISE NOTICE 'Test 1: User Login Success - PASSED';
END;
$$;

-- Test 2: User Login Failure - Wrong Password
\echo '=== Test 2: User Login Failure - Wrong Password ==='
DO $$
DECLARE
    login_result jsonb;
BEGIN
    -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
        )::text, 
        true
    );

    -- Attempt login with wrong password
    SELECT public.login('test.regular@example.com', 'wrongpassword')::jsonb INTO login_result;
    
    -- Debug the login result
    RAISE DEBUG 'Login result (should be null): %', login_result;
    
    -- Verify login failed (result should be null)
    ASSERT login_result IS NULL, 'Login with wrong password should return null';
    
    RAISE NOTICE 'Test 2: User Login Failure - Wrong Password - PASSED';
END;
$$;

-- Test 3: User Login Failure - Unconfirmed Email
\echo '=== Test 3: User Login Failure - Unconfirmed Email ==='
DO $$
DECLARE
    login_result jsonb;
BEGIN
    -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
        )::text, 
        true
    );

    -- Attempt login with unconfirmed email
    SELECT public.login('test.unconfirmed@example.com', 'unconfirmed123')::jsonb INTO login_result;
    
    -- Debug the login result
    RAISE DEBUG 'Login result (should be null): %', login_result;
    
    -- Verify login failed (result should be null)
    ASSERT login_result IS NULL, 'Login with unconfirmed email should return null';
    
    RAISE NOTICE 'Test 3: User Login Failure - Unconfirmed Email - PASSED';
END;
$$;

-- Test 4: Token Refresh
\echo '=== Test 4: Token Refresh ==='
DO $$
DECLARE
    login_result jsonb;
    refresh_result jsonb;
    refresh_jwt text;
    refresh_session_before record;
    refresh_session_after record;
BEGIN
    -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
        )::text, 
        true
    );

    -- First login
    SELECT public.login('test.admin@example.com', 'admin123')::jsonb INTO login_result;
    RAISE DEBUG 'Login result: %', login_result;
    
    -- Debug the returned headers from the login function
    RAISE DEBUG 'Response headers: %', nullif(current_setting('response.headers', true), '')::jsonb;
    
    -- Extract and verify response headers
    DECLARE
        response_headers jsonb;
        header_obj jsonb;
        access_cookie_found boolean := false;
        refresh_cookie_found boolean := false;
        access_cookie_valid boolean := false;
        refresh_cookie_valid boolean := false;
    BEGIN
        response_headers := nullif(current_setting('response.headers', true), '')::jsonb;
        
        -- Iterate through headers to find and validate cookies
        FOR header_obj IN SELECT * FROM jsonb_array_elements(response_headers)
        LOOP
            IF header_obj ? 'Set-Cookie' THEN
                IF header_obj->>'Set-Cookie' LIKE 'statbus-test=%' THEN
                    access_cookie_found := true;
                    -- Verify HttpOnly and SameSite attributes
                    IF header_obj->>'Set-Cookie' LIKE '%HttpOnly%' AND 
                       header_obj->>'Set-Cookie' LIKE '%SameSite=Strict%' THEN
                        access_cookie_valid := true;
                    END IF;
                ELSIF header_obj->>'Set-Cookie' LIKE 'statbus-test-refresh=%' THEN
                    refresh_cookie_found := true;
                    -- Verify HttpOnly and SameSite attributes
                    IF header_obj->>'Set-Cookie' LIKE '%HttpOnly%' AND 
                       header_obj->>'Set-Cookie' LIKE '%SameSite=Strict%' THEN
                        refresh_cookie_valid := true;
                    END IF;
                END IF;
            END IF;
        END LOOP;
        
        -- Assert that both cookies were found and valid
        ASSERT access_cookie_found, 'Access cookie not found in response headers';
        ASSERT refresh_cookie_found, 'Refresh cookie not found in response headers';
        ASSERT access_cookie_valid, 'Access cookie missing required security attributes';
        ASSERT refresh_cookie_valid, 'Refresh cookie missing required security attributes';
        
        RAISE DEBUG 'Cookie validation passed: Access cookie and refresh cookie both have required security attributes';
    END;
        
    -- Assert login result contains expected fields
    ASSERT login_result->>'role' = 'test.admin@example.com', 'Role should match email';
    ASSERT login_result->>'email' = 'test.admin@example.com', 'Email should be returned correctly';
    ASSERT login_result->>'access_jwt' IS NOT NULL, 'Access token should be present';
    ASSERT login_result->>'statbus_role' = 'admin_user', 'Statbus role should be admin_user';
    
    -- Decode the access token and display it
    DECLARE
        access_jwt_str text;
        access_jwt_payload jsonb;
        token_verification record;
    BEGIN
        access_jwt_str := login_result->>'access_jwt';
        SELECT * INTO token_verification FROM verify(access_jwt_str, 'test-jwt-secret-for-testing-only', 'HS256');
        access_jwt_payload := token_verification.payload::jsonb;
        RAISE DEBUG 'Decoded access token: %', access_jwt_payload;
        
        -- Verify deterministic keys in the access token payload
        ASSERT access_jwt_payload->>'role' = 'test.admin@example.com', 'Role in token should match email';
        ASSERT access_jwt_payload->>'email' = 'test.admin@example.com', 'Email in token should be correct';
        ASSERT access_jwt_payload->>'type' = 'access', 'Token type should be access';
        ASSERT access_jwt_payload->>'statbus_role' = 'admin_user', 'Statbus role should be admin_user';
        
        -- Verify dynamic values are present and not null
        ASSERT access_jwt_payload->>'exp' IS NOT NULL, 'Expiration time should be present';
        ASSERT access_jwt_payload->>'iat' IS NOT NULL, 'Issued at time should be present';
        ASSERT access_jwt_payload->>'jti' IS NOT NULL, 'JWT ID should be present';
        ASSERT access_jwt_payload->>'sub' IS NOT NULL, 'Subject should be present';        
    END;
        
    refresh_jwt := login_result->>'refresh_jwt';
    
    -- Store session info before refresh
    SELECT rs.* INTO refresh_session_before
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.admin@example.com'
    ORDER BY rs.created_at DESC
    LIMIT 1;
    
    -- Debug the refresh session before refresh
    RAISE DEBUG 'Refresh session before refresh: %', row_to_json(refresh_session_before);
        
    -- Set cookies in request headers to simulate browser cookies for refresh
    PERFORM set_config('request.headers', 
        jsonb_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'cookie', format('statbus-test-refresh=%s', refresh_jwt)
        )::text, 
        true
    );
    
    -- Sleep 1 second, to ensure the iat will increase, because it counts in whole seconds.
    PERFORM pg_sleep(1);
    -- Perform token refresh
    SELECT public.refresh() INTO refresh_result;
    
    -- Debug the refresh result
    RAISE DEBUG 'Refresh result: %', refresh_result;
    
    -- Verify refresh result contains expected fields
    ASSERT refresh_result ? 'access_jwt', 'Refresh result should contain access_jwt';
    ASSERT refresh_result ? 'refresh_jwt', 'Refresh result should contain refresh_jwt';
    ASSERT refresh_result ? 'user_id', 'Refresh result should contain user_id';
    ASSERT refresh_result ? 'role', 'Refresh result should contain role';
    ASSERT refresh_result ? 'statbus_role', 'Refresh result should contain statbus_role';
    ASSERT refresh_result ? 'email', 'Refresh result should contain email';
        
    -- Debug information to help identify token issues
    RAISE DEBUG 'Original access token: %', login_result->>'access_jwt';
    RAISE DEBUG 'New access token: %', refresh_result->>'access_jwt';
    
    -- Decode tokens to compare their contents
    DECLARE
        login_access_jwt_payload jsonb;
        refresh_access_jwt_payload jsonb;
        login_access_jwt_verification record;
        refresh_access_jwt_verification record;
    BEGIN
        -- Decode the tokens
        SELECT * INTO login_access_jwt_verification FROM verify(login_result->>'access_jwt', 'test-jwt-secret-for-testing-only', 'HS256');
        SELECT * INTO refresh_access_jwt_verification FROM verify(refresh_result->>'access_jwt', 'test-jwt-secret-for-testing-only', 'HS256');
        
        -- Convert payloads to jsonb
        login_access_jwt_payload := login_access_jwt_verification.payload::jsonb;
        refresh_access_jwt_payload := refresh_access_jwt_verification.payload::jsonb;
        
        -- Debug the token payloads
        RAISE DEBUG 'Original access jwt payload: %', login_access_jwt_payload;
        RAISE DEBUG 'New access jwt payload: %', refresh_access_jwt_payload;
        
        -- Verify token properties
        -- Check that exp (expiration time) increases
        ASSERT (refresh_access_jwt_payload->>'exp')::numeric > (login_access_jwt_payload->>'exp')::numeric,
            'New access jwt should have a later expiration time';
            
        -- Check that iat (issued at time) increases or stays the same
        ASSERT (refresh_access_jwt_payload->>'iat')::numeric >= (login_access_jwt_payload->>'iat')::numeric,
            'New access jwt should have same or later issued at time';
            
        -- Check that sub (subject) remains the same
        ASSERT refresh_access_jwt_payload->>'sub' = login_access_jwt_payload->>'sub',
            'Subject should remain the same across token refreshes';
            
        -- Check that jti (JWT ID) is different for access tokens
        -- Access tokens should have unique JTIs
        ASSERT refresh_access_jwt_payload->>'jti' <> login_access_jwt_payload->>'jti',
            'Access tokens should have different JTIs';
            
        -- Check that fixed value fields remain the same
        ASSERT refresh_access_jwt_payload->>'role' = login_access_jwt_payload->>'role',
            'Role should remain the same';
        ASSERT refresh_access_jwt_payload->>'email' = login_access_jwt_payload->>'email',
            'Email should remain the same';
        ASSERT refresh_access_jwt_payload->>'type' = login_access_jwt_payload->>'type',
            'Token type should remain the same';
        ASSERT refresh_access_jwt_payload->>'statbus_role' = login_access_jwt_payload->>'statbus_role',
            'Statbus role should remain the same';
    END;
    
    -- Compare tokens
    ASSERT refresh_result->>'access_jwt' <> login_result->>'access_jwt', 'New access token should be different';
    ASSERT refresh_result->>'refresh_jwt' <> login_result->>'refresh_jwt', 'New refresh token should be different';
    
    -- Verify session was updated
    SELECT rs.* INTO refresh_session_after
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.admin@example.com'
    ORDER BY rs.created_at DESC
    LIMIT 1;
    
    ASSERT refresh_session_after.refresh_version = refresh_session_before.refresh_version + 1, 
        'Session version should be incremented';
    ASSERT refresh_session_after.last_used_at > refresh_session_before.last_used_at, 
        'Session last_used_at should be updated';
    
    RAISE NOTICE 'Test 4: Token Refresh - PASSED';
END;
$$;

-- Test 5: Logout
\echo '=== Test 5: Logout ==='
DO $$
DECLARE
    login_result jsonb;
    logout_result jsonb;
    session_count_before integer;
    session_count_after integer;
    has_cleared_access_cookie boolean := false;
    has_cleared_refresh_cookie boolean := false;
    cookies record;
    access_jwt text;
    refresh_jwt text;
BEGIN
    -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
        )::text, 
        true
    );

    -- First login to create a session
    SELECT public.login('test.restricted@example.com', 'restricted123')::jsonb INTO login_result;
    RAISE DEBUG 'Login result: %', login_result;
    
    -- Extract tokens from login result
    access_jwt := login_result->>'access_jwt';
    refresh_jwt := login_result->>'refresh_jwt';
    
    -- Debug the returned headers from the login function
    RAISE DEBUG 'Response headers after login: %', nullif(current_setting('response.headers', true), '')::jsonb;
    
    -- Count sessions before logout
    SELECT COUNT(*) INTO session_count_before
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.restricted@example.com';
    
    RAISE DEBUG 'Session count before logout: %', session_count_before;
    
    -- Set up JWT claims to simulate being logged in with the actual token
    PERFORM set_config('request.jwt.claims', 
        (SELECT payload::text FROM verify(access_jwt, 'test-jwt-secret-for-testing-only')),
        true
    );
    
    -- Set cookies in request headers to simulate browser cookies for logout
    PERFORM set_config('request.headers', 
        jsonb_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'cookie', format('statbus-test=%s; statbus-test-refresh=%s', access_jwt, refresh_jwt)
        )::text, 
        true
    );
    
    -- Perform logout
    SELECT public.logout()::jsonb INTO logout_result;
    RAISE DEBUG 'Logout result: %', logout_result;
    
    -- Debug the returned headers from the logout function
    RAISE DEBUG 'Response headers after logout: %', nullif(current_setting('response.headers', true), '')::jsonb;
    
    -- Verify logout result
    ASSERT logout_result->>'success' = 'true', 'Logout should return success: true';
    
    -- Count sessions after logout
    SELECT COUNT(*) INTO session_count_after
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.restricted@example.com';
    
    RAISE DEBUG 'Session count after logout: %', session_count_after;
    
    -- Verify sessions were deleted
    ASSERT session_count_after < session_count_before, 
        'Sessions should be deleted after logout';
    
    -- Verify cookies were cleared
    FOR cookies IN SELECT * FROM test.extract_cookies()
    LOOP
        RAISE DEBUG 'Cookie found: name=%, value=%, expires=%', cookies.cookie_name, cookies.cookie_value, cookies.expires_at;
        IF cookies.cookie_name = 'statbus-test' AND 
           (cookies.cookie_value = '' OR cookies.expires_at = '1970-01-01 00:00:00+00'::timestamptz) THEN
            has_cleared_access_cookie := true;
        ELSIF cookies.cookie_name = 'statbus-test-refresh' AND 
              (cookies.cookie_value = '' OR cookies.expires_at = '1970-01-01 00:00:00+00'::timestamptz) THEN
            has_cleared_refresh_cookie := true;
        END IF;
    END LOOP;
    
    ASSERT has_cleared_access_cookie, 'Access cookie was not cleared';
    ASSERT has_cleared_refresh_cookie, 'Refresh cookie was not cleared';
    
    RAISE NOTICE 'Test 5: Logout - PASSED';
END;
$$;

-- Test 6: Role Management
\echo '=== Test 6: Role Management ==='
DO $$
DECLARE
    login_result jsonb;
    grant_result boolean;
    revoke_result boolean;
    user_sub uuid;
    original_role public.statbus_role;
    new_role public.statbus_role;
    access_jwt text;
    user_email text;
    role_exists boolean;
    role_granted boolean;
BEGIN
    -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
        )::text, 
        true
    );

    -- Get user sub and original role for the target user
    SELECT sub, statbus_role, email INTO user_sub, original_role, user_email
    FROM auth.user
    WHERE email = 'test.external@example.com';
    
    RAISE DEBUG 'Testing role management for user: % (sub: %, original role: %)', 
        user_email, user_sub, original_role;
    
    -- Check if the user role exists in PostgreSQL
    SELECT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = user_email
    ) INTO role_exists;
    
    RAISE DEBUG 'User role exists in PostgreSQL: %', role_exists;
    
    -- Check current role grants
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = original_role::text AND r2.rolname = user_email
    ) INTO role_granted;
    
    RAISE DEBUG 'Original role % is granted to user %: %', 
        original_role, user_email, role_granted;
    
    -- First login as admin to get valid JWT
    SELECT public.login('test.admin@example.com', 'admin123')::jsonb INTO login_result;
    RAISE DEBUG 'Login result: %', login_result;
    
    -- Extract access token from login result
    access_jwt := login_result->>'access_jwt';
    
    -- Set up JWT claims using the actual token
    PERFORM set_config('request.jwt.claims', 
        (SELECT payload::text FROM verify(access_jwt, 'test-jwt-secret-for-testing-only')),
        true
    );
    
    -- Set cookies in request headers to simulate browser cookies
    PERFORM set_config('request.headers', 
        jsonb_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'cookie', format('statbus-test=%s', access_jwt)
        )::text, 
        true
    );
    
    -- Check if restricted_user role exists
    SELECT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'restricted_user'
    ) INTO role_exists;
    
    RAISE DEBUG 'restricted_user role exists in PostgreSQL: %', role_exists;
    
    -- Check if restricted_user is already granted to the user
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'restricted_user' AND r2.rolname = user_email
    ) INTO role_granted;
    
    RAISE DEBUG 'restricted_user role is already granted to user %: %', 
        user_email, role_granted;
    
    -- Grant restricted_user role
    RAISE DEBUG 'Attempting to grant restricted_user role to %', user_email;
    SELECT public.grant_role(user_sub, 'restricted_user'::public.statbus_role) INTO grant_result;
    RAISE DEBUG 'Grant result: %', grant_result;
    
    -- Check if the role was actually granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'restricted_user' AND r2.rolname = user_email
    ) INTO role_granted;
    
    RAISE DEBUG 'After grant: restricted_user role is granted to user %: %', 
        user_email, role_granted;
    
    -- Verify grant was successful
    ASSERT grant_result = true, 'Grant role should return true';
    
    -- Verify role was updated in database
    SELECT statbus_role INTO new_role
    FROM auth.user
    WHERE sub = user_sub;
    
    RAISE DEBUG 'User role in database after grant: %', new_role;
    
    ASSERT new_role = 'restricted_user', 
        'User role should be updated to restricted_user';
    
    -- Check if regular_user role exists
    SELECT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'regular_user'
    ) INTO role_exists;
    
    RAISE DEBUG 'regular_user role exists in PostgreSQL: %', role_exists;
    
    -- Check if regular_user is already granted to the user
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'regular_user' AND r2.rolname = user_email
    ) INTO role_granted;
    
    RAISE DEBUG 'regular_user role is already granted to user %: %', 
        user_email, role_granted;
    
    -- Revoke role (which sets it back to regular_user)
    RAISE DEBUG 'Attempting to revoke role from % (setting back to regular_user)', user_email;
    SELECT public.revoke_role(user_sub) INTO revoke_result;
    RAISE DEBUG 'Revoke result: %', revoke_result;
    
    -- Check if the role was actually granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'regular_user' AND r2.rolname = user_email
    ) INTO role_granted;
    
    RAISE DEBUG 'After revoke: regular_user role is granted to user %: %', 
        user_email, role_granted;
    
    -- Verify revoke was successful
    ASSERT revoke_result = true, 'Revoke role should return true';
    
    -- Verify role was reset to regular_user
    SELECT statbus_role INTO new_role
    FROM auth.user
    WHERE sub = user_sub;
    
    RAISE DEBUG 'User role in database after revoke: %', new_role;
    
    ASSERT new_role = 'regular_user', 
        'User role should be reset to regular_user';
    
    -- Reset to original role
    RAISE DEBUG 'Resetting user % to original role: %', user_email, original_role;
    PERFORM public.grant_role(user_sub, original_role);
    
    -- Verify final role state
    SELECT statbus_role INTO new_role
    FROM auth.user
    WHERE sub = user_sub;
    
    RAISE DEBUG 'Final user role in database: %', new_role;
    
    -- Check if the original role was actually granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = original_role::text AND r2.rolname = user_email
    ) INTO role_granted;
    
    RAISE DEBUG 'Final check: original role % is granted to user %: %', 
        original_role, user_email, role_granted;
    
    RAISE NOTICE 'Test 6: Role Management - PASSED';
END;
$$;

-- Test 7: Session Management
\echo '=== Test 7: Session Management ==='
DO $$
DECLARE
    login_result jsonb;
    sessions_result jsonb[];
    session_id integer;
    session_jti uuid;
    revoke_result boolean;
    session_count_before integer;
    session_count_after integer;
    access_jwt text;
    jwt_claims json;
BEGIN
    -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
        )::text, 
        true
    );

    -- First login to create a session
    SELECT public.login('test.regular@example.com', 'regular123')::jsonb INTO login_result;
    
    -- Extract access token from login result
    access_jwt := login_result->>'access_jwt';
    
    -- Set up JWT claims using the actual token
    SELECT payload::json INTO jwt_claims 
    FROM verify(access_jwt, 'test-jwt-secret-for-testing-only');
    
    PERFORM set_config('request.jwt.claims', jwt_claims::text, true);
    
    -- Set cookies in request headers to simulate browser cookies
    PERFORM set_config('request.headers', 
        jsonb_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'cookie', format('statbus-test=%s', access_jwt)
        )::text, 
        true
    );
    
    -- List active sessions
    SELECT array_agg(s::jsonb) INTO sessions_result
    FROM public.list_active_sessions() s;
    
    -- Debug the sessions result
    RAISE DEBUG 'Active sessions: %', sessions_result;
    
    -- Verify sessions were returned
    ASSERT array_length(sessions_result, 1) > 0, 'Should have at least one active session';
    
    -- Get session ID for revocation
    SELECT (sessions_result[1]->>'id')::integer INTO session_id;
    
    -- Get the JTI for the session
    SELECT jti INTO session_jti
    FROM auth.refresh_session
    WHERE id = session_id;
    
    -- Count sessions before revocation
    SELECT COUNT(*) INTO session_count_before
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.regular@example.com';
    
    -- Revoke a specific session
    SELECT public.revoke_session(session_jti) INTO revoke_result;
    
    -- Debug the revoke result
    RAISE DEBUG 'Revoke session result: %', revoke_result;
    
    -- Verify revocation was successful
    ASSERT revoke_result = true, 'Revoke session should return true';
    
    -- Count sessions after revocation
    SELECT COUNT(*) INTO session_count_after
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.regular@example.com';
    
    -- Verify session was deleted
    ASSERT session_count_after = session_count_before - 1, 
        'One session should be deleted after revocation';
    
    RAISE NOTICE 'Test 7: Session Management - PASSED';
END;
$$;

-- Test 8: Auth Helper Functions
\echo '=== Test 8: Auth Helper Functions ==='
DO $$
DECLARE
    login_result jsonb;
    test_email text := 'test.admin@example.com';
    test_sub uuid;
    test_id integer;
    test_role public.statbus_role;
    access_jwt text;
    jwt_claims json;
BEGIN
    -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
        )::text, 
        true
    );

    -- Get user details for verification
    SELECT sub, id, statbus_role INTO test_sub, test_id, test_role
    FROM auth.user
    WHERE email = test_email;
    
    -- Login to get a real token
    SELECT public.login(test_email, 'admin123')::jsonb INTO login_result;
    
    -- Debug the login result
    RAISE DEBUG 'Login result: %', login_result;
    
    -- Extract access token from login result
    access_jwt := login_result->>'access_jwt';
    
    -- Set up JWT claims using the actual token
    SELECT payload::json INTO jwt_claims 
    FROM verify(access_jwt, 'test-jwt-secret-for-testing-only');
    
    PERFORM set_config('request.jwt.claims', jwt_claims::text, true);
    
    -- Test auth.sub()
    DECLARE
        sub_result uuid;
    BEGIN
        sub_result := auth.sub();
        RAISE DEBUG 'auth.sub() result: %, expected: %', sub_result, test_sub;
        ASSERT sub_result = test_sub, 'auth.sub() should return the correct user sub';
    END;
    
    -- Test auth.uid()
    DECLARE
        uid_result integer;
    BEGIN
        uid_result := auth.uid();
        RAISE DEBUG 'auth.uid() result: %, expected: %', uid_result, test_id;
        ASSERT uid_result = test_id, 'auth.uid() should return the correct user id';
    END;
    
    -- Test auth.role()
    DECLARE
        role_result text;
    BEGIN
        role_result := auth.role();
        RAISE DEBUG 'auth.role() result: %, expected: %', role_result, test_email;
        ASSERT role_result = test_email, 'auth.role() should return the correct role';
    END;
    
    -- Test auth.email()
    DECLARE
        email_result text;
    BEGIN
        email_result := auth.email();
        RAISE DEBUG 'auth.email() result: %, expected: %', email_result, test_email;
        ASSERT email_result = test_email, 'auth.email() should return the correct email';
    END;
    
    -- Test auth.statbus_role()
    DECLARE
        statbus_role_result public.statbus_role;
    BEGIN
        statbus_role_result := auth.statbus_role();
        RAISE DEBUG 'auth.statbus_role() result: %, expected: %', statbus_role_result, test_role;
        ASSERT statbus_role_result = test_role, 'auth.statbus_role() should return the correct statbus_role';
    END;
    
    RAISE NOTICE 'Test 8: Auth Helper Functions - PASSED';
END;
$$;

-- Test 9: JWT Claims Building
\echo '=== Test 9: JWT Claims Building ==='
DO $$
DECLARE
    claims jsonb;
    test_email text := 'test.regular@example.com';
    test_sub uuid;
    test_role public.statbus_role;
    test_expires_at timestamptz;
    test_jwt text;
    jwt_payload jsonb;
BEGIN
    -- Get user details
    SELECT sub, statbus_role INTO test_sub, test_role
    FROM auth.user
    WHERE email = test_email;
    
    -- Set test expiration time
    test_expires_at := clock_timestamp() + interval '1 hour';
    
    -- Build claims with email only
    claims := auth.build_jwt_claims(test_email);
    
    -- Debug the claims
    RAISE DEBUG 'Basic JWT claims: %', claims;
    
    -- Verify basic claims
    ASSERT claims ? 'role', 'Claims should contain role';
    ASSERT claims ? 'statbus_role', 'Claims should contain statbus_role';
    ASSERT claims ? 'sub', 'Claims should contain sub';
    ASSERT claims ? 'email', 'Claims should contain email';
    ASSERT claims ? 'type', 'Claims should contain type';
    ASSERT claims ? 'iat', 'Claims should contain iat';
    ASSERT claims ? 'exp', 'Claims should contain exp';
    ASSERT claims ? 'jti', 'Claims should contain jti';
    
    -- Verify claim values
    ASSERT claims->>'role' = test_email, 'role claim should match email';
    ASSERT claims->>'statbus_role' = test_role::text, 'statbus_role claim should match user role';
    ASSERT claims->>'sub' = test_sub::text, 'sub claim should match user sub';
    ASSERT claims->>'email' = test_email, 'email claim should match email';
    ASSERT claims->>'type' = 'access', 'type claim should be access by default';
    
    -- Build claims with additional parameters
    claims := auth.build_jwt_claims(
        p_email => test_email,
        p_type => 'refresh',
        p_expires_at => test_expires_at,
        p_additional_claims => jsonb_build_object('custom_claim', 'test_value')
    );
    
    -- Debug the claims with additional parameters
    RAISE DEBUG 'Advanced JWT claims: %', claims;
    
    -- Verify additional parameters
    ASSERT claims->>'type' = 'refresh', 'type claim should be refresh';
    ASSERT claims->>'custom_claim' = 'test_value', 'custom claim should be included';
    ASSERT (claims->>'exp')::numeric = extract(epoch from test_expires_at)::integer, 
        'exp claim should match provided expiration time';
    
    -- Test generating a JWT from claims
    SELECT auth.generate_jwt(claims) INTO test_jwt;
    
    -- Debug the generated JWT
    RAISE DEBUG 'Generated JWT: %', test_jwt;
    
    -- Verify the JWT can be decoded
    SELECT payload::jsonb INTO jwt_payload 
    FROM verify(test_jwt, 'test-jwt-secret-for-testing-only');
    
    -- Debug the decoded JWT payload
    RAISE DEBUG 'Decoded JWT payload: %', jwt_payload;
    
    -- Verify JWT payload matches claims
    ASSERT jwt_payload->>'role' = claims->>'role', 'JWT role should match claims';
    ASSERT jwt_payload->>'type' = 'refresh', 'JWT type should be refresh';
    ASSERT jwt_payload->>'custom_claim' = 'test_value', 'JWT should include custom claims';
    
    RAISE NOTICE 'Test 9: JWT Claims Building - PASSED';
END;
$$;

-- Test 10: JWT Tampering Detection
\echo '=== Test 10: JWT Tampering Detection ==='
DO $$
DECLARE
    login_result_admin jsonb;
    login_result_regular jsonb;
    tampered_access_jwt text;
    tampered_refresh_jwt text;
    tampered_claims jsonb;
    refresh_result jsonb;
    auth_status_result jsonb;
    admin_email text := 'test.admin@example.com';
    regular_email text := 'test.regular@example.com';
    admin_access_jwt text;
    admin_refresh_jwt text;
    regular_access_jwt text;
    admin_claims jsonb;
    regular_claims jsonb;
    random_jti uuid := gen_random_uuid();
    wrong_secret text := 'wrong-jwt-secret-for-testing-only';
BEGIN
    -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
        )::text, 
        true
    );

    -- First login as admin to get valid tokens
    SELECT public.login(admin_email, 'admin123')::jsonb INTO login_result_admin;
    admin_access_jwt := login_result_admin->>'access_jwt';
    admin_refresh_jwt := login_result_admin->>'refresh_jwt';
    
    -- Get admin token claims
    SELECT payload::jsonb INTO admin_claims 
    FROM verify(admin_access_jwt, 'test-jwt-secret-for-testing-only');
    
    -- Login as regular user to get valid tokens
    SELECT public.login(regular_email, 'regular123')::jsonb INTO login_result_regular;
    regular_access_jwt := login_result_regular->>'access_jwt';
    
    -- Get regular user token claims
    SELECT payload::jsonb INTO regular_claims 
    FROM verify(regular_access_jwt, 'test-jwt-secret-for-testing-only');
    
    -- Test 1: Tamper with access JWT to change role without changing signature
    -- This simulates a user trying to elevate privileges by modifying the token payload
    -- without knowing the JWT secret (which would be required to create a valid signature)
    -- Approach 1: Change the payload but keep the original (now invalid) signature
    DECLARE
        tampered_access_payload jsonb;
    BEGIN
        -- Create tampered claims by changing role from regular to admin
        -- but keeping the same signature (which will now be invalid)
        tampered_access_payload := jsonb_set(
            regular_claims,
            '{role}',
            to_jsonb(admin_email::text)
        );
        tampered_access_payload := jsonb_set(
            tampered_access_payload,
            '{statbus_role}',
            to_jsonb('admin_user'::public.statbus_role)
        );
        
        -- Manually construct a tampered JWT with invalid signature
        -- Format: base64(header).base64(tampered_payload).original_signature
        DECLARE
            header text;
            payload text;
            signature text;
            parts text[];
        BEGIN
            -- Split the original token
            parts := string_to_array(regular_access_jwt, '.');
            header := parts[1];
            signature := parts[3];
            
            -- Use the same base64url encoding that pgjwt uses
            -- This ensures compatibility with the verify function
            SELECT url_encode(convert_to(tampered_access_payload::text, 'UTF8')) INTO payload;
            
            -- Construct the tampered token
            tampered_access_jwt := header || '.' || payload || '.' || signature;
        END;
        
        -- Set the tampered token in the JWT claims
        BEGIN
            -- This should fail because the signature is now invalid
            PERFORM set_config('request.jwt.claims', 
                (SELECT payload::text FROM verify(tampered_access_jwt, 'test-jwt-secret-for-testing-only')),
                true
            );
            
            -- If we get here, the verification didn't fail as expected
            RAISE EXCEPTION 'Tampered access token was incorrectly verified as valid';
        EXCEPTION WHEN OTHERS THEN
            -- This is expected - the token should be rejected
            RAISE DEBUG 'Tampered access token was correctly rejected: %', SQLERRM;
        END;
    END;
    
    -- Test 2: Try to create a token with an incorrect JWT secret
    -- This simulates an attacker who doesn't know the real JWT secret but tries to forge a token
    DECLARE
        forged_payload jsonb;
        forged_jwt text;
        forged_result jsonb;
    BEGIN
        -- Create a payload with admin privileges
        forged_payload := jsonb_build_object(
            'role', admin_email,
            'statbus_role', 'admin_user',
            'email', admin_email,
            'sub', (SELECT sub::text FROM auth.user WHERE email = admin_email),
            'type', 'access',
            'iat', extract(epoch from clock_timestamp())::integer,
            'exp', extract(epoch from clock_timestamp() + interval '1 hour')::integer,
            'jti', gen_random_uuid()
        );
        
        -- Sign the payload with the wrong secret
        -- This simulates an attacker trying to forge a token without knowing the real secret
        forged_jwt := sign(
            forged_payload::json, 
            wrong_secret,  -- Using wrong secret here
            'HS256'
        );
        
        -- Debug the forged token
        RAISE DEBUG 'Forged JWT with wrong secret: %', forged_jwt;
        
        -- Set the forged token in the JWT claims
        BEGIN
            -- This should fail because the signature is invalid
            PERFORM set_config('request.jwt.claims', 
                (SELECT payload::text FROM verify(forged_jwt, 'test-jwt-secret-for-testing-only')),
                true
            );
            
            -- If we get here, the verification didn't fail as expected
            RAISE EXCEPTION 'Forged token with wrong secret was incorrectly verified as valid';
        EXCEPTION WHEN OTHERS THEN
            -- This is expected - the token should be rejected
            RAISE DEBUG 'Forged token with wrong secret was correctly rejected: %', SQLERRM;
        END;
    END;
    
    -- Test 3: Try to use a refresh token with a non-existent session JTI
    DECLARE
        tampered_refresh_payload jsonb;
        tampered_refresh_result jsonb;
    BEGIN
        -- Create tampered claims by changing the JTI to a random UUID
        tampered_refresh_payload := jsonb_set(
            (SELECT payload::jsonb FROM verify(admin_refresh_jwt, 'test-jwt-secret-for-testing-only')),
            '{jti}',
            to_jsonb(random_jti::text)
        );
        
        -- Manually construct a tampered JWT with valid signature but non-existent session
        DECLARE
            header text;
            payload text;
            signature text;
            parts text[];
        BEGIN
            -- Split the original token
            parts := string_to_array(admin_refresh_jwt, '.');
            header := parts[1];
            
            -- Use the same base64url encoding that pgjwt uses
            -- This ensures compatibility with the verify function
            SELECT url_encode(convert_to(tampered_refresh_payload::text, 'UTF8')) INTO payload;
            
            -- Use the original signature from the valid token
            -- This simulates an attacker who doesn't know the secret
            -- They can only modify the payload but can't create a valid signature
            signature := parts[3];
            
            -- Construct the tampered token
            tampered_refresh_jwt := header || '.' || payload || '.' || signature;
        END;
        
        -- Set cookies in request headers with the tampered refresh token
        PERFORM set_config('request.headers', 
            jsonb_build_object(
                'x-forwarded-for', '127.0.0.1',
                'user-agent', 'Test User Agent',
                'cookie', format('statbus-test-refresh=%s', tampered_refresh_jwt)
            )::text, 
            true
        );
        
        -- Try to refresh with the tampered token
        SELECT public.refresh()::jsonb INTO tampered_refresh_result;
        
        -- Debug the result
        RAISE DEBUG 'Refresh result with non-existent session: %', tampered_refresh_result;
        
        -- Verify the refresh was rejected
        ASSERT tampered_refresh_result ? 'error', 
            'Refresh with non-existent session should return an error';
    END;
    
    -- Test 4: Try to impersonate another user with a valid refresh token
    DECLARE
        impersonation_payload jsonb;
        impersonation_jwt text;
        impersonation_result jsonb;
    BEGIN
        -- Get a valid refresh token for admin
        SELECT payload::jsonb INTO impersonation_payload 
        FROM verify(admin_refresh_jwt, 'test-jwt-secret-for-testing-only');
        
        -- Modify the token to change the user (sub) while keeping the same session
        impersonation_payload := jsonb_set(
            impersonation_payload,
            '{sub}',
            to_jsonb((SELECT sub::text FROM auth.user WHERE email = 'test.restricted@example.com'))
        );
        impersonation_payload := jsonb_set(
            impersonation_payload,
            '{email}',
            to_jsonb('test.restricted@example.com'::text)
        );
        impersonation_payload := jsonb_set(
            impersonation_payload,
            '{role}',
            to_jsonb('test.restricted@example.com'::text)
        );
        
        -- Manually construct a tampered JWT with valid signature
        DECLARE
            header text;
            payload text;
            signature text;
            parts text[];
        BEGIN
            -- Split the original token
            parts := string_to_array(admin_refresh_jwt, '.');
            header := parts[1];
            
            -- Use the same base64url encoding that pgjwt uses
            -- This ensures compatibility with the verify function
            SELECT url_encode(convert_to(impersonation_payload::text, 'UTF8')) INTO payload;
            
            -- Use the original signature from the valid token
            -- This simulates an attacker who doesn't know the secret
            -- They can only modify the payload but can't create a valid signature
            signature := parts[3];
            
            -- Construct the tampered token
            impersonation_jwt := header || '.' || payload || '.' || signature;
        END;
        
        -- Set cookies in request headers with the tampered refresh token
        PERFORM set_config('request.headers', 
            jsonb_build_object(
                'x-forwarded-for', '127.0.0.1',
                'user-agent', 'Test User Agent',
                'cookie', format('statbus-test-refresh=%s', impersonation_jwt)
            )::text, 
            true
        );
        
        -- Try to refresh with the tampered token
        SELECT public.refresh()::jsonb INTO impersonation_result;
        
        -- Debug the result
        RAISE DEBUG 'Refresh result with impersonation attempt: %', impersonation_result;
        
        -- Verify the refresh was rejected
        ASSERT impersonation_result ? 'error', 
            'Refresh with impersonation attempt should return an error';
    END;
    
    RAISE NOTICE 'Test 10: JWT Tampering Detection - PASSED';
END;
$$;

-- Test 11: Auth Status Function
\echo '=== Test 11: Auth Status Function ==='
DO $$
DECLARE
    login_result jsonb;
    auth_status_result jsonb;
    auth_status_unauthenticated jsonb;
    access_jwt text;
    jwt_claims json;
    test_email text := 'test.admin@example.com';
    test_sub uuid;
BEGIN
    -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
        )::text, 
        true
    );

    -- Get user details for verification
    SELECT sub INTO test_sub
    FROM auth.user
    WHERE email = test_email;
    
    -- First check unauthenticated status (no JWT claims)
    PERFORM set_config('request.jwt.claims', '', true);
    
    SELECT public.auth_status()::jsonb INTO auth_status_unauthenticated;
    
    -- Debug the unauthenticated status
    RAISE DEBUG 'Auth status (unauthenticated): %', auth_status_unauthenticated;
    
    -- Verify unauthenticated status
    ASSERT auth_status_unauthenticated->>'isAuthenticated' = 'false', 
        'Unauthenticated status should have isAuthenticated=false';
    ASSERT auth_status_unauthenticated->>'user' IS NULL, 
        'Unauthenticated status should have user=null';
    ASSERT auth_status_unauthenticated->>'tokenExpiring' = 'false', 
        'Unauthenticated status should have tokenExpiring=false';
    
    -- Now login to get a valid token
    SELECT public.login(test_email, 'admin123')::jsonb INTO login_result;
    
    -- Extract access token from login result
    access_jwt := login_result->>'access_jwt';
    
    -- Set up JWT claims using the actual token
    SELECT payload::json INTO jwt_claims 
    FROM verify(access_jwt, 'test-jwt-secret-for-testing-only');
    
    PERFORM set_config('request.jwt.claims', jwt_claims::text, true);
    
    -- Check authenticated status
    SELECT public.auth_status()::jsonb INTO auth_status_result;
    
    -- Debug the authenticated status
    RAISE DEBUG 'Auth status (authenticated): %', auth_status_result;
    
    -- Verify authenticated status
    ASSERT auth_status_result->>'isAuthenticated' = 'true', 
        'Authenticated status should have isAuthenticated=true';
    ASSERT auth_status_result->'user' IS NOT NULL, 
        'Authenticated status should have user object';
    ASSERT auth_status_result->'user'->>'id' = test_sub::text, 
        'User ID should match';
    ASSERT auth_status_result->'user'->>'email' = test_email, 
        'User email should match';
    ASSERT auth_status_result->'user'->>'role' = test_email, 
        'User role should match email';
    ASSERT auth_status_result->'user'->>'statbus_role' = 'admin_user', 
        'User statbus_role should match';
    
    -- Test with an expiring token (modify the claims to make token expire soon)
    DECLARE
        expiring_claims json;
        expiring_status jsonb;
    BEGIN
        -- Create a copy of the claims with an expiration time 4 minutes from now
        expiring_claims := jsonb_set(
            jwt_claims::jsonb, 
            '{exp}', 
            to_jsonb(extract(epoch from now())::integer + 240)
        )::json;
        
        -- Set the modified claims
        PERFORM set_config('request.jwt.claims', expiring_claims::text, true);
        
        -- Check status with expiring token
        SELECT public.auth_status()::jsonb INTO expiring_status;
        
        -- Debug the expiring status
        RAISE DEBUG 'Auth status (expiring token): %', expiring_status;
        
        -- Verify expiring token status
        ASSERT expiring_status->>'isAuthenticated' = 'true', 
            'Status with expiring token should have isAuthenticated=true';
        ASSERT expiring_status->>'tokenExpiring' = 'true', 
            'Status with expiring token should have tokenExpiring=true';
    END;
    
    -- Test with an invalid user sub (user not found)
    DECLARE
        invalid_claims json;
        invalid_status jsonb;
        random_uuid uuid := gen_random_uuid();
    BEGIN
        -- Create a copy of the claims with an invalid user sub
        invalid_claims := jsonb_set(
            jwt_claims::jsonb, 
            '{sub}', 
            to_jsonb(random_uuid::text)
        )::json;
        
        -- Set the modified claims
        PERFORM set_config('request.jwt.claims', invalid_claims::text, true);
        
        -- Check status with invalid user
        SELECT public.auth_status()::jsonb INTO invalid_status;
        
        -- Debug the invalid status
        RAISE DEBUG 'Auth status (invalid user): %', invalid_status;
        
        -- Verify invalid user status
        ASSERT invalid_status->>'isAuthenticated' = 'false', 
            'Status with invalid user should have isAuthenticated=false';
        ASSERT invalid_status->>'user' IS NULL, 
            'Status with invalid user should have user=null';
    END;
    
    RAISE NOTICE 'Test 11: Auth Status Function - PASSED';
END;
$$;

-- Test 12: Idempotent User Creation
\echo '=== Test 11: Idempotent User Creation ==='
DO $$
DECLARE
    first_creation_result record;
    second_creation_result record;
    user_count_before integer;
    user_count_after integer;
    test_email text := 'test.idempotent@example.com';
    test_password text := 'idempotent123';
    test_role public.statbus_role := 'regular_user';
BEGIN
    -- Count users with this email before
    SELECT COUNT(*) INTO user_count_before
    FROM auth.user
    WHERE email = test_email;
    
    -- First creation
    SELECT * INTO first_creation_result 
    FROM public.user_create(test_email, test_role, test_password);
    
    -- Debug the first creation result
    RAISE DEBUG 'First creation result: %', first_creation_result;
    
    -- Verify first creation
    ASSERT first_creation_result.email = test_email, 'First creation should return correct email';
    ASSERT first_creation_result.password = test_password, 'First creation should return correct password';
    
    -- Verify user exists in database
    ASSERT EXISTS (
        SELECT 1 FROM auth.user WHERE email = test_email
    ), 'User should exist after first creation';
    
    -- Second creation with same email but different password and role
    SELECT * INTO second_creation_result 
    FROM public.user_create(test_email, 'admin_user'::public.statbus_role, 'newpassword123');
    
    -- Debug the second creation result
    RAISE DEBUG 'Second creation result: %', second_creation_result;
    
    -- Verify second creation
    ASSERT second_creation_result.email = test_email, 'Second creation should return correct email';
    ASSERT second_creation_result.password = 'newpassword123', 'Second creation should return new password';
    
    -- Count users with this email after
    SELECT COUNT(*) INTO user_count_after
    FROM auth.user
    WHERE email = test_email;
    
    -- Verify only one user exists (idempotent)
    ASSERT user_count_after = 1, 'Should still have only one user after second creation';
    
    -- Verify user was updated with new role and password
    ASSERT (
        SELECT statbus_role FROM auth.user WHERE email = test_email
    ) = 'admin_user'::public.statbus_role, 'User role should be updated';
    
    ASSERT (
        SELECT crypt('newpassword123', encrypted_password) = encrypted_password 
        FROM auth.user 
        WHERE email = test_email
    ), 'User password should be updated';
    
    -- Clean up
    DELETE FROM auth.user WHERE email = test_email;
    
    RAISE NOTICE 'Test 12: Idempotent User Creation - PASSED';
END;
$$;

-- Test 13: Trigger Role Change Handling
\echo '=== Test 12: Trigger Role Change Handling ==='
DO $$
DECLARE
    test_email text := 'test.role.change@example.com';
    test_password text := 'rolechange123';
    user_sub uuid;
    role_exists boolean;
    role_granted boolean;
BEGIN
    -- Create a test user with regular_user role
    PERFORM public.user_create(test_email, 'regular_user'::public.statbus_role, test_password);
    
    -- Get the user's sub
    SELECT sub INTO user_sub FROM auth.user WHERE email = test_email;
    
    -- Verify the PostgreSQL role exists
    SELECT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = test_email
    ) INTO role_exists;
    
    ASSERT role_exists, 'PostgreSQL role should exist for the user';
    
    -- Verify regular_user role is granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'regular_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT role_granted, 'regular_user role should be granted initially';
    
    -- Change role directly in the database (this should trigger the role change)
    UPDATE auth.user SET statbus_role = 'admin_user' WHERE email = test_email;
    
    -- Verify admin_user role is now granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'admin_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT role_granted, 'admin_user role should be granted after update';
    
    -- Verify regular_user role is no longer granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'regular_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT NOT role_granted, 'regular_user role should be revoked after update';
    
    -- Change to restricted_user
    UPDATE auth.user SET statbus_role = 'restricted_user' WHERE email = test_email;
    
    -- Verify restricted_user role is now granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'restricted_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT role_granted, 'restricted_user role should be granted after update';
    
    -- Verify admin_user role is no longer granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'admin_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT NOT role_granted, 'admin_user role should be revoked after update';
    
    -- Change to external_user
    UPDATE auth.user SET statbus_role = 'external_user' WHERE email = test_email;
    
    -- Verify external_user role is now granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'external_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT role_granted, 'external_user role should be granted after update';
    
    -- Verify restricted_user role is no longer granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'restricted_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT NOT role_granted, 'restricted_user role should be revoked after update';
    
    -- Clean up
    DELETE FROM auth.user WHERE email = test_email;
    
    -- Verify the PostgreSQL role was dropped by the delete trigger
    SELECT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = test_email
    ) INTO role_exists;
    
    ASSERT NOT role_exists, 'PostgreSQL role should be dropped after user deletion';
    
    RAISE NOTICE 'Test 13: Trigger Role Change Handling - PASSED';
END;
$$;

-- Test 14: Session Context Management
\echo '=== Test 13: Session Context Management ==='
DO $$
DECLARE
    test_email text := 'test.external@example.com';
    claims_before text;
    claims_after text;
    claims_json jsonb;
    test_sub uuid;
    test_role public.statbus_role;
BEGIN
    -- Get user details for verification
    SELECT sub, statbus_role INTO test_sub, test_role
    FROM auth.user
    WHERE email = test_email;
    
    -- Store current claims
    claims_before := current_setting('request.jwt.claims', true);
    
    -- Debug the claims before
    RAISE DEBUG 'Claims before: %', claims_before;
    
    -- Set user context from email
    PERFORM auth.set_user_context_from_email(test_email);
    
    -- Debug after setting user context
    RAISE DEBUG 'Set user context from email: %', test_email;
    
    -- Verify claims were set
    claims_after := current_setting('request.jwt.claims', true);
    claims_json := claims_after::jsonb;
    
    -- Debug the claims after
    RAISE DEBUG 'Claims after: %', claims_after;
    
    ASSERT claims_after <> claims_before, 'Claims should be updated';
    ASSERT claims_json->>'email' = test_email, 'Claims should contain the correct email';
    ASSERT claims_json->>'role' = test_email, 'Claims should set role to email';
    ASSERT claims_json->>'statbus_role' = test_role::text, 'Claims should contain correct statbus_role';
    ASSERT claims_json->>'sub' = test_sub::text, 'Claims should contain correct sub';
    ASSERT claims_json->>'type' = 'access', 'Claims should have type=access';
    ASSERT claims_json ? 'iat', 'Claims should contain iat';
    ASSERT claims_json ? 'exp', 'Claims should contain exp';
    ASSERT claims_json ? 'jti', 'Claims should contain jti';
    
    -- Test using JWT claims in session
    DECLARE
        test_claims jsonb;
    BEGIN
        test_claims := jsonb_build_object(
            'role', test_email,
            'statbus_role', test_role,
            'sub', test_sub,
            'email', test_email,
            'type', 'access',
            'iat', extract(epoch from clock_timestamp())::integer,
            'exp', extract(epoch from clock_timestamp() + interval '1 hour')::integer,
            'jti', gen_random_uuid()
        );
        
        PERFORM auth.use_jwt_claims_in_session(test_claims);
        
        -- Debug the test claims
        RAISE DEBUG 'Using test claims in session: %', test_claims;
        
        -- Verify claims were set correctly
        ASSERT (current_setting('request.jwt.claims', true)::jsonb)->>'role' = test_email, 
            'use_jwt_claims_in_session should set role correctly';
    END;
    
    -- Reset session context
    PERFORM auth.reset_session_context();
    
    -- Debug after reset
    RAISE DEBUG 'Session context after reset: %', current_setting('request.jwt.claims', true);
    
    -- Verify claims were cleared
    ASSERT current_setting('request.jwt.claims', true) = '', 
        'Claims should be cleared';
    
    RAISE NOTICE 'Test 14: Session Context Management - PASSED';
END;
$$;

-- Clean up test environment
-- Clean up test sessions
DELETE FROM auth.refresh_session
WHERE user_id IN (
    SELECT id FROM auth.user 
    WHERE email LIKE 'test.%@example.com'
);

\echo 'All auth tests completed successfully! (14 tests)'

ROLLBACK;

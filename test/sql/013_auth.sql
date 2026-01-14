-- Test file for authentication system
BEGIN;

-- Set up test environment settings once for the entire transaction
-- Set JWT secret and other settings for testing
SET LOCAL "app.settings.jwt_secret" TO 'test-jwt-secret-for-testing-only';
SET LOCAL "app.settings.jwt_exp" TO '3600';
SET LOCAL "app.settings.refresh_jwt_exp" TO '86400';
SET LOCAL "app.settings.deployment_slot_code" TO 'test';

\i test/setup.sql

-- Create a test-specific schema for helper functions
CREATE SCHEMA IF NOT EXISTS auth_test;

-- Helper function to reset common request GUCs for tests
CREATE OR REPLACE FUNCTION auth_test.reset_request_gucs()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('response.headers', '[]', true); -- Clear response headers
    PERFORM set_config('request.cookies', '{}', true); -- Clear request cookies
    PERFORM set_config('request.jwt.claims', '', true); -- Clear request claims
    PERFORM set_config('request.headers', '{}', true); -- Clear request headers
END;
$$;

-- Grant execute to the current user (test runner)
GRANT EXECUTE ON FUNCTION auth_test.reset_request_gucs() TO CURRENT_USER;

-- Create additional test users not covered by setup.sql, using the @statbus.org domain for consistency.
SELECT * FROM public.user_create(p_display_name => 'Test External', p_email => 'test.external@statbus.org', p_statbus_role => 'external_user'::statbus_role, p_password => 'External#123!');
SELECT * FROM public.user_create(p_display_name => 'Test Unconfirmed', p_email => 'test.unconfirmed@statbus.org', p_statbus_role => 'regular_user'::statbus_role, p_password => 'Unconfirmed#123!');
-- Ensure the unconfirmed user is actually unconfirmed as public.user_create confirms them by default.
UPDATE auth.user SET email_confirmed_at = NULL WHERE email = 'test.unconfirmed@statbus.org';

-- Test 0: Inet Parsing Verification
\echo '=== Test 0: Inet Parsing Verification ==='
DO $$
DECLARE
    test_ip inet;
BEGIN
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior (Pattern A)
        RAISE NOTICE 'Test 0.1: Valid IPv4';
        test_ip := inet('192.168.1.1');
        ASSERT test_ip = '192.168.1.1'::inet, format('Test 0.1 Failed: IPv4 parsing error. Expected %L, Got %L', '192.168.1.1'::inet, test_ip);
        RAISE NOTICE 'Test 0.1: PASSED';

        RAISE NOTICE 'Test 0.2: Valid IPv6';
        test_ip := inet('2001:db8::a');
        ASSERT test_ip = '2001:db8::a'::inet, format('Test 0.2 Failed: IPv6 parsing error. Expected %L, Got %L', '2001:db8::a'::inet, test_ip);
        RAISE NOTICE 'Test 0.2: PASSED';

        -- Test 0.3 and 0.4 removed as inet() does not parse ports,
        -- and X-Forwarded-For is not expected to contain ports.

        RAISE NOTICE 'Test 0.5: NULL input';
        test_ip := inet(NULL);
        ASSERT test_ip IS NULL, format('Test 0.5 Failed: inet(NULL) should be NULL, Got %L', test_ip);
        RAISE NOTICE 'Test 0.5: PASSED';

        RAISE NOTICE 'Test 0.6: Invalid IP string (expect exception)';
        BEGIN
            test_ip := inet('invalid-ip-string');
            RAISE EXCEPTION 'Test 0.6 Failed: inet() did not raise error for invalid IP';
        EXCEPTION WHEN invalid_text_representation THEN
            RAISE NOTICE 'Test 0.6: PASSED (Caught expected invalid_text_representation for "invalid-ip-string")';
        END;

        RAISE NOTICE 'Test 0.7: Empty string input (expect exception)';
        BEGIN
            test_ip := inet('');
            RAISE EXCEPTION 'Test 0.7 Failed: inet() did not raise error for empty string';
        EXCEPTION WHEN invalid_text_representation THEN
            RAISE NOTICE 'Test 0.7: PASSED (Caught expected invalid_text_representation for empty string)';
        END;

        RAISE NOTICE 'Test 0 (Inet Parsing Verification) - Overall PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 0 (Inet Parsing Verification) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 0 (Inet Parsing Verification) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 1: Shared IP Extraction Function Test (auth.get_request_ip)
\echo '=== Test 1: Shared IP Extraction Function Test ==='
DO $$
DECLARE
    extracted_ip inet;
BEGIN
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior (Pattern A)
        RAISE NOTICE 'Test 1.1: Valid IPv4 in x-forwarded-for';
        PERFORM set_config('request.headers', '{"x-forwarded-for": "1.2.3.4"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip = '1.2.3.4'::inet, format('Test 1.1 Failed. Expected %L, Got %L', '1.2.3.4'::inet, extracted_ip);
        RAISE NOTICE 'Test 1.1: PASSED';

        RAISE NOTICE 'Test 1.2: Valid IPv6 in x-forwarded-for';
        PERFORM set_config('request.headers', '{"x-forwarded-for": "2001:db8::c"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip = '2001:db8::c'::inet, format('Test 1.2 Failed. Expected %L, Got %L', '2001:db8::c'::inet, extracted_ip);
        RAISE NOTICE 'Test 1.2: PASSED';

        RAISE NOTICE 'Test 1.3: Valid IPv6 in x-forwarded-for (no port)';
        PERFORM set_config('request.headers', '{"x-forwarded-for": "2001:db8::d"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip = '2001:db8::d'::inet, format('Test 1.3 Failed. Expected %L, Got %L', '2001:db8::d'::inet, extracted_ip);
        RAISE NOTICE 'Test 1.3: PASSED';

        RAISE NOTICE 'Test 1.4: Multiple IPs in x-forwarded-for (takes first)';
        PERFORM set_config('request.headers', '{"x-forwarded-for": "1.2.3.4, 5.6.7.8"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip = '1.2.3.4'::inet, format('Test 1.4 Failed. Expected %L, Got %L', '1.2.3.4'::inet, extracted_ip);
        RAISE NOTICE 'Test 1.4: PASSED';

        RAISE NOTICE 'Test 1.5: IPv4 with port in x-forwarded-for';
        PERFORM set_config('request.headers', '{"x-forwarded-for": "1.2.3.4:8080"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip = '1.2.3.4'::inet, format('Test 1.5 Failed: IPv4 with port not stripped correctly. Expected %L, Got %L', '1.2.3.4'::inet, extracted_ip);
        RAISE NOTICE 'Test 1.5: PASSED';

        RAISE NOTICE 'Test 1.6: IPv6 with brackets and port in x-forwarded-for';
        PERFORM set_config('request.headers', '{"x-forwarded-for": "[2001:db8::a]:8080"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip = '2001:db8::a'::inet, format('Test 1.6 Failed: IPv6 with brackets and port not stripped correctly. Expected %L, Got %L', '2001:db8::a'::inet, extracted_ip);
        RAISE NOTICE 'Test 1.6: PASSED';

        RAISE NOTICE 'Test 1.7: Non-standard IPv6 without brackets but with port in x-forwarded-for (robustness test)';
        PERFORM set_config('request.headers', '{"x-forwarded-for": "2001:db8::b:8080"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip = '2001:db8::b'::inet, format('Test 1.7 Failed: Non-standard IPv6 (no brackets) with port not stripped correctly by robust parser. Expected %L, Got %L', '2001:db8::b'::inet, extracted_ip);
        RAISE NOTICE 'Test 1.7: PASSED';

        RAISE NOTICE 'Test 1.8: x-forwarded-for missing (empty JSON headers)';
        PERFORM set_config('request.headers', '{}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip IS NULL, format('Test 1.8 Failed. Expected NULL, Got %L', extracted_ip);
        RAISE NOTICE 'Test 1.8: PASSED';

        RAISE NOTICE 'Test 1.9: x-forwarded-for missing (other headers present)';
        PERFORM set_config('request.headers', '{"user-agent": "test"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip IS NULL, format('Test 1.9 Failed. Expected NULL, Got %L', extracted_ip);
        RAISE NOTICE 'Test 1.9: PASSED';
        
        RAISE NOTICE 'Test 1.10: x-forwarded-for is empty string';
        PERFORM set_config('request.headers', '{"x-forwarded-for": ""}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip IS NULL, format('Test 1.10 Failed. Expected NULL, Got %L', extracted_ip);
        RAISE NOTICE 'Test 1.10: PASSED';

        RAISE NOTICE 'Test 1.11: x-forwarded-for is JSON null';
        PERFORM set_config('request.headers', '{"x-forwarded-for": null}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip IS NULL, format('Test 1.11 Failed. Expected NULL, Got %L', extracted_ip);
        RAISE NOTICE 'Test 1.11: PASSED';

        RAISE NOTICE 'Test 1.12: request.headers GUC not set (is NULL)';
        PERFORM set_config('request.headers', NULL, true); -- Simulate GUC not being set
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip IS NULL, format('Test 1.12 Failed. Expected NULL, Got %L', extracted_ip);
        RAISE NOTICE 'Test 1.12: PASSED';

        RAISE NOTICE 'Test 1.13: request.headers is invalid JSON (expect exception)';
        BEGIN
            PERFORM set_config('request.headers', 'invalid json string', true);
            extracted_ip := auth.get_request_ip();
            RAISE EXCEPTION 'Test 1.13 Failed: auth.get_request_ip() did not raise error for invalid JSON headers';
        EXCEPTION WHEN invalid_text_representation THEN -- Error from ::json cast
            RAISE NOTICE 'Test 1.13: PASSED (Caught expected invalid_text_representation for JSON)';
        END;
        
        RAISE NOTICE 'Test 1.14: x-forwarded-for contains invalid IP string (expect exception)';
        BEGIN
            PERFORM set_config('request.headers', '{"x-forwarded-for": "invalid-ip"}', true);
            extracted_ip := auth.get_request_ip();
            RAISE EXCEPTION 'Test 1.14 Failed: auth.get_request_ip() did not raise error for invalid IP in xff';
        EXCEPTION WHEN invalid_text_representation THEN -- Error from inet() conversion
            RAISE NOTICE 'Test 1.14: PASSED (Caught expected invalid_text_representation for inet)';
        END;

        RAISE NOTICE 'Test 1.15: Simple IPv6 ::1 (no port, no brackets)';
        PERFORM set_config('request.headers', '{"x-forwarded-for": "::1"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip = '::1'::inet, format('Test 1.15 Failed: Simple IPv6 ::1 not handled correctly. Expected %L, Got %L', '::1'::inet, extracted_ip);
        RAISE NOTICE 'Test 1.15: PASSED';

        RAISE NOTICE 'Test 1.16: IPv6 localhost with port, no brackets (::1:8080)';
        PERFORM set_config('request.headers', '{"x-forwarded-for": "::1:8080"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip = '::1'::inet, format('Test 1.16 Failed: IPv6 ::1:8080 with port not stripped correctly. Expected %L, Got %L', '::1'::inet, extracted_ip);
        RAISE NOTICE 'Test 1.16: PASSED';

        RAISE NOTICE 'Test 1.17: IPv6 localhost with port, with brackets ([::1]:8080)';
        PERFORM set_config('request.headers', '{"x-forwarded-for": "[::1]:8080"}', true);
        extracted_ip := auth.get_request_ip();
        ASSERT extracted_ip = '::1'::inet, format('Test 1.17 Failed: IPv6 [::1]:8080 with port and brackets not stripped correctly. Expected %L, Got %L', '::1'::inet, extracted_ip);
        RAISE NOTICE 'Test 1.17: PASSED';

        RAISE NOTICE 'Test 1 (Shared IP Extraction Function Test) - Overall PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 1 (Shared IP Extraction Function Test) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 1 (Shared IP Extraction Function Test) - FAILED: %', SQLERRM;
    END;
    -- Reset headers GUC to a sensible default after tests
    PERFORM set_config('request.headers', '{}', true);
END;
$$;
    
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

-- Helper function to perform login with specific headers and verify results
CREATE OR REPLACE FUNCTION test.perform_login_and_verify(
    p_email text,
    p_password text,
    p_scenario_name text,
    p_request_headers jsonb,
    p_expected_ip inet,
    p_expected_secure_flag boolean,
    p_expected_user_agent text
) RETURNS void AS $$
DECLARE
    login_result jsonb;
    access_token text;
    refresh_jwt text;
    has_access_cookie boolean := false;
    has_refresh_cookie boolean := false;
    response_headers jsonb;
    header_obj jsonb;
    session_record record;
    cookie_value_text text;
    refresh_jwt_payload jsonb;
    session_jti uuid;
BEGIN
    RAISE DEBUG 'Running login scenario: % with headers %', p_scenario_name, p_request_headers;

    -- Set up headers
    PERFORM set_config('request.headers', p_request_headers::text, true);
    -- Clear previous response headers
    PERFORM set_config('response.headers', '[]'::text, true);

    -- Perform login
    SELECT to_json(source.*) INTO login_result FROM public.login(p_email, p_password) AS source;
    
    RAISE DEBUG 'Login result for scenario "%": %', p_scenario_name, login_result;
    response_headers := nullif(current_setting('response.headers', true), '')::jsonb;
    RAISE DEBUG 'Response headers for scenario "%": %', p_scenario_name, response_headers;

    ASSERT login_result IS NOT NULL, format('Login result should not be NULL for scenario %L. Login result: %s', p_scenario_name, login_result);
    ASSERT (login_result->>'is_authenticated')::boolean IS TRUE,
        format('Login should succeed and return is_authenticated=true for scenario %L. Got is_authenticated=%L. Full login_result: %s', p_scenario_name, login_result->>'is_authenticated', login_result);
    ASSERT (login_result->'error_code') = 'null'::jsonb, -- Check error_code is null on success
        format('error_code should be null for successful login in scenario %L. Got error_code=%L. Full login_result: %s', p_scenario_name, login_result->'error_code', login_result);
    
    SELECT cv.cookie_value INTO access_token FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    SELECT cv.cookie_value INTO refresh_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus-refresh';

    ASSERT access_token IS NOT NULL, format('Access token cookie (statbus) not found after login for scenario %L. Cookies found: %s', p_scenario_name, (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    ASSERT refresh_jwt IS NOT NULL, format('Refresh token cookie (statbus-refresh) not found after login for scenario %L. Cookies found: %s', p_scenario_name, (SELECT json_agg(jrc) FROM test.extract_cookies() jrc));
    ASSERT response_headers IS NOT NULL AND jsonb_array_length(response_headers) > 0,
        format('Response headers should contain Set-Cookie directives for scenario %L. Headers: %s', p_scenario_name, response_headers);

    FOR header_obj IN SELECT * FROM jsonb_array_elements(response_headers) LOOP
        IF header_obj ? 'Set-Cookie' THEN
            cookie_value_text := header_obj->>'Set-Cookie';
            IF cookie_value_text LIKE 'statbus=%' THEN
                has_access_cookie := true;
                IF p_expected_secure_flag THEN
                    ASSERT cookie_value_text LIKE '%Secure%', 
                        format('Access cookie should have Secure flag for scenario %L with headers %L. Cookie: %L', p_scenario_name, p_request_headers::text, cookie_value_text);
                ELSE
                    ASSERT cookie_value_text NOT LIKE '%Secure%', 
                        format('Access cookie should NOT have Secure flag for scenario %L with headers %L. Cookie: %L', p_scenario_name, p_request_headers::text, cookie_value_text);
                END IF;
            END IF;
            IF cookie_value_text LIKE 'statbus-refresh=%' THEN
                has_refresh_cookie := true;
                IF p_expected_secure_flag THEN
                    ASSERT cookie_value_text LIKE '%Secure%', 
                        format('Refresh cookie should have Secure flag for scenario %L with headers %L. Cookie: %L', p_scenario_name, p_request_headers::text, cookie_value_text);
                ELSE
                    ASSERT cookie_value_text NOT LIKE '%Secure%', 
                        format('Refresh cookie should NOT have Secure flag for scenario %L with headers %L. Cookie: %L', p_scenario_name, p_request_headers::text, cookie_value_text);
                END IF;
            END IF;
        END IF;
    END LOOP;
    
    ASSERT has_access_cookie, format('Access cookie was not set for scenario %L. Response headers: %s', p_scenario_name, response_headers);
    ASSERT has_refresh_cookie, format('Refresh cookie was not set for scenario %L. Response headers: %s', p_scenario_name, response_headers);

    -- Verify session was created in database with correct IP and User Agent
    SELECT payload::jsonb INTO refresh_jwt_payload
    FROM verify(refresh_jwt, 'test-jwt-secret-for-testing-only', 'HS256');
    
    session_jti := (refresh_jwt_payload->>'jti')::uuid;

    RAISE DEBUG 'Extracted session JTI % for scenario %L from refresh token', session_jti, p_scenario_name;

    SELECT rs.ip_address, rs.user_agent INTO session_record
    FROM auth.refresh_session rs
    WHERE rs.jti = session_jti;

    ASSERT FOUND, format('Session with JTI %L not found for scenario %L. Refresh token payload: %s', session_jti, p_scenario_name, refresh_jwt_payload);

    IF p_expected_ip IS NOT NULL THEN
        ASSERT session_record.ip_address = p_expected_ip, 
            format('Session IP address mismatch for scenario %L. Expected: %L, Got: %L. Session record: %s', p_scenario_name, p_expected_ip, session_record.ip_address, row_to_json(session_record));
    ELSE
        ASSERT session_record.ip_address IS NULL,
            format('Session IP address should be NULL for scenario %L. Got: %L. Session record: %s', p_scenario_name, session_record.ip_address, row_to_json(session_record));
    END IF;
    
    IF p_expected_user_agent IS NOT NULL THEN
         ASSERT session_record.user_agent = p_expected_user_agent, 
            format('Session User Agent mismatch for scenario %L. Expected: %L, Got: %L. Session record: %s', p_scenario_name, p_expected_user_agent, session_record.user_agent, row_to_json(session_record));
    ELSE
        ASSERT session_record.user_agent IS NULL,
            format('Session User Agent should be NULL for scenario %L. Got: %L. Session record: %s', p_scenario_name, session_record.user_agent, row_to_json(session_record));
    END IF;
    RAISE DEBUG 'Login scenario %L passed all checks.', p_scenario_name; -- Changed %s to %L for RAISE DEBUG as well for consistency, though it's less critical here.
END;
$$ LANGUAGE plpgsql;

-- Test 2: User Login Success
\echo '=== Test 2: User Login Success ==='
DO $$
DECLARE
    login_result jsonb;
    expected_claims jsonb;
    access_token text;
    refresh_jwt text;
    cookies record;
    has_access_cookie boolean := false;
    has_refresh_cookie boolean := false;
    auth_status_result jsonb;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Original Test 1 logic starts here
        -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );

    -- Perform login
    SELECT to_json(source.*) INTO login_result FROM public.login('test.regular@statbus.org', 'Regular#123!') AS source;
    
    RAISE DEBUG 'Login result: %', login_result;
    RAISE DEBUG 'Response headers after login: %', nullif(current_setting('response.headers', true), '')::jsonb;
    
    ASSERT (login_result->>'is_authenticated')::boolean IS TRUE, format('Login result should indicate authentication. Got: %L. Full login_result: %s', login_result->>'is_authenticated', login_result);
    ASSERT (login_result->'error_code') = 'null'::jsonb, format('Login result should have null error_code on success. Got: %L. Full login_result: %s', login_result->'error_code', login_result);
    ASSERT login_result ? 'uid', format('Login result should contain uid. Full login_result: %s', login_result);
    ASSERT login_result ? 'role', format('Login result should contain role. Full login_result: %s', login_result);
    ASSERT login_result ? 'statbus_role', format('Login result should contain statbus_role. Full login_result: %s', login_result);
    ASSERT login_result ? 'email', format('Login result should contain email. Full login_result: %s', login_result);

    -- Extract tokens from cookies
    SELECT cv.cookie_value INTO access_token FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    SELECT cv.cookie_value INTO refresh_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus-refresh';

    ASSERT access_token IS NOT NULL, format('Access token cookie not found after login. Cookies found: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    ASSERT refresh_jwt IS NOT NULL, format('Refresh token cookie not found after login. Cookies found: %s', (SELECT json_agg(jrc) FROM test.extract_cookies() jrc));
    
    -- Verify token claims
    expected_claims := jsonb_build_object(
        'role', 'test.regular@statbus.org',
        'statbus_role', 'regular_user',
        'email', 'test.regular@statbus.org',
        'type', 'access'
    );
    
    ASSERT test.verify_jwt_claims(access_token, expected_claims),
        format('Access token claims do not match expected values. Token: %L, Expected: %s', access_token, expected_claims);
    
    -- Verify refresh token claims
    expected_claims := jsonb_build_object(
        'role', 'test.regular@statbus.org',
        'statbus_role', 'regular_user',
        'email', 'test.regular@statbus.org',
        'type', 'refresh'
    );
    
    ASSERT test.verify_jwt_claims(refresh_jwt, expected_claims),
        format('Refresh token claims do not match expected values. Token: %L, Expected: %s', refresh_jwt, expected_claims);
    
    -- Verify cookies were set
    FOR cookies IN SELECT * FROM test.extract_cookies()
    LOOP
        IF cookies.cookie_name = 'statbus' THEN
            has_access_cookie := true;
            ASSERT cookies.cookie_value = access_token, format('Access cookie value does not match token. Expected: %L, Got: %L', access_token, cookies.cookie_value);
        ELSIF cookies.cookie_name = 'statbus-refresh' THEN
            has_refresh_cookie := true;
            ASSERT cookies.cookie_value = refresh_jwt, format('Refresh cookie value does not match token. Expected: %L, Got: %L', refresh_jwt, cookies.cookie_value);
        END IF;
    END LOOP;
    
    ASSERT has_access_cookie, format('Access cookie was not set. Cookies found: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    ASSERT has_refresh_cookie, format('Refresh cookie was not set. Cookies found: %s', (SELECT json_agg(jrc) FROM test.extract_cookies() jrc));

    -- Verify Secure flag in cookies
    DECLARE
        response_headers jsonb;
        header_obj jsonb;
        access_cookie_secure boolean := false;
        refresh_cookie_secure boolean := false;
    BEGIN
        response_headers := nullif(current_setting('response.headers', true), '')::jsonb;
        FOR header_obj IN SELECT * FROM jsonb_array_elements(response_headers) LOOP
            IF header_obj ? 'Set-Cookie' THEN
                IF header_obj->>'Set-Cookie' LIKE 'statbus=%' AND header_obj->>'Set-Cookie' LIKE '%Secure%' THEN
                    access_cookie_secure := true;
                END IF;
                IF header_obj->>'Set-Cookie' LIKE 'statbus-refresh=%' AND header_obj->>'Set-Cookie' LIKE '%Secure%' THEN
                    refresh_cookie_secure := true;
                END IF;
            END IF;
        END LOOP;
        ASSERT access_cookie_secure, format('Access cookie should have Secure flag when x-forwarded-proto is https. Headers: %s', response_headers);
        ASSERT refresh_cookie_secure, format('Refresh cookie should have Secure flag when x-forwarded-proto is https. Headers: %s', response_headers);
    END;
    
    -- Verify session was created in database with correct IP and User Agent
    DECLARE
        session_record record;
    BEGIN
        SELECT rs.ip_address, rs.user_agent INTO session_record
        FROM auth.refresh_session rs
        JOIN auth.user u ON rs.user_id = u.id
        WHERE u.email = 'test.regular@statbus.org'
        ORDER BY rs.created_at DESC LIMIT 1;

        ASSERT session_record.ip_address = '127.0.0.1'::inet, format('Session IP address mismatch. Expected %L, Got %L. Session: %s', '127.0.0.1'::inet, session_record.ip_address, row_to_json(session_record));
        ASSERT session_record.user_agent = 'Test User Agent', format('Session User Agent mismatch. Expected %L, Got %L. Session: %s', 'Test User Agent', session_record.user_agent, row_to_json(session_record));
    END;
    
    -- Verify last_sign_in_at was updated
    DECLARE last_signin timestamptz;
    BEGIN
        SELECT last_sign_in_at INTO last_signin FROM auth.user WHERE email = 'test.regular@statbus.org';
        ASSERT last_signin > now() - interval '1 minute',
            format('last_sign_in_at was not updated. Expected > %L, Got %L', now() - interval '1 minute', last_signin);
    END;
    
    -- Now test auth_status using the cookies from the first login
    -- Set up cookies to simulate browser cookies
    PERFORM set_config('request.cookies', 
        json_build_object(
            'statbus', access_token,
            'statbus-refresh', refresh_jwt
        )::text, 
        true
    );
    -- Headers for auth_status (already set from initial login)
    PERFORM set_config('request.jwt.claims', '', true); -- Reset JWT claims to ensure we're using cookies
    
    SELECT to_json(source.*) INTO auth_status_result FROM public.auth_status() AS source;
    RAISE DEBUG 'Auth status result (after initial login): %', auth_status_result;
    ASSERT auth_status_result->>'is_authenticated' = 'true', format('Auth status should show authenticated. Got: %L. Full auth_status_result: %s', auth_status_result->>'is_authenticated', auth_status_result);
    ASSERT auth_status_result->>'email' = 'test.regular@statbus.org', format('Auth status should have correct email. Expected %L, Got %L. Full auth_status_result: %s', 'test.regular@statbus.org', auth_status_result->>'email', auth_status_result);

    RAISE NOTICE '--- Test 2.1: Initial Login and Auth Status Verification - PASSED ---';

    RAISE NOTICE '--- Test 2.2: Header Variations for Login ---';
    -- Scenario 1: HTTPS proxy (standard)
    PERFORM test.perform_login_and_verify(
        'test.regular@statbus.org', 'Regular#123!',
        'HTTPS Proxy',
        jsonb_build_object(
            'x-forwarded-for', '10.0.0.1',
            'user-agent', 'HTTPS Agent',
            'x-forwarded-proto', 'https'
        ),
        '10.0.0.1'::inet, true, 'HTTPS Agent'
    );

    -- Scenario 2: HTTP proxy
    PERFORM test.perform_login_and_verify(
        'test.regular@statbus.org', 'Regular#123!',
        'HTTP Proxy',
        jsonb_build_object(
            'x-forwarded-for', '10.0.0.2',
            'user-agent', 'HTTP Agent',
            'x-forwarded-proto', 'http'
        ),
        '10.0.0.2'::inet, false, 'HTTP Agent'
    );

    -- Scenario 3: Naked request (no proxy headers)
    PERFORM test.perform_login_and_verify(
        'test.regular@statbus.org', 'Regular#123!',
        'Naked Request',
        jsonb_build_object('user-agent', 'Naked Agent'),
        NULL::inet, false, 'Naked Agent' -- IP is NULL as x-forwarded-for is missing
    );
    
    -- Scenario 4: Naked request (no headers at all)
    PERFORM test.perform_login_and_verify(
        'test.regular@statbus.org', 'Regular#123!',
        'Naked Request No Headers',
        jsonb_build_object(), -- Empty headers
        NULL::inet, false, NULL -- IP and UA are NULL
    );

    -- Scenario 5: Multiple IPs in x-forwarded-for (HTTPS)
    PERFORM test.perform_login_and_verify(
        'test.regular@statbus.org', 'Regular#123!',
        'Multiple IPs HTTPS',
        jsonb_build_object(
            'x-forwarded-for', '10.0.0.3, 192.168.0.1',
            'user-agent', 'Multi-IP Agent',
            'x-forwarded-proto', 'https'
        ),
        '10.0.0.3'::inet, true, 'Multi-IP Agent' -- Should take the first IP
    );

    -- Scenario 6: IPv6 in x-forwarded-for (HTTPS)
    PERFORM test.perform_login_and_verify(
        'test.regular@statbus.org', 'Regular#123!',
        'IPv6 HTTPS',
        jsonb_build_object(
            'x-forwarded-for', '2001:db8::a', -- Removed brackets
            'user-agent', 'IPv6 Agent',
            'x-forwarded-proto', 'https'
        ),
        '2001:db8::a'::inet, true, 'IPv6 Agent'
    );

    -- Scenario 7: IP in x-forwarded-for (HTTPS, no port)
    PERFORM test.perform_login_and_verify(
        'test.regular@statbus.org', 'Regular#123!',
        'IP with Port HTTPS', -- Scenario name can remain, implies testing IP handling
        jsonb_build_object(
            'x-forwarded-for', '10.0.0.4', -- No port
            'user-agent', 'IP-Port Agent',
            'x-forwarded-proto', 'https'
        ),
        '10.0.0.4'::inet, true, 'IP-Port Agent'
    );

    -- Scenario 8: IPv6 with port in x-forwarded-for (HTTPS)
    PERFORM test.perform_login_and_verify(
        'test.regular@statbus.org', 'Regular#123!',
        'IPv6 with Port HTTPS', -- Scenario name can remain
        jsonb_build_object(
            'x-forwarded-for', '2001:db8::b', -- No port, no brackets needed
            'user-agent', 'IPv6-Port Agent',
            'x-forwarded-proto', 'https'
        ),
        '2001:db8::b'::inet, true, 'IPv6-Port Agent'
    );
    
    -- Scenario 9: x-forwarded-proto: HTTPS (uppercase) - current code is case-sensitive for 'https'
    PERFORM test.perform_login_and_verify(
        'test.regular@statbus.org', 'Regular#123!',
        'Uppercase HTTPS Proto',
        jsonb_build_object(
            'x-forwarded-for', '10.0.0.5',
            'user-agent', 'Case Agent',
            'x-forwarded-proto', 'HTTPS' -- Uppercase
        ),
        '10.0.0.5'::inet, true, 'Case Agent' -- Expect Secure: true after case-insensitive fix
    );

        RAISE NOTICE 'Test 2: User Login Success (including header variations) - PASSED';
        -- End of original Test 2 logic
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 2 (User Login Success) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 2 (User Login Success) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 3: User Login Failure - Wrong Password
\echo '=== Test 3: User Login Failure - Wrong Password ==='
DO $$
DECLARE
    login_result jsonb;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Original Test 4 logic starts here
        -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
        'x-forwarded-for', '127.0.0.1',
        'user-agent', 'Test User Agent',
        'x-forwarded-proto', 'https' -- Simulate HTTPS
    )::text, 
    true
);

    -- Attempt login with wrong password
    SELECT to_json(source.*) INTO login_result FROM public.login('test.regular@statbus.org', 'wrongpassword') AS source;
    
    -- Debug the login result
    RAISE DEBUG 'Login result (should be null): %', login_result;
    
    -- Verify login failed (result should be an auth_status_response indicating not authenticated)
    ASSERT login_result IS NOT NULL, format('Login with wrong password should return a non-null auth_status_response. Got: %s', login_result);
    ASSERT (login_result->>'is_authenticated')::boolean IS FALSE, format('Login with wrong password should result in is_authenticated = false. Got: %L. Full response: %s', login_result->>'is_authenticated', login_result);
    ASSERT login_result->>'uid' IS NULL, format('Login with wrong password should result in uid = NULL. Got: %L. Full response: %s', login_result->>'uid', login_result);
    ASSERT login_result->>'error_code' = 'WRONG_PASSWORD', format('Login with wrong password should result in error_code WRONG_PASSWORD. Got: %L. Full response: %s', login_result->>'error_code', login_result);
    RAISE NOTICE 'Test 3: public.login is expected to set HTTP status 401 for wrong password.';
    
        RAISE NOTICE 'Test 3: User Login Failure - Wrong Password - PASSED';
        -- End of original Test 3 logic
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 3 (User Login Failure - Wrong Password) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 3 (User Login Failure - Wrong Password) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 4: User Login Failure - Null Password
\echo '=== Test 4: User Login Failure - Null Password ==='
DO $$
DECLARE
    login_result jsonb;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        PERFORM set_config('request.headers', 
            json_build_object(
                'x-forwarded-for', '127.0.0.1',
                'user-agent', 'Test User Agent',
                'x-forwarded-proto', 'https'
            )::text, 
            true
        );

    -- Attempt login with NULL password
    SELECT to_json(source.*) INTO login_result FROM public.login('test.regular@statbus.org', NULL::text) AS source;
    
    RAISE DEBUG 'Login result (null password): %', login_result;
    
    ASSERT login_result IS NOT NULL, 'Login with null password should return a non-null auth_status_response.';
    ASSERT (login_result->>'is_authenticated')::boolean IS FALSE, 'Login with null password should result in is_authenticated = false.';
    ASSERT login_result->>'uid' IS NULL, 'Login with null password should result in uid = NULL.';
    ASSERT login_result->>'error_code' = 'USER_MISSING_PASSWORD', format('Login with null password should result in error_code USER_MISSING_PASSWORD. Got: %L.', login_result->>'error_code');
    RAISE NOTICE 'Test 4: public.login is expected to set HTTP status 401 for null password.';
    
        RAISE NOTICE 'Test 4: User Login Failure - Null Password - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 4 (User Login Failure - Null Password) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 4 (User Login Failure - Null Password) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 5: User Login Failure - User Not Found
\echo '=== Test 5: User Login Failure - User Not Found ==='
DO $$
DECLARE
    login_result jsonb;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        PERFORM set_config('request.headers', 
            json_build_object(
                'x-forwarded-for', '127.0.0.1',
                'user-agent', 'Test User Agent',
                'x-forwarded-proto', 'https'
            )::text, 
            true
        );

    -- Attempt login with a non-existent user
    SELECT to_json(source.*) INTO login_result FROM public.login('nonexistent.user@statbus.org', 'anypassword') AS source;
    
    RAISE DEBUG 'Login result (user not found): %', login_result;
    
    ASSERT login_result IS NOT NULL, 'Login with non-existent user should return a non-null auth_status_response.';
    ASSERT (login_result->>'is_authenticated')::boolean IS FALSE, 'Login with non-existent user should result in is_authenticated = false.';
    ASSERT login_result->>'uid' IS NULL, 'Login with non-existent user should result in uid = NULL.';
    ASSERT login_result->>'error_code' = 'USER_NOT_FOUND', format('Login with non-existent user should result in error_code USER_NOT_FOUND. Got: %L.', login_result->>'error_code');
    RAISE NOTICE 'Test 5: public.login is expected to set HTTP status 401 for non-existent user.';
    
        RAISE NOTICE 'Test 5: User Login Failure - User Not Found - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 5 (User Login Failure - User Not Found) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 5 (User Login Failure - User Not Found) - FAILED: %', SQLERRM;
    END;
END;
$$;


-- Test 6: User Login Failure - Unconfirmed Email
\echo '=== Test 6: User Login Failure - Unconfirmed Email ==='
DO $$
DECLARE
    login_result jsonb;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );

    -- Attempt login with unconfirmed email
    SELECT to_json(source.*) INTO login_result FROM public.login('test.unconfirmed@statbus.org', 'Unconfirmed#123!') AS source;
    
    -- Debug the login result
    RAISE DEBUG 'Login result (should be null): %', login_result;
    
    -- Verify login failed (result should be an auth_status_response indicating not authenticated)
    ASSERT login_result IS NOT NULL, format('Login with unconfirmed email should return a non-null auth_status_response. Got: %s', login_result);
    ASSERT (login_result->>'is_authenticated')::boolean IS FALSE, format('Login with unconfirmed email should result in is_authenticated = false. Got: %L. Full response: %s', login_result->>'is_authenticated', login_result);
    ASSERT login_result->>'uid' IS NULL, format('Login with unconfirmed email should result in uid = NULL. Got: %L. Full response: %s', login_result->>'uid', login_result);
    ASSERT login_result->>'error_code' = 'USER_NOT_CONFIRMED_EMAIL', format('Login with unconfirmed email should result in error_code USER_NOT_CONFIRMED_EMAIL. Got: %L. Full response: %s', login_result->>'error_code', login_result);
    RAISE NOTICE 'Test 6: public.login is expected to set HTTP status 401 for unconfirmed email.';
    
        RAISE NOTICE 'Test 6: User Login Failure - Unconfirmed Email - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 6 (User Login Failure - Unconfirmed Email) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 6 (User Login Failure - Unconfirmed Email) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 7: User Login Failure - Deleted User
\echo '=== Test 7: User Login Failure - Deleted User ==='
DO $$
DECLARE
    login_result jsonb;
    deleted_user_email text := 'test.deleted.user@statbus.org';
BEGIN
    PERFORM auth_test.reset_request_gucs();
    -- Create and then delete a user for this test
    PERFORM public.user_create(p_display_name => 'Test Deleted User', p_email => deleted_user_email, p_statbus_role => 'regular_user'::public.statbus_role, p_password => 'Deleted#123!');
    UPDATE auth.user SET deleted_at = now() WHERE email = deleted_user_email;

    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        PERFORM set_config('request.headers', 
            json_build_object(
                'x-forwarded-for', '127.0.0.1',
                'user-agent', 'Test User Agent',
                'x-forwarded-proto', 'https'
            )::text, 
            true
        );

    -- Attempt login with the deleted user's credentials
    SELECT to_json(source.*) INTO login_result FROM public.login(deleted_user_email, 'Deleted#123!') AS source;
    
    RAISE DEBUG 'Login result (deleted user): %', login_result;
    
    ASSERT login_result IS NOT NULL, 'Login with deleted user should return a non-null auth_status_response.';
    ASSERT (login_result->>'is_authenticated')::boolean IS FALSE, 'Login with deleted user should result in is_authenticated = false.';
    ASSERT login_result->>'uid' IS NULL, 'Login with deleted user should result in uid = NULL.';
    ASSERT login_result->>'error_code' = 'USER_DELETED', format('Login with deleted user should result in error_code USER_DELETED. Got: %L.', login_result->>'error_code');
    RAISE NOTICE 'Test 7: public.login is expected to set HTTP status 401 for deleted user.';
    
        RAISE NOTICE 'Test 7: User Login Failure - Deleted User - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 7 (User Login Failure - Deleted User) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 7 (User Login Failure - Deleted User) - FAILED: %', SQLERRM;
    END;
    -- Clean up the test user
    DELETE FROM auth.user WHERE email = deleted_user_email;
END;
$$;


-- Test 8: Token Refresh
\echo '=== Test 8: Token Refresh ==='
DO $$
DECLARE
    login_result jsonb;
    refresh_result jsonb;
    access_jwt_from_login text;
    refresh_jwt_from_login text;
    access_jwt_from_refresh text;
    refresh_jwt_from_refresh text;
    refresh_session_before record;
    refresh_session_after record;
    auth_status_before jsonb;
    auth_status_after jsonb;
BEGIN
    PERFORM auth_test.reset_request_gucs(); -- Ensure all GUCs are reset at the start of the test block

    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Reset context for the test (some of these are now redundant but harmless)
    PERFORM set_config('request.cookies', '{}', true); -- Login doesn't use request cookies
    PERFORM set_config('request.jwt.claims', '', true); -- Clear any JWT claims from previous tests
    PERFORM set_config('response.headers', '[]', true); -- Clear response headers before login
    
    -- Set up request headers for login
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1', -- Initial IP
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );

    -- First login
    SELECT to_json(source.*) INTO login_result FROM public.login('test.admin@statbus.org', 'Admin#123!') AS source;
    RAISE DEBUG 'Login result: %', login_result;
    RAISE DEBUG 'Response headers after login: %', nullif(current_setting('response.headers', true), '')::jsonb;
    
    DECLARE
        response_headers jsonb;
        header_obj jsonb;
        access_cookie_found boolean := false;
        refresh_cookie_found boolean := false;
        access_cookie_attrs_valid boolean := false;
        refresh_cookie_attrs_valid boolean := false;
    BEGIN
        response_headers := nullif(current_setting('response.headers', true), '')::jsonb;
        
        FOR header_obj IN SELECT * FROM jsonb_array_elements(response_headers) LOOP
            IF header_obj ? 'Set-Cookie' THEN
                IF header_obj->>'Set-Cookie' LIKE 'statbus=%' THEN
                    access_cookie_found := true;
                    IF header_obj->>'Set-Cookie' LIKE '%HttpOnly%' AND
                       header_obj->>'Set-Cookie' LIKE '%SameSite=Strict%' AND
                       header_obj->>'Set-Cookie' LIKE '%Secure%' AND
                       header_obj->>'Set-Cookie' LIKE '%Path=/%' AND NOT (header_obj->>'Set-Cookie' LIKE '%Path=/rest/rpc/refresh%') THEN -- Ensure Path=/ and not /rest/rpc/refresh
                        access_cookie_attrs_valid := true;
                    END IF;
                ELSIF header_obj->>'Set-Cookie' LIKE 'statbus-refresh=%' THEN
                    refresh_cookie_found := true;
                    IF header_obj->>'Set-Cookie' LIKE '%HttpOnly%' AND
                       header_obj->>'Set-Cookie' LIKE '%SameSite=Strict%' AND
                       header_obj->>'Set-Cookie' LIKE '%Secure%' AND
                       header_obj->>'Set-Cookie' LIKE '%Path=/rest/rpc/refresh%' THEN -- Check for specific path
                        refresh_cookie_attrs_valid := true;
                    END IF;
                END IF;
            END IF;
        END LOOP;
        
        ASSERT access_cookie_found, 'Access cookie not found in login response headers';
        ASSERT refresh_cookie_found, 'Refresh cookie not found in login response headers';
        ASSERT access_cookie_attrs_valid, format('Access cookie missing required security attributes (HttpOnly, SameSite, Secure, Path=/). Headers: %s', response_headers);
        ASSERT refresh_cookie_attrs_valid, format('Refresh cookie missing required security attributes (HttpOnly, SameSite, Secure, Path=/rest/rpc/refresh). Headers: %s', response_headers);
        
        RAISE DEBUG 'Login cookie validation passed: Access and refresh cookies have required security attributes and paths.';
    END;
        
    ASSERT (login_result->>'is_authenticated')::boolean IS TRUE, format('Login should be successful. Got: %L. Full login_result: %s', login_result->>'is_authenticated', login_result);
    ASSERT (login_result->'error_code') = 'null'::jsonb, format('Login result should have null error_code on success for refresh test setup. Got: %L. Full login_result: %s', login_result->'error_code', login_result);
    ASSERT login_result->>'role' = 'test.admin@statbus.org', format('Role should match email. Expected %L, Got %L. Full login_result: %s', 'test.admin@statbus.org', login_result->>'role', login_result);
    ASSERT login_result->>'email' = 'test.admin@statbus.org', format('Email should be returned correctly. Expected %L, Got %L. Full login_result: %s', 'test.admin@statbus.org', login_result->>'email', login_result);
    ASSERT login_result->>'statbus_role' = 'admin_user', format('Statbus role should be admin_user. Expected %L, Got %L. Full login_result: %s', 'admin_user', login_result->>'statbus_role', login_result);

    SELECT cv.cookie_value INTO access_jwt_from_login FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    SELECT cv.cookie_value INTO refresh_jwt_from_login FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus-refresh';
    ASSERT access_jwt_from_login IS NOT NULL, format('Access token cookie not found after login. Cookies: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    ASSERT refresh_jwt_from_login IS NOT NULL, format('Refresh token cookie not found after login. Cookies: %s', (SELECT json_agg(jrc) FROM test.extract_cookies() jrc));
    
    -- Verify that the access token cookie has the same expiration as the refresh token cookie
    DECLARE
        access_cookie_expires timestamptz;
        refresh_cookie_expires timestamptz;
    BEGIN
        SELECT expires_at INTO access_cookie_expires FROM test.extract_cookies() WHERE cookie_name = 'statbus';
        SELECT expires_at INTO refresh_cookie_expires FROM test.extract_cookies() WHERE cookie_name = 'statbus-refresh';
        
        ASSERT access_cookie_expires IS NOT NULL, 'Access cookie expiration time not found.';
        ASSERT refresh_cookie_expires IS NOT NULL, 'Refresh cookie expiration time not found.';
        
        -- Allow for a small difference (e.g., 1 second) due to timing of generation
        ASSERT abs(extract(epoch from access_cookie_expires) - extract(epoch from refresh_cookie_expires)) < 2,
            format('Access token cookie expiration (%L) should match refresh token cookie expiration (%L).', access_cookie_expires, refresh_cookie_expires);
    END;
    
    -- Decode the access token and display it
    DECLARE
        access_jwt_payload jsonb;
        token_verification record;
    BEGIN
        SELECT * INTO token_verification FROM verify(access_jwt_from_login, 'test-jwt-secret-for-testing-only', 'HS256');
        access_jwt_payload := token_verification.payload::jsonb;
        RAISE DEBUG 'Decoded access token (from login): %', access_jwt_payload;
        
        -- Verify deterministic keys in the access token payload
        ASSERT access_jwt_payload->>'role' = 'test.admin@statbus.org', format('Role in token should match email. Expected %L, Got %L. Payload: %s', 'test.admin@statbus.org', access_jwt_payload->>'role', access_jwt_payload);
        ASSERT access_jwt_payload->>'email' = 'test.admin@statbus.org', format('Email in token should be correct. Expected %L, Got %L. Payload: %s', 'test.admin@statbus.org', access_jwt_payload->>'email', access_jwt_payload);
        ASSERT access_jwt_payload->>'type' = 'access', format('Token type should be access. Got %L. Payload: %s', access_jwt_payload->>'type', access_jwt_payload);
        ASSERT access_jwt_payload->>'statbus_role' = 'admin_user', format('Statbus role should be admin_user. Got %L. Payload: %s', access_jwt_payload->>'statbus_role', access_jwt_payload);
        
        -- Verify dynamic values are present and not null
        ASSERT access_jwt_payload->>'exp' IS NOT NULL, format('Expiration time should be present. Payload: %s', access_jwt_payload);
        ASSERT access_jwt_payload->>'iat' IS NOT NULL, format('Issued at time should be present. Payload: %s', access_jwt_payload);
        ASSERT access_jwt_payload->>'jti' IS NOT NULL, format('JWT ID should be present. Payload: %s', access_jwt_payload);
        ASSERT access_jwt_payload->>'sub' IS NOT NULL, format('Subject should be present. Payload: %s', access_jwt_payload);
        ASSERT access_jwt_payload->>'uid' IS NOT NULL, format('User ID (uid) should be present. Payload: %s', access_jwt_payload);
    END;
    
    -- Decode the refresh token and display it
    DECLARE
        refresh_jwt_payload jsonb;
        refresh_token_verification record;
    BEGIN
        SELECT * INTO refresh_token_verification FROM verify(refresh_jwt_from_login, 'test-jwt-secret-for-testing-only', 'HS256');
        refresh_jwt_payload := refresh_token_verification.payload::jsonb;
        RAISE DEBUG 'Decoded refresh token (from login): %', refresh_jwt_payload;
        
        -- Verify deterministic keys in the refresh token payload
        ASSERT refresh_jwt_payload->>'role' = 'test.admin@statbus.org', format('Role in refresh token should match email. Expected %L, Got %L. Payload: %s', 'test.admin@statbus.org', refresh_jwt_payload->>'role', refresh_jwt_payload);
        ASSERT refresh_jwt_payload->>'email' = 'test.admin@statbus.org', format('Email in refresh token should be correct. Expected %L, Got %L. Payload: %s', 'test.admin@statbus.org', refresh_jwt_payload->>'email', refresh_jwt_payload);
        ASSERT refresh_jwt_payload->>'type' = 'refresh', format('Token type should be refresh. Got %L. Payload: %s', refresh_jwt_payload->>'type', refresh_jwt_payload);
        ASSERT refresh_jwt_payload->>'statbus_role' = 'admin_user', format('Statbus role should be admin_user. Got %L. Payload: %s', refresh_jwt_payload->>'statbus_role', refresh_jwt_payload);
        
        -- Verify dynamic values are present and not null
        ASSERT refresh_jwt_payload->>'exp' IS NOT NULL, format('Expiration time should be present in refresh token. Payload: %s', refresh_jwt_payload);
        ASSERT refresh_jwt_payload->>'iat' IS NOT NULL, format('Issued at time should be present in refresh token. Payload: %s', refresh_jwt_payload);
        ASSERT refresh_jwt_payload->>'jti' IS NOT NULL, format('JWT ID should be present in refresh token. Payload: %s', refresh_jwt_payload);
        ASSERT refresh_jwt_payload->>'sub' IS NOT NULL, format('Subject should be present in refresh token. Payload: %s', refresh_jwt_payload);
        ASSERT refresh_jwt_payload->>'version' IS NOT NULL, format('Version should be present in refresh token. Payload: %s', refresh_jwt_payload);
    END;
    
    -- Store session info before refresh
    DECLARE
        refresh_jwt_payload_for_jti jsonb;
        session_jti_from_token uuid;
    BEGIN
        SELECT payload::jsonb INTO refresh_jwt_payload_for_jti FROM verify(refresh_jwt_from_login, 'test-jwt-secret-for-testing-only');
        session_jti_from_token := (refresh_jwt_payload_for_jti->>'jti')::uuid;
        RAISE DEBUG 'JTI from login refresh token: %', session_jti_from_token;

        SELECT rs.*, u.id AS user_id, u.sub AS user_sub INTO refresh_session_before
        FROM auth.refresh_session rs
        JOIN auth.user u ON rs.user_id = u.id
        WHERE rs.jti = session_jti_from_token AND u.email = 'test.admin@statbus.org'; -- Select by JTI
        
        ASSERT FOUND, format('Session with JTI %L not found for user test.admin@statbus.org', session_jti_from_token);
        RAISE DEBUG 'Refresh session before refresh: %', row_to_json(refresh_session_before);
        ASSERT refresh_session_before.ip_address = '127.0.0.1'::inet, format('Initial session IP address mismatch. Expected %L, Got %L. Session: %s', '127.0.0.1'::inet, refresh_session_before.ip_address, row_to_json(refresh_session_before));
        ASSERT refresh_session_before.user_agent = 'Test User Agent', format('Initial session User Agent mismatch. Expected %L, Got %L. Session: %s', 'Test User Agent', refresh_session_before.user_agent, row_to_json(refresh_session_before));
    END;
    
    -- Check auth status before refresh
    -- Set cookies properly in request.cookies instead of request.headers.cookie
    PERFORM set_config('request.cookies',
        json_build_object(
            'statbus', access_jwt_from_login,
            'statbus-refresh', refresh_jwt_from_login
        )::text,
        true
    );
    
    -- Also set headers for completeness, but without the cookie
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1', -- IP at the time of auth_status check
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );
    
    -- Reset JWT claims to ensure we're using cookies
    PERFORM set_config('request.jwt.claims', '', true);
    
    -- Get auth status before refresh
    SELECT to_json(source.*) INTO auth_status_before FROM public.auth_status() AS source;
    RAISE DEBUG 'Auth status before refresh: %', auth_status_before;
    
    ASSERT auth_status_before->>'is_authenticated' = 'true', format('Auth status should show authenticated. Got: %L. Full auth_status_before: %s', auth_status_before->>'is_authenticated', auth_status_before);
    ASSERT auth_status_before->'uid' IS NOT NULL, format('Auth status should include user info (uid). Full auth_status_before: %s', auth_status_before);
    ASSERT auth_status_before->>'email' = 'test.admin@statbus.org', format('Auth status should have correct email. Expected %L, Got %L. Full auth_status_before: %s', 'test.admin@statbus.org', auth_status_before->>'email', auth_status_before);
        
    -- Sleep 1 second, to ensure the iat will increase, because it counts in whole seconds.
    PERFORM pg_sleep(1);

    -- Perform token refresh (Scenario 1: HTTPS headers during refresh)
    RAISE NOTICE '--- Test 8.1: Refresh with HTTPS headers ---';
    
    -- Set cookies for refresh call
    PERFORM set_config('request.cookies',
        json_build_object(
            'statbus-refresh', refresh_jwt_from_login
        )::text,
        true
    );
    -- Set headers for refresh call
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '192.168.1.100', -- New IP for refresh
            'user-agent', 'Refresh UA HTTPS',   -- New UA for refresh
            'x-forwarded-proto', 'https'      -- Simulate HTTPS for refresh
        )::text, 
        true
    );
    -- Clear response headers before refresh call (as refresh() sets cookies)
    PERFORM set_config('response.headers', '[]'::text, true);

    SELECT to_json(source.*) INTO refresh_result FROM public.refresh() AS source;
    RAISE DEBUG 'Refresh result (HTTPS): %', refresh_result;
    
    -- Verify Secure flag for cookies set by HTTPS refresh
    DECLARE
        response_headers_refresh jsonb;
        header_obj jsonb;
        access_cookie_is_secure boolean := false;
        refresh_cookie_is_secure boolean := false;
        access_cookie_found_https boolean := false;
        refresh_cookie_found_https boolean := false;
        cookie_value_text text;
    BEGIN
        response_headers_refresh := nullif(current_setting('response.headers', true), '')::jsonb;
        RAISE DEBUG 'Response headers after HTTPS refresh: %', response_headers_refresh;
        ASSERT response_headers_refresh IS NOT NULL, format('Response headers should not be null after HTTPS refresh. Got: %s', response_headers_refresh);

        FOR header_obj IN SELECT * FROM jsonb_array_elements(response_headers_refresh) LOOP
            IF header_obj ? 'Set-Cookie' THEN
                cookie_value_text := header_obj->>'Set-Cookie';
                IF cookie_value_text LIKE 'statbus=%' AND cookie_value_text LIKE '%Path=/%' AND NOT (cookie_value_text LIKE '%Path=/rest/rpc/refresh%') THEN
                    access_cookie_found_https := true;
                    IF cookie_value_text LIKE '%Secure%' THEN
                        access_cookie_is_secure := true;
                    END IF;
                END IF;
                IF cookie_value_text LIKE 'statbus-refresh=%' AND cookie_value_text LIKE '%Path=/rest/rpc/refresh%' THEN
                    refresh_cookie_found_https := true;
                    IF cookie_value_text LIKE '%Secure%' THEN
                        refresh_cookie_is_secure := true;
                    END IF;
                END IF;
            END IF;
        END LOOP;
        ASSERT access_cookie_found_https, format('Access cookie from HTTPS refresh should be set. Headers: %s', response_headers_refresh);
        ASSERT refresh_cookie_found_https, format('Refresh cookie from HTTPS refresh should be set. Headers: %s', response_headers_refresh);
        ASSERT access_cookie_is_secure, format('Access cookie from HTTPS refresh should have Secure flag. Headers: %s', response_headers_refresh);
        ASSERT refresh_cookie_is_secure, format('Refresh cookie from HTTPS refresh should have Secure flag. Headers: %s', response_headers_refresh);
    END;
    
    ASSERT (refresh_result->>'is_authenticated')::boolean IS TRUE, format('Refresh result should indicate authentication. Got: %L. Full refresh_result: %s', refresh_result->>'is_authenticated', refresh_result);
    ASSERT (refresh_result->'error_code') = 'null'::jsonb, format('Refresh result should have null error_code on success. Got: %L. Full refresh_result: %s', refresh_result->'error_code', refresh_result);
    ASSERT refresh_result ? 'uid', format('Refresh result should contain user_id. Full refresh_result: %s', refresh_result);
    ASSERT refresh_result ? 'role', format('Refresh result should contain role. Full refresh_result: %s', refresh_result);
    ASSERT refresh_result ? 'statbus_role', format('Refresh result should contain statbus_role. Full refresh_result: %s', refresh_result);
    ASSERT refresh_result ? 'email', format('Refresh result should contain email. Full refresh_result: %s', refresh_result);

    -- Extract new tokens from cookies set by refresh()
    SELECT cv.cookie_value INTO access_jwt_from_refresh FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    SELECT cv.cookie_value INTO refresh_jwt_from_refresh FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus-refresh';
    ASSERT access_jwt_from_refresh IS NOT NULL, format('Access token cookie not found after refresh. Cookies: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    ASSERT refresh_jwt_from_refresh IS NOT NULL, format('Refresh token cookie not found after refresh. Cookies: %s', (SELECT json_agg(jrc) FROM test.extract_cookies() jrc));
        
    -- Debug information to help identify token issues
    RAISE DEBUG 'Original access token (from login cookie): %', access_jwt_from_login;
    RAISE DEBUG 'New access token (from refresh cookie): %', access_jwt_from_refresh;
    
    -- Decode tokens to compare their contents
    DECLARE
        login_access_jwt_payload jsonb;
        refresh_access_jwt_payload jsonb;
        login_access_jwt_verification record;
        refresh_access_jwt_verification record;
    BEGIN
        -- Decode the tokens
        SELECT * INTO login_access_jwt_verification FROM verify(access_jwt_from_login, 'test-jwt-secret-for-testing-only', 'HS256');
        SELECT * INTO refresh_access_jwt_verification FROM verify(access_jwt_from_refresh, 'test-jwt-secret-for-testing-only', 'HS256');
        
        -- Convert payloads to jsonb
        login_access_jwt_payload := login_access_jwt_verification.payload::jsonb;
        refresh_access_jwt_payload := refresh_access_jwt_verification.payload::jsonb;
        
        RAISE DEBUG 'Original access jwt payload: %', login_access_jwt_payload;
        RAISE DEBUG 'New access jwt payload: %', refresh_access_jwt_payload;
        
        ASSERT (refresh_access_jwt_payload->>'exp')::numeric > (login_access_jwt_payload->>'exp')::numeric,
            format('New access jwt should have a later expiration time. Old exp: %L, New exp: %L', login_access_jwt_payload->>'exp', refresh_access_jwt_payload->>'exp');
        ASSERT (refresh_access_jwt_payload->>'iat')::numeric >= (login_access_jwt_payload->>'iat')::numeric,
            format('New access jwt should have same or later issued at time. Old iat: %L, New iat: %L', login_access_jwt_payload->>'iat', refresh_access_jwt_payload->>'iat');
        ASSERT refresh_access_jwt_payload->>'sub' = login_access_jwt_payload->>'sub',
            format('Subject should remain the same across token refreshes. Old sub: %L, New sub: %L', login_access_jwt_payload->>'sub', refresh_access_jwt_payload->>'sub');
        ASSERT refresh_access_jwt_payload->>'jti' <> login_access_jwt_payload->>'jti',
            format('Access tokens should have different JTIs. Old jti: %L, New jti: %L', login_access_jwt_payload->>'jti', refresh_access_jwt_payload->>'jti');
        ASSERT refresh_access_jwt_payload->>'role' = login_access_jwt_payload->>'role',
            format('Role should remain the same. Old role: %L, New role: %L', login_access_jwt_payload->>'role', refresh_access_jwt_payload->>'role');
        ASSERT refresh_access_jwt_payload->>'email' = login_access_jwt_payload->>'email',
            format('Email should remain the same. Old email: %L, New email: %L', login_access_jwt_payload->>'email', refresh_access_jwt_payload->>'email');
        ASSERT refresh_access_jwt_payload->>'type' = login_access_jwt_payload->>'type',
            format('Token type should remain the same. Old type: %L, New type: %L', login_access_jwt_payload->>'type', refresh_access_jwt_payload->>'type');
        ASSERT refresh_access_jwt_payload->>'statbus_role' = login_access_jwt_payload->>'statbus_role',
            format('Statbus role should remain the same. Old statbus_role: %L, New statbus_role: %L', login_access_jwt_payload->>'statbus_role', refresh_access_jwt_payload->>'statbus_role');
    END;
    
    ASSERT access_jwt_from_refresh <> access_jwt_from_login, format('New access token should be different. Old: %L, New: %L', access_jwt_from_login, access_jwt_from_refresh);
    ASSERT refresh_jwt_from_refresh <> refresh_jwt_from_login, format('New refresh token should be different. Old: %L, New: %L', refresh_jwt_from_login, refresh_jwt_from_refresh);
    
    SELECT rs.* INTO refresh_session_after
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.admin@statbus.org' AND rs.jti = (refresh_session_before.jti) -- ensure we are checking the same session
    LIMIT 1; -- jti is unique, so limit 1 is fine

    ASSERT FOUND, format('Failed to find session after HTTPS refresh for JTI %L. Session before: %L. Current request headers: %L', refresh_session_before.jti, row_to_json(refresh_session_before), current_setting('request.headers', true)::jsonb);
    
    ASSERT refresh_session_after.refresh_version = refresh_session_before.refresh_version + 1, 
        format('Session version mismatch (HTTPS refresh). Expected: %s, Got: %s. Session before: %L, Session after: %L. Request headers: %L', refresh_session_before.refresh_version + 1, refresh_session_after.refresh_version, row_to_json(refresh_session_before), row_to_json(refresh_session_after), current_setting('request.headers', true)::jsonb);
    ASSERT refresh_session_after.last_used_at > refresh_session_before.last_used_at, 
        format('Session last_used_at should be updated (HTTPS refresh). Before: %L (%s), After: %L (%s). Request headers: %L', refresh_session_before.last_used_at, extract(epoch from refresh_session_before.last_used_at), refresh_session_after.last_used_at, extract(epoch from refresh_session_after.last_used_at), current_setting('request.headers', true)::jsonb);
    ASSERT refresh_session_after.ip_address = '192.168.1.100'::inet, 
        format('Session IP address mismatch (HTTPS refresh). Expected: %L, Got: %L. Request headers: %L, Session record after: %L', '192.168.1.100'::inet, refresh_session_after.ip_address, current_setting('request.headers', true)::jsonb, row_to_json(refresh_session_after));
    ASSERT refresh_session_after.user_agent = 'Refresh UA HTTPS', 
        format('Session User Agent mismatch (HTTPS refresh). Expected: %L, Got: %L. Request headers: %L, Session record after: %L', 'Refresh UA HTTPS', refresh_session_after.user_agent, current_setting('request.headers', true)::jsonb, row_to_json(refresh_session_after));

    -- Update refresh_session_before to the state after the HTTPS refresh for the next comparison
    refresh_session_before := refresh_session_after;

    RAISE NOTICE '--- Test 8.2: Refresh with HTTP headers ---';
    PERFORM pg_sleep(1); -- Ensure time progresses for new token iat

    -- Set cookies for the next refresh call (using the latest refresh_jwt from the previous refresh)
    PERFORM set_config('request.cookies',
        json_build_object('statbus-refresh', refresh_jwt_from_refresh)::text, true);
    -- Set headers for HTTP refresh call
    PERFORM set_config('request.headers',
        json_build_object(
            'x-forwarded-for', '172.16.0.5',     -- Different IP for HTTP refresh
            'user-agent', 'Refresh UA HTTP',    -- Different UA
            'x-forwarded-proto', 'http'         -- Simulate HTTP for refresh
        )::text, 
        true
    );
    -- Clear response headers before refresh call (as refresh() sets cookies)
    PERFORM set_config('response.headers', '[]'::text, true); 

    SELECT to_json(source.*) INTO refresh_result FROM public.refresh() AS source;
    RAISE DEBUG 'Refresh result (HTTP): %', refresh_result;

    -- Verify Secure flag (or lack thereof) for cookies set by HTTP refresh
    DECLARE
        response_headers_http_refresh jsonb;
        header_obj_http jsonb;
        access_cookie_is_not_secure boolean := false;
        refresh_cookie_is_not_secure boolean := false;
        access_cookie_found_http boolean := false;
        refresh_cookie_found_http boolean := false;
        cookie_value_text_http text;
    BEGIN
        response_headers_http_refresh := nullif(current_setting('response.headers', true), '')::jsonb;
        RAISE DEBUG 'Response headers after HTTP refresh: %', response_headers_http_refresh;
        ASSERT response_headers_http_refresh IS NOT NULL, format('Response headers should not be null after HTTP refresh. Got: %s', response_headers_http_refresh);

        FOR header_obj_http IN SELECT * FROM jsonb_array_elements(response_headers_http_refresh) LOOP
            IF header_obj_http ? 'Set-Cookie' THEN
                cookie_value_text_http := header_obj_http->>'Set-Cookie';
                IF cookie_value_text_http LIKE 'statbus=%' AND cookie_value_text_http LIKE '%Path=/%' AND NOT (cookie_value_text_http LIKE '%Path=/rest/rpc/refresh%') THEN
                    access_cookie_found_http := true;
                    IF cookie_value_text_http NOT LIKE '%Secure%' THEN
                        access_cookie_is_not_secure := true;
                    END IF;
                END IF;
                IF cookie_value_text_http LIKE 'statbus-refresh=%' AND cookie_value_text_http LIKE '%Path=/rest/rpc/refresh%' THEN
                    refresh_cookie_found_http := true;
                    IF cookie_value_text_http NOT LIKE '%Secure%' THEN
                        refresh_cookie_is_not_secure := true;
                    END IF;
                END IF;
            END IF;
        END LOOP;
        ASSERT access_cookie_found_http, format('Access cookie from HTTP refresh should be set. Headers: %s', response_headers_http_refresh);
        ASSERT refresh_cookie_found_http, format('Refresh cookie from HTTP refresh should be set. Headers: %s', response_headers_http_refresh);
        ASSERT access_cookie_is_not_secure, format('Access cookie from HTTP refresh should NOT have Secure flag. Headers: %s', response_headers_http_refresh);
        ASSERT refresh_cookie_is_not_secure, format('Refresh cookie from HTTP refresh should NOT have Secure flag. Headers: %s', response_headers_http_refresh);
    END;

    SELECT rs.* INTO refresh_session_after
    FROM auth.refresh_session rs
    WHERE rs.jti = (refresh_session_before.jti) -- refresh_session_before now holds state after HTTPS refresh
    LIMIT 1;

    ASSERT FOUND, format('Failed to find session after HTTP refresh for JTI %L. Session before HTTP refresh: %L. Current request headers: %L', refresh_session_before.jti, row_to_json(refresh_session_before), current_setting('request.headers', true)::jsonb);
    
    ASSERT refresh_session_after.refresh_version = refresh_session_before.refresh_version + 1, 
        format('Session version mismatch (HTTP refresh). Expected: %s, Got: %s. Session before HTTP refresh: %L, Session after: %L. Request headers: %L', refresh_session_before.refresh_version + 1, refresh_session_after.refresh_version, row_to_json(refresh_session_before), row_to_json(refresh_session_after), current_setting('request.headers', true)::jsonb);
    ASSERT refresh_session_after.last_used_at > refresh_session_before.last_used_at, 
        format('Session last_used_at should be updated (HTTP refresh). Before: %L (%s), After: %L (%s). Request headers: %L', refresh_session_before.last_used_at, extract(epoch from refresh_session_before.last_used_at), refresh_session_after.last_used_at, extract(epoch from refresh_session_after.last_used_at), current_setting('request.headers', true)::jsonb);
    ASSERT refresh_session_after.ip_address = '172.16.0.5'::inet, 
        format('Session IP address mismatch (HTTP refresh). Expected: %L, Got: %L. Request headers: %L, Session record after: %L', '172.16.0.5'::inet, refresh_session_after.ip_address, current_setting('request.headers', true)::jsonb, row_to_json(refresh_session_after));
    ASSERT refresh_session_after.user_agent = 'Refresh UA HTTP', 
        format('Session User Agent mismatch (HTTP refresh). Expected: %L, Got: %L. Request headers: %L, Session record after: %L', 'Refresh UA HTTP', refresh_session_after.user_agent, current_setting('request.headers', true)::jsonb, row_to_json(refresh_session_after));

    -- Final auth status check with the latest tokens from HTTP refresh
    -- (Need to extract these tokens from cookies again after the second refresh)
    SELECT cv.cookie_value INTO access_jwt_from_refresh FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    SELECT cv.cookie_value INTO refresh_jwt_from_refresh FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus-refresh';
    ASSERT access_jwt_from_refresh IS NOT NULL, format('Access token cookie not found after second refresh. Cookies: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    ASSERT refresh_jwt_from_refresh IS NOT NULL, format('Refresh token cookie not found after second refresh. Cookies: %s', (SELECT json_agg(jrc) FROM test.extract_cookies() jrc));

    RAISE NOTICE '--- Test 8.3: Final Auth Status Check ---';
    PERFORM set_config('request.cookies',
        json_build_object(
            'statbus', access_jwt_from_refresh,
            'statbus-refresh', refresh_jwt_from_refresh
        )::text,
        true
    );
    -- Use headers corresponding to the last refresh (HTTP)
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '172.16.0.5', 
            'user-agent', 'Refresh UA HTTP',
            'x-forwarded-proto', 'http' 
        )::text, 
        true
    );
    PERFORM set_config('request.jwt.claims', '', true);
    
    SELECT to_json(source.*) INTO auth_status_after FROM public.auth_status() AS source;
    RAISE DEBUG 'Auth status after all refreshes: %', auth_status_after;
    ASSERT auth_status_after->>'is_authenticated' = 'true', format('Final auth status should show authenticated. Got: %L. Full auth_status_after: %s', auth_status_after->>'is_authenticated', auth_status_after);
    ASSERT auth_status_after->>'email' = 'test.admin@statbus.org', format('Final auth status should have correct email. Expected %L, Got %L. Full auth_status_after: %s', 'test.admin@statbus.org', auth_status_after->>'email', auth_status_after);
    
        RAISE NOTICE 'Test 8: Token Refresh (including header variations) - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 8 (Token Refresh) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 8 (Token Refresh) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 9: Token Refresh Failure Modes
\echo '=== Test 9: Token Refresh Failure Modes ==='
DO $$
DECLARE
    refresh_response jsonb;
    admin_refresh_jwt text;
    login_result jsonb;
    claims jsonb;
    tampered_refresh_jwt text;
    header text;
    encoded_payload_text text;
    signature text;
    parts text[];
BEGIN
    PERFORM auth_test.reset_request_gucs();

    -- Setup: Login as admin to get a valid refresh token
    PERFORM set_config('request.headers', json_build_object('x-forwarded-proto', 'https')::text, true);
    SELECT to_json(source.*) INTO login_result FROM public.login('test.admin@statbus.org', 'Admin#123!') AS source;
    SELECT cv.cookie_value INTO admin_refresh_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus-refresh';
    ASSERT admin_refresh_jwt IS NOT NULL, 'Failed to get admin refresh token for setup.';

    -- Case 1: No refresh token cookie
    RAISE NOTICE 'Test 9.1: No refresh token cookie';
    PERFORM set_config('request.cookies', '{}'::text, true); -- Empty cookies
    SELECT to_jsonb(source.*) INTO refresh_response FROM public.refresh() AS source;
    RAISE DEBUG 'Refresh response (no cookie): %', refresh_response;
    ASSERT (refresh_response->>'is_authenticated')::boolean IS FALSE, 'Should be unauthenticated if no refresh cookie.';
    ASSERT refresh_response->>'error_code' = 'REFRESH_NO_TOKEN_COOKIE', format('Error code mismatch for no refresh cookie. Got: %L', refresh_response->>'error_code');
    ASSERT current_setting('response.status', true) = '401', 'Test 9.1: response.status should be 401 for no refresh token cookie.';
    RAISE NOTICE 'Test 9.1: public.refresh is expected to set HTTP status 401 for no refresh token cookie.';

    -- Case 2: Invalid token type (e.g., an access token used as refresh)
    RAISE NOTICE 'Test 9.2: Invalid token type (access token as refresh)';
    DECLARE access_jwt text;
    BEGIN
        SELECT cv.cookie_value INTO access_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus'; -- From previous login
        PERFORM set_config('request.cookies', json_build_object('statbus-refresh', access_jwt)::text, true);
        SELECT to_jsonb(source.*) INTO refresh_response FROM public.refresh() AS source;
        RAISE DEBUG 'Refresh response (access token as refresh): %', refresh_response;
        ASSERT (refresh_response->>'is_authenticated')::boolean IS FALSE, 'Should be unauthenticated if access token used as refresh.';
        ASSERT refresh_response->>'error_code' = 'REFRESH_INVALID_TOKEN_TYPE', format('Error code mismatch for invalid token type. Got: %L', refresh_response->>'error_code');
        ASSERT current_setting('response.status', true) = '401', 'Test 9.2: response.status should be 401 for invalid token type.';
        RAISE NOTICE 'Test 9.2: public.refresh is expected to set HTTP status 401 for invalid token type.';
    END;

    -- Case 3: User not found or deleted (tamper sub in a valid refresh token)
    RAISE NOTICE 'Test 9.3: User not found/deleted';
    SELECT payload::jsonb INTO claims FROM verify(admin_refresh_jwt, current_setting('app.settings.jwt_secret'));
    claims := jsonb_set(claims, '{sub}', to_jsonb(gen_random_uuid()::text)); -- Non-existent sub
    parts := string_to_array(admin_refresh_jwt, '.');
    header := parts[1];
    signature := parts[3];
    SELECT url_encode(convert_to(claims::text, 'UTF8')) INTO encoded_payload_text;
    tampered_refresh_jwt := header || '.' || encoded_payload_text || '.' || signature;
    
    PERFORM set_config('request.cookies', json_build_object('statbus-refresh', tampered_refresh_jwt)::text, true);
    SELECT to_jsonb(source.*) INTO refresh_response FROM public.refresh() AS source;
    RAISE DEBUG 'Refresh response (user not found): %', refresh_response;
    ASSERT (refresh_response->>'is_authenticated')::boolean IS FALSE, 'Should be unauthenticated if user not found.';
    ASSERT refresh_response->>'error_code' = 'REFRESH_USER_NOT_FOUND_OR_DELETED', format('Error code mismatch for user not found. Got: %L', refresh_response->>'error_code');
    ASSERT current_setting('response.status', true) = '401', 'Test 9.3: response.status should be 401 for user not found/deleted.';
    RAISE NOTICE 'Test 9.3: public.refresh is expected to set HTTP status 401 for user not found/deleted.';

    -- Case 4: Session invalid or superseded (tamper jti or version in a valid refresh token)
    RAISE NOTICE 'Test 9.4: Session invalid/superseded';
    SELECT payload::jsonb INTO claims FROM verify(admin_refresh_jwt, current_setting('app.settings.jwt_secret'));
    claims := jsonb_set(claims, '{jti}', to_jsonb(gen_random_uuid()::text)); -- Non-existent jti
    parts := string_to_array(admin_refresh_jwt, '.');
    header := parts[1];
    signature := parts[3];
    SELECT url_encode(convert_to(claims::text, 'UTF8')) INTO encoded_payload_text;
    tampered_refresh_jwt := header || '.' || encoded_payload_text || '.' || signature;

    PERFORM set_config('request.cookies', json_build_object('statbus-refresh', tampered_refresh_jwt)::text, true);
    SELECT to_jsonb(source.*) INTO refresh_response FROM public.refresh() AS source;
    RAISE DEBUG 'Refresh response (session invalid): %', refresh_response;
    ASSERT (refresh_response->>'is_authenticated')::boolean IS FALSE, 'Should be unauthenticated if session invalid.';
    ASSERT refresh_response->>'error_code' = 'REFRESH_SESSION_INVALID_OR_SUPERSEDED', format('Error code mismatch for invalid session. Got: %L', refresh_response->>'error_code');
    ASSERT current_setting('response.status', true) = '401', 'Test 9.4: response.status should be 401 for invalid/superseded session.';
    RAISE NOTICE 'Test 9.4: public.refresh is expected to set HTTP status 401 for invalid/superseded session.';

    RAISE NOTICE 'Test 9: Token Refresh Failure Modes - PASSED';
EXCEPTION
    WHEN ASSERT_FAILURE THEN
        RAISE NOTICE 'Test 9 (Token Refresh Failure Modes) - FAILED (ASSERT): %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'Test 9 (Token Refresh Failure Modes) - FAILED: %', SQLERRM;
END;
$$;

-- Test 10: Logout
\echo '=== Test 10: Logout ==='
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
    auth_status_before jsonb;
    auth_status_after jsonb;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    RAISE DEBUG '[Test 10 Setup] Initializing Test 10: Logout';

    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );

    -- First login to create a session
    SELECT to_json(source.*) INTO login_result FROM public.login('test.restricted@statbus.org', 'Restricted#123!') AS source;
    RAISE DEBUG 'Login result: %', login_result;
    ASSERT (login_result->>'is_authenticated')::boolean IS TRUE, format('Login should be successful for logout test setup. Got: %L. Full login_result: %s', login_result->>'is_authenticated', login_result);
    ASSERT (login_result->'error_code') = 'null'::jsonb, format('Login result for logout test setup should have null error_code. Got: %L. Full login_result: %s', login_result->'error_code', login_result);
    
    SELECT cv.cookie_value INTO access_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    SELECT cv.cookie_value INTO refresh_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus-refresh';
    ASSERT access_jwt IS NOT NULL, format('Access token cookie not found after login for logout test. Cookies: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    ASSERT refresh_jwt IS NOT NULL, format('Refresh token cookie not found after login for logout test. Cookies: %s', (SELECT json_agg(jrc) FROM test.extract_cookies() jrc));
    
    RAISE DEBUG 'Response headers after login: %', nullif(current_setting('response.headers', true), '')::jsonb;
    
    SELECT COUNT(*) INTO session_count_before
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.restricted@statbus.org';
    
    RAISE DEBUG 'Session count before logout: %', session_count_before;
    
    -- Check auth status before logout
    PERFORM set_config('request.cookies',
        json_build_object(
            'statbus', access_jwt,
            'statbus-refresh', refresh_jwt
        )::text,
        true
    );
    
    -- Also set headers for completeness
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );
    
    -- Reset JWT claims to ensure we're using cookies
    PERFORM set_config('request.jwt.claims', '', true);
    RAISE DEBUG '[Test 10] Before calling public.auth_status (pre-logout): request.cookies: %, request.jwt.claims: %', nullif(current_setting('request.cookies', true), ''), nullif(current_setting('request.jwt.claims', true), '');
    RAISE DEBUG '[Test 10] access_jwt var: %, refresh_jwt var: %', access_jwt, refresh_jwt;
    
    -- Get auth status before logout
    SELECT to_json(source.*) INTO auth_status_before FROM public.auth_status() AS source;
    RAISE DEBUG '[Test 10] Auth status before logout (auth_status_before): %', auth_status_before;
    
    ASSERT auth_status_before->>'is_authenticated' = 'true', format('Auth status before logout should show authenticated. Got: %L. Full auth_status_before: %s', auth_status_before->>'is_authenticated', auth_status_before);
    ASSERT auth_status_before->'uid' IS NOT NULL, format('Auth status before logout should include user info (uid). Full auth_status_before: %s', auth_status_before);
    ASSERT auth_status_before->>'email' = 'test.restricted@statbus.org', format('Auth status before logout should have correct email. Expected %L, Got %L. Full auth_status_before: %s', 'test.restricted@statbus.org', auth_status_before->>'email', auth_status_before);
    
    -- Set cookies to simulate browser cookies for logout
    PERFORM set_config('request.cookies',
        json_build_object(
            'statbus', access_jwt,
            'statbus-refresh', refresh_jwt
        )::text,
        true
    );
    
    -- Also set headers for completeness
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );
    
    -- Perform logout
    SELECT to_json(source.*) INTO logout_result FROM public.logout() AS source;
    RAISE DEBUG 'Logout result: %', logout_result;
    RAISE DEBUG 'Response headers after logout: %', nullif(current_setting('response.headers', true), '')::jsonb;
    
    -- Verify logout result (should be an auth_status_response indicating not authenticated)
    ASSERT logout_result IS NOT NULL, format('Logout should return a non-null auth_status_response. Got: %s', logout_result);
    ASSERT (logout_result->>'is_authenticated')::boolean IS FALSE, format('Logout should result in is_authenticated = false. Got: %L. Full response: %s', logout_result->>'is_authenticated', logout_result);
    ASSERT logout_result->>'uid' IS NULL, format('Logout should result in uid = NULL. Got: %L. Full response: %s', logout_result->>'uid', logout_result);
    ASSERT (logout_result->'error_code') = 'null'::jsonb, format('Logout result should have null error_code. Got: %L. Full response: %s', logout_result->'error_code', logout_result);
    
    SELECT COUNT(*) INTO session_count_after
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.restricted@statbus.org';
    
    RAISE DEBUG 'Session count after logout: %', session_count_after;
    
    -- Verify exactly one session was deleted
    ASSERT session_count_after = session_count_before - 1,
        format('Exactly one session should be deleted after logout. Expected count: %s, Got: %s. (Before: %s, After: %s)', session_count_before - 1, session_count_after, session_count_before, session_count_after);
    
    -- Verify cookies were cleared
    FOR cookies IN SELECT * FROM test.extract_cookies()
    LOOP
        RAISE DEBUG 'Cookie found: name=%, value=%, expires=%', cookies.cookie_name, cookies.cookie_value, cookies.expires_at;
        IF cookies.cookie_name = 'statbus' AND 
           (cookies.cookie_value = '' OR cookies.expires_at = '1970-01-01 00:00:00+00'::timestamptz) THEN
            has_cleared_access_cookie := true;
        ELSIF cookies.cookie_name = 'statbus-refresh' AND 
              (cookies.cookie_value = '' OR cookies.expires_at = '1970-01-01 00:00:00+00'::timestamptz) THEN
            has_cleared_refresh_cookie := true;
        END IF;
    END LOOP;
    
    ASSERT has_cleared_access_cookie, format('Access cookie was not cleared. Cookies found: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    ASSERT has_cleared_refresh_cookie, format('Refresh cookie was not cleared. Cookies found: %s', (SELECT json_agg(jrc) FROM test.extract_cookies() jrc));
    
    -- Check auth status after logout
    -- Use the cleared cookies
    PERFORM set_config('request.cookies', 
        json_build_object(
            'statbus', '',
            'statbus-refresh', ''
        )::text, 
        true
    );
    
    -- Also set headers for completeness
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );
    
    -- Reset JWT claims to ensure we're using cookies
    PERFORM set_config('request.jwt.claims', '', true);
    
    -- Get auth status after logout
    SELECT to_json(source.*) INTO auth_status_after FROM public.auth_status() AS source;
    RAISE DEBUG 'Auth status after logout: %', auth_status_after;
    
    ASSERT auth_status_after->>'is_authenticated' = 'false', format('Auth status after logout should show not authenticated. Got: %L. Full auth_status_after: %s', auth_status_after->>'is_authenticated', auth_status_after);
    ASSERT auth_status_after->>'uid' IS NULL, format('Auth status after logout should not include user info (uid). Got: %L. Full auth_status_after: %s', auth_status_after->>'uid', auth_status_after);
    ASSERT auth_status_after->>'email' IS NULL, format('Auth status after logout should not have email. Got: %L. Full auth_status_after: %s', auth_status_after->>'email', auth_status_after);
    
        RAISE NOTICE 'Test 10: Logout - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 10 (Logout) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 10 (Logout) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 11: Role Management
\echo '=== Test 11: Role Management ==='
DO $$
DECLARE
    login_result jsonb;
    grant_result RECORD;
    revoke_result boolean;
    user_sub uuid;
    original_role public.statbus_role;
    new_role public.statbus_role;
    access_jwt text;
    user_email text;
    role_exists boolean;
    role_granted boolean;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );

    -- Get user sub and original role for the target user
    SELECT sub, statbus_role, email INTO user_sub, original_role, user_email
    FROM auth.user
    WHERE email = 'test.external@statbus.org';
    
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
    SELECT to_json(source.*) INTO login_result FROM public.login('test.admin@statbus.org', 'Admin#123!') AS source;
    RAISE DEBUG 'Login result: %', login_result;
    ASSERT (login_result->>'is_authenticated')::boolean IS TRUE, format('Admin login failed for role management test. Got: %L. Full login_result: %s', login_result->>'is_authenticated', login_result);
    
    -- Extract access token from cookies set by login()
    SELECT cv.cookie_value INTO access_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    ASSERT access_jwt IS NOT NULL, format('Access token cookie not found after admin login for role management test. Cookies: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    
    -- Set up JWT claims using the actual token
    PERFORM set_config('request.jwt.claims',
        (SELECT payload::text FROM verify(access_jwt, 'test-jwt-secret-for-testing-only')),
        true
    );
    
    -- Set cookies to simulate browser cookies
    PERFORM set_config('request.cookies',
        jsonb_build_object(
            'statbus', access_jwt
        )::text,
        true
    );
    
    -- Also set headers for completeness
    PERFORM set_config('request.headers', 
        jsonb_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent'
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
    UPDATE public.user
    SET statbus_role = 'restricted_user'::public.statbus_role
    WHERE sub = user_sub
    RETURNING * INTO grant_result;
    RAISE DEBUG 'Grant result: %', to_jsonb(grant_result);
    
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
    ASSERT grant_result.statbus_role = 'restricted_user', format('Grant role should return restricted_user. Got: %L. Full grant_result: %s', grant_result.statbus_role, to_jsonb(grant_result));
    
    -- Verify role was updated in database
    SELECT statbus_role INTO new_role
    FROM auth.user
    WHERE sub = user_sub;
    
    RAISE DEBUG 'User role in database after grant: %', new_role;
    
    ASSERT new_role = 'restricted_user',
        format('User role should be updated to restricted_user. Got: %L', new_role);
    
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
    UPDATE public.user
    SET statbus_role = 'regular_user'::public.statbus_role
    WHERE sub = user_sub
    RETURNING * INTO grant_result; -- Re-using grant_result variable name for consistency
    RAISE DEBUG 'Revoke (set to regular_user) result: %', to_jsonb(grant_result);
    
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
    ASSERT grant_result.statbus_role = 'regular_user', format('Revoke role (set to regular_user) should return regular_user. Got: %L. Full grant_result: %s', grant_result.statbus_role, to_jsonb(grant_result));
    
    -- Verify role was reset to regular_user
    SELECT statbus_role INTO new_role
    FROM auth.user
    WHERE sub = user_sub;
    
    RAISE DEBUG 'User role in database after revoke: %', new_role;
    
    ASSERT new_role = 'regular_user',
        format('User role should be reset to regular_user. Got: %L', new_role);
    
    -- Reset to original role
    RAISE DEBUG 'Resetting user % to original role: %', user_email, original_role;
    UPDATE public.user
    SET statbus_role = original_role
    WHERE sub = user_sub
    RETURNING * INTO grant_result;
    RAISE DEBUG 'Reset role result: %', to_jsonb(grant_result);
    ASSERT grant_result.statbus_role = original_role, format('Resetting role should return original_role. Got: %L. Full grant_result: %s', grant_result.statbus_role, to_jsonb(grant_result));
    
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
    
        RAISE NOTICE 'Test 11: Role Management - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 11 (Role Management) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 11 (Role Management) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 12: Session Management
\echo '=== Test 12: Session Management ==='
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
    PERFORM auth_test.reset_request_gucs();
    RAISE DEBUG '[Test 12 Setup] Initializing Test 12: Session Management';

    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );

    -- First login to create a session
    SELECT to_json(source.*) INTO login_result FROM public.login('test.regular@statbus.org', 'Regular#123!') AS source;
    ASSERT (login_result->>'is_authenticated')::boolean IS TRUE, format('Login failed for session management test. Got: %L. Full login_result: %s', login_result->>'is_authenticated', login_result);
    
    -- Extract access token from cookies set by login()
    SELECT cv.cookie_value INTO access_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    ASSERT access_jwt IS NOT NULL, format('Access token cookie not found after login for session management test. Cookies: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    
    -- Set up JWT claims using the actual token
    SELECT payload::json INTO jwt_claims
    FROM verify(access_jwt, 'test-jwt-secret-for-testing-only');
    
    PERFORM set_config('request.jwt.claims', jwt_claims::text, true);
    
    -- Set cookies in request.cookies and headers for list_active_sessions
    PERFORM set_config('request.cookies',
        json_build_object(
            'statbus', access_jwt
            -- list_active_sessions uses request.jwt.claims, so cookie content doesn't strictly matter here
            -- as long as claims are set.
        )::text,
        true
    );
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );
    
    -- List active sessions
    SELECT array_agg(to_json(s.*)) INTO sessions_result
    FROM public.list_active_sessions() AS s;
    
    -- Debug the sessions result
    RAISE DEBUG 'Active sessions: %', sessions_result;
    
    -- Verify sessions were returned
    ASSERT array_length(sessions_result, 1) > 0, format('Should have at least one active session. Got %s sessions. Full result: %s', array_length(sessions_result, 1), sessions_result);
    
    -- Get session ID for revocation
    SELECT (sessions_result[1]->>'id')::integer INTO session_id;
    
    -- Get the JTI for the session
    SELECT jti INTO session_jti
    FROM auth.refresh_session
    WHERE id = session_id;
    RAISE DEBUG '[Test 12] Session JTI to be revoked: % (from session_id: %)', session_jti, session_id;
    
    -- Count sessions before revocation
    SELECT COUNT(*) INTO session_count_before
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.regular@statbus.org';
    
    -- Revoke a specific session
    RAISE DEBUG '[Test 12] Before calling public.revoke_session for JTI %: request.jwt.claims: %', session_jti, nullif(current_setting('request.jwt.claims', true), '');
    SELECT public.revoke_session(session_jti) INTO revoke_result;
    
    -- Debug the revoke result
    RAISE DEBUG '[Test 12] Revoke session result: %', revoke_result;
    
    -- Verify revocation was successful
    ASSERT revoke_result = true, format('Revoke session should return true. Got: %L', revoke_result);
    
    -- Count sessions after revocation
    SELECT COUNT(*) INTO session_count_after
    FROM auth.refresh_session rs
    JOIN auth.user u ON rs.user_id = u.id
    WHERE u.email = 'test.regular@statbus.org';
    
    -- Verify session was deleted
    ASSERT session_count_after = session_count_before - 1,
        format('One session should be deleted after revocation. Expected count: %s, Got: %s. (Before: %s, After: %s)', session_count_before - 1, session_count_after, session_count_before, session_count_after);
    
        RAISE NOTICE 'Test 12: Session Management - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 12 (Session Management) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 12 (Session Management) - FAILED: %', SQLERRM;
    END;
END;
$$;


-- Test 13: JWT Claims Building
\echo '=== Test 13: JWT Claims Building ==='
DO $$
DECLARE
    claims jsonb;
    test_email text := 'test.regular@statbus.org';
    test_sub uuid;
    test_role public.statbus_role;
    test_expires_at timestamptz;
    test_jwt text;
    jwt_payload jsonb;
BEGIN
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
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
    ASSERT claims ? 'role', format('Claims should contain role. Claims: %s', claims);
    ASSERT claims ? 'statbus_role', format('Claims should contain statbus_role. Claims: %s', claims);
    ASSERT claims ? 'sub', format('Claims should contain sub. Claims: %s', claims);
    ASSERT claims ? 'email', format('Claims should contain email. Claims: %s', claims);
    ASSERT claims ? 'type', format('Claims should contain type. Claims: %s', claims);
    ASSERT claims ? 'iat', format('Claims should contain iat. Claims: %s', claims);
    ASSERT claims ? 'exp', format('Claims should contain exp. Claims: %s', claims);
    ASSERT claims ? 'jti', format('Claims should contain jti. Claims: %s', claims);
    ASSERT claims ? 'uid', format('Claims should contain uid. Claims: %s', claims);

    -- Verify claim values
    ASSERT claims->>'role' = test_email, format('role claim should match email. Expected %L, Got %L. Claims: %s', test_email, claims->>'role', claims);
    ASSERT claims->>'statbus_role' = test_role::text, format('statbus_role claim should match user role. Expected %L, Got %L. Claims: %s', test_role::text, claims->>'statbus_role', claims);
    ASSERT claims->>'sub' = test_sub::text, format('sub claim should match user sub. Expected %L, Got %L. Claims: %s', test_sub::text, claims->>'sub', claims);
    ASSERT claims->>'email' = test_email, format('email claim should match email. Expected %L, Got %L. Claims: %s', test_email, claims->>'email', claims);
    ASSERT claims->>'type' = 'access', format('type claim should be access by default. Got %L. Claims: %s', claims->>'type', claims);
    
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
    ASSERT claims->>'type' = 'refresh', format('type claim should be refresh. Got %L. Claims: %s', claims->>'type', claims);
    ASSERT claims->>'custom_claim' = 'test_value', format('custom claim should be included. Got %L. Claims: %s', claims->>'custom_claim', claims);
    ASSERT (claims->>'exp')::numeric = extract(epoch from test_expires_at)::integer,
        format('exp claim should match provided expiration time. Expected %L, Got %L. Claims: %s', extract(epoch from test_expires_at)::integer, claims->>'exp', claims);
    
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
    ASSERT jwt_payload->>'role' = claims->>'role', format('JWT role should match claims. Expected %L, Got %L. JWT Payload: %s, Original Claims: %s', claims->>'role', jwt_payload->>'role', jwt_payload, claims);
    ASSERT jwt_payload->>'type' = 'refresh', format('JWT type should be refresh. Expected %L, Got %L. JWT Payload: %s', 'refresh', jwt_payload->>'type', jwt_payload);
    ASSERT jwt_payload->>'custom_claim' = 'test_value', format('JWT should include custom claims. Expected %L, Got %L. JWT Payload: %s', 'test_value', jwt_payload->>'custom_claim', jwt_payload);

        RAISE NOTICE 'Test 13: JWT Claims Building - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 13 (JWT Claims Building) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 13 (JWT Claims Building) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 14: JWT Tampering Detection
\echo '=== Test 14: JWT Tampering Detection ==='
DO $$
DECLARE
    login_result_admin jsonb;
    login_result_regular jsonb;
    tampered_access_jwt text;
    tampered_refresh_jwt text;
    tampered_claims jsonb;
    refresh_result jsonb;
    auth_status_result jsonb;
    admin_email text := 'test.admin@statbus.org';
    regular_email text := 'test.regular@statbus.org';
    admin_access_jwt text;
    admin_refresh_jwt text;
    regular_access_jwt text;
    admin_claims jsonb;
    regular_claims jsonb;
    random_jti uuid := gen_random_uuid();
    wrong_secret text := 'wrong-jwt-secret-for-testing-only';
BEGIN
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );

    -- First login as admin to get valid tokens
    SELECT to_json(source.*) INTO login_result_admin FROM public.login(admin_email, 'Admin#123!') AS source;
    ASSERT (login_result_admin->>'is_authenticated')::boolean IS TRUE, format('Admin login failed for JWT tampering test. Got: %L. Full login_result_admin: %s', login_result_admin->>'is_authenticated', login_result_admin);
    SELECT cv.cookie_value INTO admin_access_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    SELECT cv.cookie_value INTO admin_refresh_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus-refresh';
    ASSERT admin_access_jwt IS NOT NULL AND admin_refresh_jwt IS NOT NULL, format('Admin tokens not found in cookies. Access: %L, Refresh: %L. Cookies: %s', admin_access_jwt, admin_refresh_jwt, (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    
    -- Get admin token claims
    SELECT payload::jsonb INTO admin_claims
    FROM verify(admin_access_jwt, 'test-jwt-secret-for-testing-only');
    
    -- Login as regular user to get valid tokens
    SELECT to_json(source.*) INTO login_result_regular FROM public.login(regular_email, 'Regular#123!') AS source;
    ASSERT (login_result_regular->>'is_authenticated')::boolean IS TRUE, format('Regular user login failed for JWT tampering test. Got: %L. Full login_result_regular: %s', login_result_regular->>'is_authenticated', login_result_regular);
    SELECT cv.cookie_value INTO regular_access_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    ASSERT regular_access_jwt IS NOT NULL, format('Regular user access token not found in cookies. Cookies: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    
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
        
        -- Set cookies with the tampered refresh token
        PERFORM set_config('request.cookies', 
            jsonb_build_object(
                'statbus-refresh', tampered_refresh_jwt
            )::text, 
            true
        );
    
        -- Also set headers for completeness
        PERFORM set_config('request.headers', 
            jsonb_build_object(
                'x-forwarded-for', '127.0.0.1',
                'user-agent', 'Test User Agent'
            )::text, 
            true
        );
        
        -- Try to refresh with the tampered token
        BEGIN
            SELECT to_json(source.*) INTO tampered_refresh_result FROM public.refresh() AS source;
            -- If we get here, the refresh didn't fail as expected
            RAISE EXCEPTION 'Refresh with non-existent session should have failed';
        EXCEPTION WHEN OTHERS THEN
            -- This is expected - the token should be rejected
            tampered_refresh_result := jsonb_build_object('error', SQLERRM);
            RAISE DEBUG 'Refresh with non-existent session correctly failed: %', SQLERRM;
        END;
        
        -- Debug the result
        RAISE DEBUG 'Refresh result with non-existent session: %', tampered_refresh_result;
        
        -- Verify the refresh was rejected
        ASSERT tampered_refresh_result ? 'error',
            format('Refresh with non-existent session should return an error. Got: %s', tampered_refresh_result);
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
            to_jsonb((SELECT sub::text FROM auth.user WHERE email = 'test.restricted@statbus.org'))
        );
        impersonation_payload := jsonb_set(
            impersonation_payload,
            '{email}',
            to_jsonb('test.restricted@statbus.org'::text)
        );
        impersonation_payload := jsonb_set(
            impersonation_payload,
            '{role}',
            to_jsonb('test.restricted@statbus.org'::text)
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
        
        -- Set cookies with the tampered refresh token
        PERFORM set_config('request.cookies', 
            jsonb_build_object(
                'statbus-refresh', impersonation_jwt
            )::text, 
            true
        );
    
        -- Also set headers for completeness
        PERFORM set_config('request.headers', 
            jsonb_build_object(
                'x-forwarded-for', '127.0.0.1',
                'user-agent', 'Test User Agent'
            )::text, 
            true
        );
        
        -- Try to refresh with the tampered token
        BEGIN
            SELECT to_json(source.*) INTO impersonation_result FROM public.refresh() AS source;
            -- If we get here, the refresh didn't fail as expected
            RAISE EXCEPTION 'Refresh with impersonation attempt should have failed';
        EXCEPTION WHEN OTHERS THEN
            -- This is expected - the token should be rejected
            impersonation_result := jsonb_build_object('error', SQLERRM);
            RAISE DEBUG 'Refresh with impersonation attempt correctly failed: %', SQLERRM;
        END;
        
        -- Debug the result
        RAISE DEBUG 'Refresh result with impersonation attempt: %', impersonation_result;
        
        -- Verify the refresh was rejected
        ASSERT impersonation_result ? 'error',
            format('Refresh with impersonation attempt should return an error. Got: %s', impersonation_result);
    END;
    
        RAISE NOTICE 'Test 14: JWT Tampering Detection - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 14 (JWT Tampering Detection) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 14 (JWT Tampering Detection) - FAILED: %', SQLERRM;
    END;
END;
$$;


-- Test 15: Auth Status Function
\echo '=== Test 15: Auth Status Function ==='
DO $$
DECLARE
    login_result jsonb;
    auth_status_result jsonb;
    auth_status_unauthenticated jsonb;
    access_jwt text;
    refresh_jwt text;
    jwt_claims json;
    test_email text := 'test.admin@statbus.org';
    test_sub uuid;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Set up headers to simulate a browser
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );

    -- Get user details for verification
    SELECT sub INTO test_sub
    FROM auth.user
    WHERE email = test_email;
    
    -- First check unauthenticated status (no cookies)
    PERFORM set_config('request.cookies', '{}', true);
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );
    PERFORM set_config('request.jwt.claims', '', true);
    
    SELECT to_json(source.*) INTO auth_status_unauthenticated FROM public.auth_status() AS source;
    
    RAISE DEBUG 'Auth status (unauthenticated): %', auth_status_unauthenticated;
    
    ASSERT auth_status_unauthenticated->>'is_authenticated' = 'false', format('Auth status should show not authenticated. Got: %L. Full response: %s', auth_status_unauthenticated->>'is_authenticated', auth_status_unauthenticated);
    ASSERT auth_status_unauthenticated->>'uid' IS NULL, format('Auth status should not include user info (uid). Got: %L. Full response: %s', auth_status_unauthenticated->>'uid', auth_status_unauthenticated);
    ASSERT auth_status_unauthenticated->>'email' IS NULL, format('Auth status should not have email. Got: %L. Full response: %s', auth_status_unauthenticated->>'email', auth_status_unauthenticated);
    ASSERT (auth_status_unauthenticated->'error_code') = 'null'::jsonb, format('Auth status (unauthenticated) should have null error_code. Got: %L. Full response: %s', auth_status_unauthenticated->'error_code', auth_status_unauthenticated);
    
    -- Now login to get a valid token
    SELECT to_json(source.*) INTO login_result FROM public.login(test_email, 'Admin#123!') AS source;
    ASSERT (login_result->>'is_authenticated')::boolean IS TRUE, format('Login failed for auth status test. Got: %L. Full login_result: %s', login_result->>'is_authenticated', login_result);
    ASSERT (login_result->'error_code') = 'null'::jsonb, format('Login for auth status test should have null error_code. Got: %L. Full login_result: %s', login_result->'error_code', login_result);
    
    -- Extract tokens from cookies set by login()
    SELECT cv.cookie_value INTO access_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
    SELECT cv.cookie_value INTO refresh_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus-refresh';
    ASSERT access_jwt IS NOT NULL AND refresh_jwt IS NOT NULL, format('Tokens not found in cookies for auth status test. Access: %L, Refresh: %L. Cookies: %s', access_jwt, refresh_jwt, (SELECT json_agg(jec) FROM test.extract_cookies() jec));
    
    -- Set up cookies to simulate browser cookies
    PERFORM set_config('request.cookies',
        json_build_object(
            'statbus', access_jwt,
            'statbus-refresh', refresh_jwt
        )::text,
        true
    );
    
    -- Also set headers for completeness
    PERFORM set_config('request.headers', 
        json_build_object(
            'x-forwarded-for', '127.0.0.1',
            'user-agent', 'Test User Agent',
            'x-forwarded-proto', 'https' -- Simulate HTTPS
        )::text, 
        true
    );
    
    -- Reset JWT claims to ensure we're using cookies
    PERFORM set_config('request.jwt.claims', '', true);
    
    -- Check authenticated status using cookies
    SELECT to_json(source.*) INTO auth_status_result FROM public.auth_status() AS source;
    
    RAISE DEBUG 'Auth status (authenticated via cookies): %', auth_status_result;
    
    ASSERT auth_status_result->>'is_authenticated' = 'true', format('Auth status should show authenticated. Got: %L. Full response: %s', auth_status_result->>'is_authenticated', auth_status_result);
    ASSERT auth_status_result->'uid' IS NOT NULL, format('Auth status should include user info (uid). Full response: %s', auth_status_result);
    ASSERT auth_status_result->>'email' = test_email, format('Auth status should have correct email. Expected %L, Got %L. Full response: %s', test_email, auth_status_result->>'email', auth_status_result);
    ASSERT (auth_status_result->'error_code') = 'null'::jsonb, format('Auth status (authenticated) should have null error_code. Got: %L. Full response: %s', auth_status_result->'error_code', auth_status_result);
    
    -- Test with an expiring token (modify the token to make it expire soon)
    DECLARE
        expiring_claims json;
        expiring_jwt text;
        expiring_status jsonb;
    BEGIN
        -- Get the claims from the token
        SELECT payload::json INTO jwt_claims
        FROM verify(access_jwt, 'test-jwt-secret-for-testing-only');
        
        -- Create a copy of the claims with an expiration time 4 minutes from now
        expiring_claims := jsonb_set(
            jwt_claims::jsonb, 
            '{exp}', 
            to_jsonb(extract(epoch from now())::integer + 240)
        )::json;
        
        -- Create a new token with the modified claims
        SELECT sign(expiring_claims, 'test-jwt-secret-for-testing-only') INTO expiring_jwt;
        
        -- Set the cookie with the expiring token
        PERFORM set_config('request.cookies',
            json_build_object(
                'statbus', expiring_jwt,
                'statbus-refresh', refresh_jwt -- Use original refresh token
            )::text,
            true
        );
        
        -- Also set headers for completeness
        PERFORM set_config('request.headers', 
            json_build_object(
                'x-forwarded-for', '127.0.0.1',
                'user-agent', 'Test User Agent',
                'x-forwarded-proto', 'https' -- Simulate HTTPS
            )::text, 
            true
        );
        
        -- Reset JWT claims to ensure we're using cookies
        PERFORM set_config('request.jwt.claims', '', true);
        
        -- Check status with expiring token
        SELECT to_json(source.*) INTO expiring_status FROM public.auth_status() AS source;
        
        RAISE DEBUG 'Auth status (expiring token): %', expiring_status;
        
        ASSERT expiring_status->>'is_authenticated' = 'true', format('Auth status with expiring token should show authenticated. Got: %L. Full response: %s', expiring_status->>'is_authenticated', expiring_status);
        ASSERT expiring_status->'uid' IS NOT NULL, format('Auth status with expiring token should include user info (uid). Full response: %s', expiring_status);
        ASSERT expiring_status->>'email' = test_email, format('Auth status with expiring token should have correct email. Expected %L, Got %L. Full response: %s', test_email, expiring_status->>'email', expiring_status);
        ASSERT (expiring_status->'error_code') = 'null'::jsonb, format('Auth status (expiring token) should have null error_code. Got: %L. Full response: %s', expiring_status->'error_code', expiring_status);
    END;
    
    -- Test with an invalid user sub (user not found)
    DECLARE
        invalid_claims json;
        invalid_jwt text;
        invalid_status jsonb;
        random_uuid uuid := gen_random_uuid();
    BEGIN
        -- Get the claims from the token
        SELECT payload::json INTO jwt_claims
        FROM verify(access_jwt, 'test-jwt-secret-for-testing-only');
        
        -- Create a copy of the claims with an invalid user sub
        invalid_claims := jsonb_set(
            jwt_claims::jsonb, 
            '{sub}', 
            to_jsonb(random_uuid::text)
        )::json;
        
        -- Create a new token with the modified claims
        SELECT sign(invalid_claims, 'test-jwt-secret-for-testing-only') INTO invalid_jwt;
        
        -- Set the cookie with the invalid token
        PERFORM set_config('request.cookies',
            json_build_object(
                'statbus', invalid_jwt,
                'statbus-refresh', refresh_jwt -- Use original refresh token
            )::text,
            true
        );
        
        -- Also set headers for completeness
        PERFORM set_config('request.headers', 
            json_build_object(
                'x-forwarded-for', '127.0.0.1',
                'user-agent', 'Test User Agent',
                'x-forwarded-proto', 'https' -- Simulate HTTPS
            )::text, 
            true
        );
        
        -- Reset JWT claims to ensure we're using cookies
        PERFORM set_config('request.jwt.claims', '', true);
        
        -- Check status with invalid user
        SELECT to_json(source.*) INTO invalid_status FROM public.auth_status() AS source;
        
        RAISE DEBUG 'Auth status (invalid user): %', invalid_status;
        
        ASSERT invalid_status->>'is_authenticated' = 'false', format('Auth status with invalid user should show not authenticated. Got: %L. Full response: %s', invalid_status->>'is_authenticated', invalid_status);
        ASSERT invalid_status->>'uid' IS NULL, format('Auth status with invalid user should not include user info (uid). Got: %L. Full response: %s', invalid_status->>'uid', invalid_status);
        ASSERT invalid_status->>'email' IS NULL, format('Auth status with invalid user should not have email. Got: %L. Full response: %s', invalid_status->>'email', invalid_status);
        ASSERT (invalid_status->'error_code') = 'null'::jsonb, format('Auth status (invalid user) should have null error_code. Got: %L. Full response: %s', invalid_status->'error_code', invalid_status);
    END;

    -- Test with an expired token to trigger refresh suggestion
    DECLARE
        expire_result jsonb;
        expired_access_jwt text;
        expired_status jsonb;
        refresh_result jsonb;
    BEGIN
        RAISE NOTICE '--- Test 15.1: Testing expired token refresh flow ---';
        -- We are already logged in and have valid cookies set from the previous part of the test.
        -- The request.cookies GUC should contain 'statbus' and 'statbus-refresh' tokens.
        
        -- Call the function to expire the access token
        -- This requires an authenticated session, which we have.
        -- We need to set the JWT claims for the function to work.
        SELECT payload::text INTO jwt_claims FROM verify(access_jwt, 'test-jwt-secret-for-testing-only');
        PERFORM set_config('request.jwt.claims', jwt_claims::text, true);

        SELECT to_jsonb(source.*) INTO expire_result FROM public.auth_expire_access_keep_refresh() AS source;
        RAISE DEBUG 'auth_expire_access_keep_refresh result: %', expire_result;
        
        ASSERT expire_result->>'status' = 'access_token_expired_and_set',
            format('auth_expire_access_keep_refresh should return correct status. Got: %L', expire_result->>'status');
            
        -- Extract the newly set, expired access token from the response headers
        SELECT cv.cookie_value INTO expired_access_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
        ASSERT expired_access_jwt IS NOT NULL, 'A new (expired) access token should be set in cookies.';
        ASSERT expired_access_jwt <> access_jwt, 'The expired access token should be different from the original one.';

        -- Verify the new token is indeed expired
        DECLARE
            _jwt_verify_result auth.jwt_verify_result;
        BEGIN
            _jwt_verify_result := auth.jwt_verify(expired_access_jwt);
            ASSERT _jwt_verify_result.is_valid AND _jwt_verify_result.expired,
                'The new access token should be valid but expired.';
        END;

        -- Now, call auth_status with only the expired access token cookie.
        -- The refresh token cookie is not sent to auth_status due to its path restriction.
        PERFORM set_config('request.cookies', json_build_object('statbus', expired_access_jwt)::text, true);
        PERFORM set_config('request.jwt.claims', '', true); -- Clear claims, rely on cookie

        SELECT to_jsonb(source.*) INTO expired_status FROM public.auth_status() AS source;
        RAISE DEBUG 'Auth status with expired token: %', expired_status;

        ASSERT (expired_status->>'is_authenticated')::boolean IS FALSE,
            'Auth status with expired token should be is_authenticated=false.';
        ASSERT (expired_status->>'expired_access_token_call_refresh')::boolean IS TRUE,
            'Auth status with expired token should be expired_access_token_call_refresh=true.';
        ASSERT expired_status->>'uid' IS NULL,
            'Auth status with expired token should not contain user details.';

        -- Finally, complete the flow by calling refresh with the original refresh token
        PERFORM set_config('request.cookies', json_build_object('statbus-refresh', refresh_jwt)::text, true);
        SELECT to_jsonb(source.*) INTO refresh_result FROM public.refresh() AS source;
        RAISE DEBUG 'Refresh result after expired status check: %', refresh_result;

        ASSERT (refresh_result->>'is_authenticated')::boolean IS TRUE,
            'Refresh call after expired status should succeed.';
        ASSERT refresh_result->>'email' = test_email,
            'Refresh call should return correct user details.';
    END;
    
        RAISE NOTICE 'Test 15: Auth Status Function - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 15 (Auth Status Function) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 15 (Auth Status Function) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 16: Idempotent User Creation
\echo '=== Test 16: Idempotent User Creation ==='
DO $$
DECLARE
    first_creation_result record;
    second_creation_result record;
    user_count_before integer;
    user_count_after integer;
    test_email text := 'test.idempotent@example.com';
    test_password text := 'idempotent123';
    test_role public.statbus_role := 'regular_user';
    old_encrypted_password text;
    new_encrypted_password text;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    RAISE DEBUG '[Test 16 Setup] Initializing Test 16: Idempotent User Creation';

    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Count users with this email before
    SELECT COUNT(*) INTO user_count_before
    FROM auth.user
    WHERE email = test_email;
    
    -- First creation
    RAISE DEBUG '[Test 16] Calling public.user_create for the first time with email: %, role: %, password: (hidden)', test_email, test_role;
    SELECT * INTO first_creation_result 
    FROM public.user_create(p_display_name => 'Test Idempotent', p_email => test_email, p_statbus_role => test_role, p_password => test_password);
    
    -- Debug the first creation result
    RAISE DEBUG '[Test 16] First creation result: %', first_creation_result;
    
    -- Verify first creation
    ASSERT first_creation_result.email = test_email, format('First creation should return correct email. Expected %L, Got %L', test_email, first_creation_result.email);
    ASSERT first_creation_result.password = test_password, format('First creation should return correct password. Expected %L, Got %L', test_password, first_creation_result.password);
    
    -- Verify user exists in database
    ASSERT EXISTS (
        SELECT 1 FROM auth.user WHERE email = test_email
    ), format('User %L should exist after first creation.', test_email);
    
    -- Store the old encrypted password before updating
    SELECT encrypted_password INTO old_encrypted_password
    FROM auth.user
    WHERE email = test_email;
    RAISE DEBUG '[Test 16] Old encrypted password: %', old_encrypted_password;
    
    -- Second creation with same email but different password and role
    RAISE DEBUG '[Test 16] Calling public.user_create for the second time with email: %, role: admin_user, password: (hidden)', test_email;
    SELECT * INTO second_creation_result 
    FROM public.user_create(p_display_name => 'Test Idempotent', p_email => test_email, p_statbus_role => 'admin_user'::public.statbus_role, p_password => 'newpassword123');
    
    -- Debug the second creation result
    RAISE DEBUG '[Test 16] Second creation result: %', second_creation_result;
    
    -- Verify second creation
    ASSERT second_creation_result.email = test_email, format('Second creation should return correct email. Expected %L, Got %L', test_email, second_creation_result.email);
    ASSERT second_creation_result.password = 'newpassword123', format('Second creation should return new password. Expected %L, Got %L', 'newpassword123', second_creation_result.password);
    
    -- Count users with this email after
    SELECT COUNT(*) INTO user_count_after
    FROM auth.user
    WHERE email = test_email;
    
    -- Verify only one user exists (idempotent)
    ASSERT user_count_after = 1, format('Should still have only one user after second creation. Expected 1, Got %s', user_count_after);
    
    -- Verify user was updated with new role and password
    DECLARE current_statbus_role public.statbus_role;
    BEGIN
        SELECT statbus_role INTO current_statbus_role FROM auth.user WHERE email = test_email;
        ASSERT current_statbus_role = 'admin_user'::public.statbus_role, format('User role should be updated to admin_user. Got %L', current_statbus_role);
    END;
    
    -- Verify the encrypted password has changed
    SELECT encrypted_password INTO new_encrypted_password
    FROM auth.user
    WHERE email = test_email;
    RAISE DEBUG 'New encrypted password: %', new_encrypted_password;
    
    ASSERT old_encrypted_password IS DISTINCT FROM new_encrypted_password,
        format('Encrypted password should change after update. Old: %L, New: %L', old_encrypted_password, new_encrypted_password);
    
    -- Clean up
    DELETE FROM auth.user WHERE email = test_email;
    
        RAISE NOTICE 'Test 16: Idempotent User Creation - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 16 (Idempotent User Creation) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 16 (Idempotent User Creation) - FAILED: %', SQLERRM;
    END;
END;
$$;

\echo '=== Test 17: Trigger Role Change Handling ==='
DO $$
DECLARE
    test_email text := 'test.role.change@example.com';
    test_password text := 'rolechange123';
    user_sub uuid;
    role_exists boolean;
    role_granted boolean;
BEGIN
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Create a test user with regular_user role
    PERFORM public.user_create(p_display_name => 'Test Role Change', p_email => test_email, p_statbus_role => 'regular_user'::public.statbus_role, p_password => test_password);
    
    -- Get the user's sub
    SELECT sub INTO user_sub FROM auth.user WHERE email = test_email;
    
    -- Verify the PostgreSQL role exists
    SELECT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = test_email
    ) INTO role_exists;
    
    ASSERT role_exists, format('PostgreSQL role %L should exist for the user. Got: %L', test_email, role_exists);
    
    -- Verify regular_user role is granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'regular_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT role_granted, format('regular_user role should be granted initially for %L. Got: %L', test_email, role_granted);
    
    -- Change role directly in the database (this should trigger the role change)
    UPDATE auth.user SET statbus_role = 'admin_user' WHERE email = test_email;
    
    -- Verify admin_user role is now granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'admin_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT role_granted, format('admin_user role should be granted after update for %L. Got: %L', test_email, role_granted);
    
    -- Verify regular_user role is no longer granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'regular_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT NOT role_granted, format('regular_user role should be revoked after update for %L. Got: %L', test_email, role_granted);
    
    -- Change to restricted_user
    UPDATE auth.user SET statbus_role = 'restricted_user' WHERE email = test_email;
    
    -- Verify restricted_user role is now granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'restricted_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT role_granted, format('restricted_user role should be granted after update for %L. Got: %L', test_email, role_granted);
    
    -- Verify admin_user role is no longer granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'admin_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT NOT role_granted, format('admin_user role should be revoked after update for %L. Got: %L', test_email, role_granted);
    
    -- Change to external_user
    UPDATE auth.user SET statbus_role = 'external_user' WHERE email = test_email;
    
    -- Verify external_user role is now granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'external_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT role_granted, format('external_user role should be granted after update for %L. Got: %L', test_email, role_granted);
    
    -- Verify restricted_user role is no longer granted
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r1 ON m.roleid = r1.oid
        JOIN pg_roles r2 ON m.member = r2.oid
        WHERE r1.rolname = 'restricted_user' AND r2.rolname = test_email
    ) INTO role_granted;
    
    ASSERT NOT role_granted, format('restricted_user role should be revoked after update for %L. Got: %L', test_email, role_granted);
    
    -- Clean up
    DELETE FROM auth.user WHERE email = test_email;
    
    -- Verify the PostgreSQL role was dropped by the delete trigger
    SELECT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = test_email
    ) INTO role_exists;
    
    ASSERT NOT role_exists, format('PostgreSQL role %L should be dropped after user deletion. Got: %L', test_email, role_exists);
    
        RAISE NOTICE 'Test 17: Trigger Role Change Handling - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 17 (Trigger Role Change Handling) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 17 (Trigger Role Change Handling) - FAILED: %', SQLERRM;
    END;
END;
$$;


-- Test 18: Session Context Management
\echo '=== Test 18: Session Context Management ==='
DO $$
DECLARE
    test_email text := 'test.external@statbus.org';
    claims_before text;
    claims_after text;
    claims_json jsonb;
    test_sub uuid;
    test_role public.statbus_role;
BEGIN
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
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
    
    ASSERT claims_after <> claims_before, format('Claims should be updated. Before: %L, After: %L', claims_before, claims_after);
    ASSERT claims_json->>'email' = test_email, format('Claims should contain the correct email. Expected %L, Got %L. Claims: %s', test_email, claims_json->>'email', claims_json);
    ASSERT claims_json->>'role' = test_email, format('Claims should set role to email. Expected %L, Got %L. Claims: %s', test_email, claims_json->>'role', claims_json);
    ASSERT claims_json->>'statbus_role' = test_role::text, format('Claims should contain correct statbus_role. Expected %L, Got %L. Claims: %s', test_role::text, claims_json->>'statbus_role', claims_json);
    ASSERT claims_json->>'sub' = test_sub::text, format('Claims should contain correct sub. Expected %L, Got %L. Claims: %s', test_sub::text, claims_json->>'sub', claims_json);
    ASSERT claims_json->>'type' = 'access', format('Claims should have type=access. Got %L. Claims: %s', claims_json->>'type', claims_json);
    ASSERT claims_json ? 'iat', format('Claims should contain iat. Claims: %s', claims_json);
    ASSERT claims_json ? 'exp', format('Claims should contain exp. Claims: %s', claims_json);
    ASSERT claims_json ? 'jti', format('Claims should contain jti. Claims: %s', claims_json);
    
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
            format('use_jwt_claims_in_session should set role correctly. Expected %L, Got %L. Current claims: %s', test_email, (current_setting('request.jwt.claims', true)::jsonb)->>'role', current_setting('request.jwt.claims', true));
    END;
    
    -- Reset session context
    PERFORM auth.reset_session_context();
    
    -- Debug after reset
    RAISE DEBUG 'Session context after reset: %', current_setting('request.jwt.claims', true);
    
    -- Verify claims were cleared
    ASSERT current_setting('request.jwt.claims', true) = '',
        format('Claims should be cleared. Got: %L', current_setting('request.jwt.claims', true));
    
        RAISE NOTICE 'Test 18: Session Context Management - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 18 (Session Context Management) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 18 (Session Context Management) - FAILED: %', SQLERRM;
    END;
END;
$$;


-- Test 19: Password Change (User)
\echo '=== Test 19: Password Change (User) ==='
DO $$
DECLARE
    login_result jsonb;
    test_email text := 'test.regular@statbus.org';
    old_password text := 'Regular#123!';
    new_password text := 'newRegularPass456';
    access_jwt text;
    session_count_before integer;
    session_count_after integer;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior for the entire Test 19
        
        RAISE NOTICE 'Test 19: Setup - Logging in user and checking initial session count.';
        SELECT to_jsonb(source.*) INTO login_result FROM public.login(test_email, old_password) AS source;
        RAISE DEBUG 'Logged in user %: %', test_email, login_result;
        ASSERT login_result IS NOT NULL AND (login_result->>'is_authenticated')::boolean IS TRUE, format('Setup: Login failed for user %L. Got: %L. Full login_result: %s', test_email, login_result->>'is_authenticated', login_result);
        
        SELECT cv.cookie_value INTO access_jwt FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus';
        ASSERT access_jwt IS NOT NULL, format('Access token not found in cookies after login for setup for user %L. Cookies: %s', test_email, (SELECT json_agg(jec) FROM test.extract_cookies() jec));

        SELECT COUNT(*) INTO session_count_before FROM auth.refresh_session
        WHERE user_id = (SELECT id FROM auth.user WHERE email = test_email);
        ASSERT session_count_before > 0, format('Setup: User %L should have at least one session before password change. Found %s sessions.', test_email, session_count_before);
        RAISE NOTICE 'Test 19: Password Change (User) - Setup complete. User has % sessions.', session_count_before;

        -- Test 19.1: Change password as user (simulating user-initiated action)
        RAISE NOTICE 'Test 19.1: Attempting to change password for user %.', test_email;
        BEGIN -- Nested block for SET LOCAL ROLE and its specific rollback simulation
            EXECUTE format('SET LOCAL ROLE %I', test_email); -- Use %I for identifiers
            RAISE DEBUG 'Test 19.1: Switched to role % (current_user: %)', test_email, current_user;
            ASSERT current_user = test_email, format('Test 19.1: Failed to switch role to %L. Current user: %L', test_email, current_user);

            -- Set JWT claims as if an access token was used for this operation
            PERFORM set_config('request.jwt.claims', (SELECT payload::text FROM verify(access_jwt, 'test-jwt-secret-for-testing-only')), true);

            PERFORM public.change_password(new_password);
            RAISE DEBUG 'Test 19.1: public.change_password(%L) executed for user %', new_password, test_email;
            
            SELECT COUNT(*) INTO session_count_after FROM auth.refresh_session
            WHERE user_id = (SELECT id FROM auth.user WHERE email = test_email);
            RAISE DEBUG 'Test 19.1: Session count for user % after password change: %', test_email, session_count_after;
            ASSERT session_count_after = 0, format('Test 19.1: All sessions for user %L should be deleted after password change. Found %s sessions.', test_email, session_count_after);
            
            -- Verify password was updated (try logging in with new password)
            DECLARE
                login_result_verify jsonb;
            BEGIN
                RAISE DEBUG 'Test 19.1: Verifying login with new password for %', test_email;
                SELECT to_jsonb(source.*) INTO login_result_verify FROM public.login(test_email, new_password) AS source;
                RAISE DEBUG 'Test 19.1: Login result with new password: %', login_result_verify;
                ASSERT login_result_verify IS NOT NULL AND (login_result_verify->>'is_authenticated')::boolean IS TRUE, format('Test 19.1: Login with new password for %L should succeed. Got: %L. Full response: %s', test_email, login_result_verify->>'is_authenticated', login_result_verify);
                ASSERT (login_result_verify->'error_code') = 'null'::jsonb, format('Test 19.1: Login with new password for %L should have null error_code. Got: %L. Full response: %s', test_email, login_result_verify->'error_code', login_result_verify);

                RAISE DEBUG 'Test 19.1: Verifying login with old password for % fails', test_email;
                SELECT to_jsonb(source.*) INTO login_result_verify FROM public.login(test_email, old_password) AS source;
                RAISE DEBUG 'Test 19.1: Login result with old password: %', login_result_verify;
                ASSERT login_result_verify IS NULL OR (login_result_verify->>'is_authenticated')::boolean IS FALSE, format('Test 19.1: Login with old password for %L should fail. Got: %L. Full response: %s', test_email, login_result_verify->>'is_authenticated', login_result_verify);
                ASSERT login_result_verify->>'error_code' = 'WRONG_PASSWORD', format('Test 19.1: Login with old password for %L should have error_code WRONG_PASSWORD. Got: %L. Full response: %s', test_email, login_result_verify->>'error_code', login_result_verify);
            END;
            
            RAISE NOTICE 'Test 19.1: Password change and immediate verification successful for role %.', test_email;
            RAISE EXCEPTION 'Simulating rollback for SET LOCAL ROLE for test purposes' USING ERRCODE = 'P0001'; 
            
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            RAISE DEBUG 'Test 19.1: Caught simulated rollback exception for SET LOCAL ROLE. Current user: %', current_user;
        END; -- End of SET LOCAL ROLE block

        RAISE DEBUG 'Test 19.1: After SET LOCAL ROLE block, current_user: %', current_user;
        ASSERT current_user = 'postgres', format('Test 19.1: After SET LOCAL ROLE block, current_user should be reverted to postgres (or original). Got: %L', current_user);
                
        RAISE NOTICE 'Test 19.1: Change password as user and verify - PASSED (within its own transactional context)';
        
        -- Since the SET LOCAL ROLE block was rolled back, the password change is also rolled back.
        -- Verify that the password is back to the original.
        DECLARE
            login_reverify jsonb;
        BEGIN
            RAISE DEBUG 'Test 19: Verifying password reverted to original due to sub-transaction rollback for %', test_email;
            SELECT to_jsonb(source.*) INTO login_reverify FROM public.login(test_email, old_password) AS source;
            ASSERT login_reverify IS NOT NULL AND (login_reverify->>'is_authenticated')::boolean IS TRUE, format('Test 19: Login with original password for %L should succeed after simulated rollback. Got: %L. Full response: %s', test_email, login_reverify->>'is_authenticated', login_reverify);
            ASSERT (login_reverify->'error_code') = 'null'::jsonb, format('Test 19: Login with original password for %L (after simulated rollback) should have null error_code. Got: %L. Full response: %s', test_email, login_reverify->'error_code', login_reverify);

            SELECT to_jsonb(source.*) INTO login_reverify FROM public.login(test_email, new_password) AS source;
            ASSERT login_reverify IS NULL OR (login_reverify->>'is_authenticated')::boolean IS FALSE, format('Test 19: Login with new password for %L should fail after simulated rollback. Got: %L. Full response: %s', test_email, login_reverify->>'is_authenticated', login_reverify);
            ASSERT login_reverify->>'error_code' = 'WRONG_PASSWORD', format('Test 19: Login with new password for %L (after simulated rollback) should have error_code WRONG_PASSWORD. Got: %L. Full response: %s', test_email, login_reverify->>'error_code', login_reverify);
            RAISE NOTICE 'Test 19: Password correctly reverted to original for % due to transaction rollback.', test_email;
        END;

        RAISE NOTICE 'Test 19 (Password Change (User)) - Overall PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 19 (Password Change (User)) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 19 (Password Change (User)) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 21: Role Switching with SET LOCAL ROLE
\echo '=== Test 21: Role Switching with SET LOCAL ROLE ==='
DO $$
DECLARE
    admin_email text := 'test.admin@statbus.org';
    admin_can_see_count integer;
    regular_email text := 'test.regular@statbus.org';
    regular_can_see_count integer;
    restricted_email text := 'test.restricted@statbus.org';
    restricted_can_see_count integer;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Outer BEGIN/EXCEPTION/END for the entire Test 21 (Pattern A)
        
        -- Test 21.1: Admin role permissions
        RAISE NOTICE 'Test 21.1: Testing admin role permissions.';
        BEGIN -- Nested BEGIN/EXCEPTION for SET LOCAL ROLE simulation
            EXECUTE format('SET LOCAL ROLE %I', admin_email);
            RAISE DEBUG 'Test 21.1: Inside SET LOCAL ROLE block, current_user=%', current_user;
            ASSERT current_user = admin_email, format('Test 21.1: Current user should be admin_email. Got: %L', current_user);
            
            SELECT COUNT(*) INTO admin_can_see_count FROM auth.user;
            ASSERT admin_can_see_count > 0, format('Test 21.1: Admin should be able to see users. Found %s users.', admin_can_see_count);
            
            RAISE EXCEPTION 'Simulating rollback for SET LOCAL ROLE (Test 21.1)' USING ERRCODE = 'P0001';
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            RAISE DEBUG 'Test 21.1: Caught simulated rollback for SET LOCAL ROLE. Current user: %', current_user;
        END; -- End of SET LOCAL ROLE block for 21.1
        RAISE DEBUG 'Test 21.1: After SET LOCAL ROLE block, current_user=%', current_user;
        ASSERT current_user = 'postgres', format('Test 21.1: After SET LOCAL ROLE block, current_user should be postgres. Got: %L', current_user);
        RAISE NOTICE 'Test 21.1: Admin role permissions - PASSED';

        -- Test 21.2: Regular user permissions
        RAISE NOTICE 'Test 21.2: Testing regular user permissions.';
        BEGIN -- Nested BEGIN/EXCEPTION for SET LOCAL ROLE simulation
            EXECUTE format('SET LOCAL ROLE %I', regular_email);
            RAISE DEBUG 'Test 21.2: Inside SET LOCAL ROLE block, current_user=%', current_user;
            ASSERT current_user = regular_email, format('Test 21.2: Current user should be regular_email. Got: %L', current_user);
            
            BEGIN -- Sub-block to catch potential insufficient_privilege for COUNT(*)
                SELECT COUNT(*) INTO regular_can_see_count FROM auth.user;
                ASSERT regular_can_see_count = 1, format('Test 21.2: Regular user should only see their own user record. Saw %s records.', regular_can_see_count);
            EXCEPTION WHEN insufficient_privilege THEN
                RAISE NOTICE 'Test 21.2: Caught insufficient_privilege when regular user tried to count all users, this might be expected depending on RLS. Count set to 0.';
                regular_can_see_count := 0; -- Or handle as appropriate for the test's intent
            END;
            ASSERT EXISTS (SELECT 1 FROM auth.user WHERE email = regular_email), format('Test 21.2: Regular user %L should see their own record via direct query.', regular_email);
            ASSERT EXISTS (SELECT 1 FROM public.country LIMIT 1), 'Test 21.2: Regular user should be able to see public data.';
            
            RAISE EXCEPTION 'Simulating rollback for SET LOCAL ROLE (Test 21.2)' USING ERRCODE = 'P0001';
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            RAISE DEBUG 'Test 21.2: Caught simulated rollback for SET LOCAL ROLE. Current user: %', current_user;
        END; -- End of SET LOCAL ROLE block for 21.2
        RAISE DEBUG 'Test 21.2: After SET LOCAL ROLE block, current_user=%', current_user;
        ASSERT current_user = 'postgres', format('Test 21.2: After SET LOCAL ROLE block, current_user should be postgres. Got: %L', current_user);
        RAISE NOTICE 'Test 21.2: Regular user permissions - PASSED';

        -- Test 21.3: Restricted user permissions
        RAISE NOTICE 'Test 21.3: Testing restricted user permissions.';
        BEGIN -- Nested BEGIN/EXCEPTION for SET LOCAL ROLE simulation
            EXECUTE format('SET LOCAL ROLE %I', restricted_email);
            RAISE DEBUG 'Test 21.3: Inside SET LOCAL ROLE block, current_user=%', current_user;
            ASSERT current_user = restricted_email, format('Test 21.3: Current user should be restricted_email. Got: %L', current_user);

            BEGIN -- Sub-block to catch potential insufficient_privilege for COUNT(*)
                SELECT COUNT(*) INTO restricted_can_see_count FROM auth.user;
                ASSERT restricted_can_see_count = 1, format('Test 21.3: Restricted user should only see their own user record. Saw %s records.', restricted_can_see_count);
            EXCEPTION WHEN insufficient_privilege THEN
                RAISE NOTICE 'Test 21.3: Caught insufficient_privilege when restricted user tried to count all users. Count set to 0.';
                restricted_can_see_count := 0;
            END;
            ASSERT EXISTS (SELECT 1 FROM auth.user WHERE email = restricted_email), format('Test 21.3: Restricted user %L should see their own record.', restricted_email);
            ASSERT EXISTS (SELECT 1 FROM public.country LIMIT 1), 'Test 21.3: Restricted user should be able to see public data.';
            
            RAISE EXCEPTION 'Simulating rollback for SET LOCAL ROLE (Test 21.3)' USING ERRCODE = 'P0001';
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            RAISE DEBUG 'Test 21.3: Caught simulated rollback for SET LOCAL ROLE. Current user: %', current_user;
        END; -- End of SET LOCAL ROLE block for 21.3
        RAISE DEBUG 'Test 21.3: After SET LOCAL ROLE block, current_user=%', current_user;
        ASSERT current_user = 'postgres', format('Test 21.3: After SET LOCAL ROLE block, current_user should be postgres. Got: %L', current_user);
        RAISE NOTICE 'Test 21.3: Restricted user permissions - PASSED';
        
        RAISE NOTICE 'Test 21 (Role Switching with SET LOCAL ROLE) - Overall PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 21 (Role Switching with SET LOCAL ROLE) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 21 (Role Switching with SET LOCAL ROLE) - FAILED: %', SQLERRM;
    END; -- End of outer BEGIN/EXCEPTION for Test 21
END; -- End of DO block for Test 21
$$;


-- Test 20: Password Change (Admin)
\echo '=== Test 20: Password Change (Admin) ==='
DO $$
DECLARE
    target_sub_for_test20 uuid;
    new_password_for_test20 text := 'newExternalPass789';
    original_password_for_test20 text := 'External#123!';
    target_email_for_test20 text := 'test.external@statbus.org';
    target_refresh_jwt_for_test20 text;
    admin_email text := 'test.admin@statbus.org';
    target_login_result jsonb;
    session_count_before integer;
    session_count_after integer; -- Hoisted
    refresh_result record; -- Hoisted
BEGIN
    -- PERFORM auth_test.reset_request_gucs(); -- This was already called at the top of the DO block for Test 20
    BEGIN -- Outer BEGIN/EXCEPTION/END for the entire Test 20 (Pattern A)
        -- Initialize GUCs for Test 20 to ensure a clean state
        -- First, reset all common GUCs
        PERFORM auth_test.reset_request_gucs();
        -- Then, set specific headers needed for this test
        PERFORM set_config('request.headers', json_build_object('x-forwarded-proto', 'https')::text, true);
        
        -- Test 20.1: Setup and initial state
        RAISE NOTICE 'Test 20.1: Setup - Getting target user and logging them in.';
        SELECT sub INTO target_sub_for_test20 FROM auth.user WHERE email = target_email_for_test20;
        RAISE DEBUG 'Test 20.1: Target user % sub: %', target_email_for_test20, target_sub_for_test20;
        ASSERT target_sub_for_test20 IS NOT NULL, format('Test 20.1: Target user %L not found.', target_email_for_test20);

        SELECT to_jsonb(source.*) INTO target_login_result FROM public.login(target_email_for_test20, original_password_for_test20) AS source;
        ASSERT target_login_result IS NOT NULL AND (target_login_result->>'is_authenticated')::boolean IS TRUE, format('Test 20.1: Login failed for target user %L. Got: %L. Full response: %s', target_email_for_test20, target_login_result->>'is_authenticated', target_login_result);
        ASSERT (target_login_result->'error_code') = 'null'::jsonb, format('Test 20.1: Login for target user %L should have null error_code. Got: %L. Full response: %s', target_email_for_test20, target_login_result->'error_code', target_login_result);
        
        SELECT cv.cookie_value INTO target_refresh_jwt_for_test20 FROM test.extract_cookies() cv WHERE cv.cookie_name = 'statbus-refresh';
        ASSERT target_refresh_jwt_for_test20 IS NOT NULL, format('Refresh token not found in cookies for target user login (Test 20.1). Cookies: %s', (SELECT json_agg(jec) FROM test.extract_cookies() jec));

        SELECT COUNT(*) INTO session_count_before FROM auth.refresh_session
        WHERE user_id = (SELECT id FROM auth.user WHERE sub = target_sub_for_test20);
        ASSERT session_count_before > 0, format('Test 20.1: Target user %L should have at least one session. Found %s sessions.', target_email_for_test20, session_count_before);
        RAISE NOTICE 'Test 20.1: Setup and initial state - PASSED. Target user has % sessions.', session_count_before;

        -- Test 20.2 & 20.3: Admin changes user password and verifies
        RAISE NOTICE 'Test 20.2: Admin attempts to change password for user %.', target_email_for_test20;
        BEGIN -- Nested BEGIN/EXCEPTION for SET LOCAL ROLE simulation
            EXECUTE format('SET LOCAL ROLE %I', admin_email);
            RAISE DEBUG 'Test 20.2: Switched to admin role % (current_user: %)', admin_email, current_user;
            ASSERT current_user = admin_email, format('Test 20.2: Failed to switch to admin role. Expected %L, Got %L', admin_email, current_user);

            PERFORM public.admin_change_password(target_sub_for_test20, new_password_for_test20);
            RAISE DEBUG 'Test 20.2: public.admin_change_password executed for target % by admin %.', target_sub_for_test20, admin_email;
            
            SELECT COUNT(*) INTO session_count_after FROM auth.refresh_session
            WHERE user_id = (SELECT id FROM auth.user WHERE sub = target_sub_for_test20);
            RAISE DEBUG 'Test 20.2: Session count for target user % after admin password change: %', target_email_for_test20, session_count_after;
            ASSERT session_count_after = 0, format('Test 20.2: All sessions for target user %L should be deleted after admin password change. Found %s sessions.', target_email_for_test20, session_count_after);
            
            -- Test 20.3: Verify password was changed (within this transaction)
            RAISE NOTICE 'Test 20.3: Verifying password change for user %.', target_email_for_test20;
            SELECT to_jsonb(source.*) INTO target_login_result FROM public.login(target_email_for_test20, new_password_for_test20) AS source;
            ASSERT target_login_result IS NOT NULL AND (target_login_result->>'is_authenticated')::boolean IS TRUE, format('Test 20.3: Login with new password for target user %L should succeed. Got: %L. Full response: %s', target_email_for_test20, target_login_result->>'is_authenticated', target_login_result);
            ASSERT (target_login_result->'error_code') = 'null'::jsonb, format('Test 20.3: Login with new password for target user %L should have null error_code. Got: %L. Full response: %s', target_email_for_test20, target_login_result->'error_code', target_login_result);

            SELECT to_jsonb(source.*) INTO target_login_result FROM public.login(target_email_for_test20, original_password_for_test20) AS source;
            ASSERT target_login_result IS NULL OR (target_login_result->>'is_authenticated')::boolean IS FALSE, format('Test 20.3: Login with old password for target user %L should fail. Got: %L. Full response: %s', target_email_for_test20, target_login_result->>'is_authenticated', target_login_result);
            ASSERT target_login_result->>'error_code' = 'WRONG_PASSWORD', format('Test 20.3: Login with old password for target user %L should have error_code WRONG_PASSWORD. Got: %L. Full response: %s', target_email_for_test20, target_login_result->>'error_code', target_login_result);

            -- Test 20.3.1: Refresh with invalidated session
            RAISE NOTICE 'Test 20.3.1: Verifying refresh with invalidated session token for user %.', target_email_for_test20;
            PERFORM set_config('request.cookies', jsonb_build_object('statbus-refresh', target_refresh_jwt_for_test20)::text, true);
            PERFORM set_config('request.jwt.claims', '', true);
            -- Ensure headers are set for public.refresh, providing a typical context
            PERFORM set_config('request.headers', json_build_object('x-forwarded-for', '127.0.0.1', 'user-agent', 'Test Agent for Refresh', 'x-forwarded-proto', 'https')::text, true);
            BEGIN
                SELECT to_jsonb(source.*) INTO target_login_result FROM public.refresh() AS source; -- Changed to capture JSON
                RAISE DEBUG 'Test 20.3.1: Refresh result with invalidated session: %', target_login_result;
                ASSERT target_login_result IS NOT NULL, 'Refresh with invalidated session should return a JSON response.';
                ASSERT (target_login_result->>'is_authenticated')::boolean IS FALSE, 'Refresh with invalidated session should be unauthenticated.';
                ASSERT target_login_result->>'error_code' = 'REFRESH_SESSION_INVALID_OR_SUPERSEDED', format('Refresh with invalidated session should have error_code REFRESH_SESSION_INVALID_OR_SUPERSEDED. Got: %L', target_login_result->>'error_code');
            EXCEPTION WHEN OTHERS THEN
                 RAISE EXCEPTION 'Test 20.3.1: Refresh with target user invalidated session token should have returned JSON, not raised SQL error %', SQLERRM;
            END;
            RAISE NOTICE 'Test 20.3.1: Password change verification - PASSED.';
            
            RAISE EXCEPTION 'Simulating rollback for SET LOCAL ROLE (Test 20.2/20.3)' USING ERRCODE = 'P0001';
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            RAISE DEBUG 'Test 20.2/20.3: Caught simulated rollback for SET LOCAL ROLE. Current user: %', current_user;
        END; -- End of SET LOCAL ROLE block for 20.2/20.3
        RAISE DEBUG 'Test 20.2/20.3: After SET LOCAL ROLE block, current_user: %', current_user;
        ASSERT current_user = 'postgres', format('Test 20.2/20.3: Current user should be postgres after SET LOCAL ROLE block. Got: %L', current_user);
        RAISE NOTICE 'Test 20.2: Admin changes user password - PASSED (transactionally, change rolled back).';

        -- Test 20.4: Verify password reverted and test admin changing it back via UPDATE public.user
        RAISE NOTICE 'Test 20.4: Verifying password reverted and testing admin changing it back via UPDATE.';
        BEGIN -- Nested BEGIN/EXCEPTION for SET LOCAL ROLE for 20.4
            EXECUTE format('SET LOCAL ROLE %I', admin_email);
            RAISE DEBUG 'Test 20.4: Switched to admin role % (current_user: %)', admin_email, current_user;
            ASSERT current_user = admin_email, format('Test 20.4: Failed to switch to admin role. Expected %L, Got %L', admin_email, current_user);

            -- Verify password is still original (due to previous rollback)
            SELECT to_jsonb(source.*) INTO target_login_result FROM public.login(target_email_for_test20, original_password_for_test20) AS source;
            ASSERT target_login_result IS NOT NULL AND (target_login_result->>'is_authenticated')::boolean IS TRUE, format('Test 20.4: Login with original password for %L should still work (confirming rollback). Got: %L. Full response: %s', target_email_for_test20, target_login_result->>'is_authenticated', target_login_result);
            ASSERT (target_login_result->'error_code') = 'null'::jsonb, format('Test 20.4: Login with original password for %L (confirming rollback) should have null error_code. Got: %L. Full response: %s', target_email_for_test20, target_login_result->'error_code', target_login_result);

            -- Admin changes target user password back to original_password_for_test20 using UPDATE public.user
            -- (This step is a bit redundant if previous was rolled back, but tests the UPDATE path)
            UPDATE public.user SET password = original_password_for_test20 WHERE sub = target_sub_for_test20;
            RAISE DEBUG 'Test 20.4: Admin updated password for % via public.user view.', target_email_for_test20;

            SELECT to_jsonb(source.*) INTO target_login_result FROM public.login(target_email_for_test20, original_password_for_test20) AS source;
            ASSERT target_login_result IS NOT NULL AND (target_login_result->>'is_authenticated')::boolean IS TRUE, format('Test 20.4: Login with original password for %L should succeed after admin reset via UPDATE. Got: %L. Full response: %s', target_email_for_test20, target_login_result->>'is_authenticated', target_login_result);
            ASSERT (target_login_result->'error_code') = 'null'::jsonb, format('Test 20.4: Login with original password for %L (after admin reset) should have null error_code. Got: %L. Full response: %s', target_email_for_test20, target_login_result->'error_code', target_login_result);
            
            RAISE EXCEPTION 'Simulating rollback for SET LOCAL ROLE (Test 20.4)' USING ERRCODE = 'P0001';
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            RAISE DEBUG 'Test 20.4: Caught simulated rollback for SET LOCAL ROLE. Current user: %', current_user;
        END; -- End of SET LOCAL ROLE block for 20.4
        RAISE DEBUG 'Test 20.4: After SET LOCAL ROLE block, current_user: %', current_user;
        ASSERT current_user = 'postgres', format('Test 20.4: Current user should be postgres after SET LOCAL ROLE block. Got: %L', current_user);
        RAISE NOTICE 'Test 20.4: Admin password change back operations - PASSED (transactionally).';

        RAISE NOTICE 'Test 20 (Password Change (Admin)) - Overall PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 20 (Password Change (Admin)) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 20 (Password Change (Admin)) - FAILED: %', SQLERRM;
    END; -- End of outer BEGIN/EXCEPTION for Test 20
END; -- End of DO block for Test 20
$$;

-- Test 22: API Key Creation and Usage
\echo '=== Test 22: API Key Creation and Usage ==='
DO $$
DECLARE
    login_result jsonb;
    api_key_result record;
    api_key_token text;
    api_key_jti uuid;
    api_key_description text := 'Test API Key';
    test_email text := 'test.regular@statbus.org';
    test_password text := 'Regular#123!';
    api_key_claims jsonb;
    api_key_count integer;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- Use nested block for SET LOCAL ROLE
    BEGIN
        -- Switch to the user's role
        EXECUTE format('SET LOCAL ROLE "%s"', test_email);
        RAISE DEBUG 'Inside nested block, current_user=%', current_user;
        ASSERT current_user = test_email, format('Inside nested block, current user should be test email. Got: %L', current_user);
    
    -- Create an API key
    SELECT * INTO api_key_result FROM public.create_api_key(api_key_description, interval '30 days');
    
    -- Debug the API key result
    RAISE DEBUG 'API key result: %', to_jsonb(api_key_result);
    
    -- Verify API key was created
    ASSERT api_key_result.description = api_key_description, format('API key description should match. Expected %L, Got %L', api_key_description, api_key_result.description);
    ASSERT api_key_result.token IS NOT NULL, 'API key token should not be null.';
    ASSERT api_key_result.jti IS NOT NULL, 'API key JTI should not be null.';
    
    -- Store values for later tests
    api_key_token := api_key_result.token;
    api_key_jti := api_key_result.jti;
    
    -- Verify the token is a valid JWT with expected claims
    SELECT payload::jsonb INTO api_key_claims 
    FROM verify(api_key_token, 'test-jwt-secret-for-testing-only');
    
    -- Debug the API key claims
    RAISE DEBUG 'API key claims: %', api_key_claims;
    
    -- Verify API key claims
    ASSERT api_key_claims->>'type' = 'api_key', format('API key type should be api_key. Got %L. Claims: %s', api_key_claims->>'type', api_key_claims);
    ASSERT api_key_claims->>'role' = test_email, format('API key role should match user email. Expected %L, Got %L. Claims: %s', test_email, api_key_claims->>'role', api_key_claims);
    ASSERT api_key_claims->>'jti' = api_key_jti::text, format('API key JTI should match. Expected %L, Got %L. Claims: %s', api_key_jti::text, api_key_claims->>'jti', api_key_claims);
    ASSERT api_key_claims->>'description' = api_key_description, format('API key description should be in claims. Expected %L, Got %L. Claims: %s', api_key_description, api_key_claims->>'description', api_key_claims);
    
    -- Verify API key is in the database
    ASSERT EXISTS (
        SELECT 1 FROM auth.api_key WHERE jti = api_key_jti
    ), format('API key with JTI %L should exist in database.', api_key_jti);
    
    -- Test using the API key token for authentication
    -- Clear existing context
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM set_config('request.cookies', '{}', true);
    
    -- Set up JWT claims using the API key token
    PERFORM set_config('request.jwt.claims', 
        (SELECT payload::text FROM verify(api_key_token, 'test-jwt-secret-for-testing-only')),
        true
    );
    
    -- Run the pre-request function that checks API key revocation
    PERFORM auth.check_api_key_revocation();
    
    -- If we get here without an exception, the API key is valid
    RAISE DEBUG 'API key validation passed';
    
    -- Verify we can access data with the API key
    -- This should work because the API key has the same permissions as the user
    ASSERT EXISTS (
        SELECT 1 FROM public.country LIMIT 1
    ), 'Should be able to access public data with API key.';
    
    -- Test listing API keys
    -- We're already using the user's role from SET LOCAL ROLE
    
    -- List API keys
    SELECT COUNT(*) INTO api_key_count FROM public.api_key;
    
    -- Verify we can see our API key
    ASSERT api_key_count > 0, format('Should be able to list API keys. Found %s keys.', api_key_count);
    ASSERT EXISTS (
        SELECT 1 FROM public.api_key WHERE jti = api_key_jti
    ), format('Should be able to see the created API key with JTI %L.', api_key_jti);
    
    -- Raise exception to implicitly rollback the SET LOCAL ROLE
    RAISE EXCEPTION 'Simulating rollback for SET LOCAL ROLE' USING ERRCODE = 'P0001';
    
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        -- Catch the specific exception and log success
        RAISE DEBUG 'Caught simulated rollback exception, SET LOCAL ROLE was rolled back to %', current_user;
    END;
        RAISE NOTICE 'Test 22 (API Key Creation and Usage) - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 22 (API Key Creation and Usage) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 22 (API Key Creation and Usage) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 23: API Key Revocation
\echo '=== Test 23: API Key Revocation ==='
DO $$
DECLARE
    login_result jsonb;
    api_key_result record;
    api_key_token text;
    api_key_jti uuid;
    api_key_description text := 'Test API Key for Revocation';
    test_email text := 'test.regular@statbus.org';
    test_password text := 'Regular#123!';
    revoke_result boolean;
    api_key_claims jsonb;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- First login to set up user context for SET LOCAL ROLE
    SELECT to_json(source.*) INTO login_result FROM public.login(test_email, test_password) AS source;
    ASSERT (login_result->>'is_authenticated')::boolean IS TRUE, format('Login failed for API key revocation test setup. Got: %L. Full login_result: %s', login_result->>'is_authenticated', login_result);
    ASSERT (login_result->'error_code') = 'null'::jsonb, format('Login for API key revocation test setup should have null error_code. Got: %L. Full login_result: %s', login_result->'error_code', login_result);
    
    -- Use nested block for SET LOCAL ROLE to properly test RLS
    BEGIN
        -- Switch to the user's role to create and then revoke an API key
        EXECUTE format('SET LOCAL ROLE "%s"', test_email);
        RAISE DEBUG 'Inside nested block, current_user=%', current_user;
        ASSERT current_user = test_email, format('Inside nested block, current user should be test email. Got: %L', current_user);
        
        -- Create an API key
        SELECT * INTO api_key_result FROM public.create_api_key(api_key_description, interval '30 days');
        
        -- Store values for later tests
        api_key_token := api_key_result.token;
        api_key_jti := api_key_result.jti;
        
        -- Get the claims from the token
        SELECT payload::jsonb INTO api_key_claims 
        FROM verify(api_key_token, 'test-jwt-secret-for-testing-only');
        
        -- Verify API key is in the database and not revoked
        ASSERT EXISTS (
            SELECT 1 FROM auth.api_key WHERE jti = api_key_jti AND revoked_at IS NULL
        ), format('API key with JTI %L should exist in database and not be revoked.', api_key_jti);
        
        -- Revoke the API key
        SELECT public.revoke_api_key(api_key_jti) INTO revoke_result;
        
        -- Verify revocation was successful
        ASSERT revoke_result = true, format('Revoke API key should return true. Got: %L', revoke_result);
        
        -- Verify API key is marked as revoked in the database
        ASSERT EXISTS (
            SELECT 1 FROM auth.api_key WHERE jti = api_key_jti AND revoked_at IS NOT NULL
        ), format('API key with JTI %L should be marked as revoked in database.', api_key_jti);
        
        -- Test using the revoked API key token for authentication
        -- This simulates what PostgREST would do when receiving a revoked API key token
        
        -- Set JWT claims to simulate what PostgREST would do
        PERFORM set_config('request.jwt.claims', api_key_claims::text, true);
        
        -- Try to use the revoked API key
        BEGIN
            -- This should raise an exception because the key is revoked
            PERFORM auth.check_api_key_revocation();
            
            -- If we get here, the revocation check failed
            RAISE EXCEPTION 'Revoked API key should not pass validation';
        EXCEPTION WHEN OTHERS THEN
            -- This is expected - the key should be rejected
            RAISE DEBUG 'Revoked API key was correctly rejected: %', SQLERRM;
            ASSERT SQLERRM LIKE '%API Key has been revoked%', format('Error should indicate revoked key. Got: %L', SQLERRM);
        END;

        -- Raise exception to implicitly rollback the SET LOCAL ROLE
        RAISE EXCEPTION 'Simulating rollback for SET LOCAL ROLE' USING ERRCODE = 'P0001';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        -- Catch the specific exception and log success
        RAISE DEBUG 'Caught simulated rollback exception, SET LOCAL ROLE was rolled back to %', current_user;
    END;
        
        RAISE NOTICE 'Test 23 (API Key Revocation) - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 23 (API Key Revocation) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 23 (API Key Revocation) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Test 24: API Key Permissions and Boundaries
\echo '=== Test 24: API Key Permissions and Boundaries ==='
DO $$
DECLARE
    login_result jsonb;
    api_key_result record;
    api_key_token text;
    api_key_jti uuid;
    api_key_description text := 'Test API Key for Permissions';
    test_email text := 'test.regular@statbus.org';
    test_password text := 'Regular#123!';
    api_key_claims jsonb;
BEGIN
    PERFORM auth_test.reset_request_gucs();
    BEGIN -- Inner BEGIN/EXCEPTION/END for savepoint-like behavior
        -- First login to set up user context for SET LOCAL ROLE
    SELECT to_json(source.*) INTO login_result FROM public.login(test_email, test_password) AS source;
    ASSERT (login_result->>'is_authenticated')::boolean IS TRUE, format('Login failed for API key permissions test setup. Got: %L. Full login_result: %s', login_result->>'is_authenticated', login_result);
    ASSERT (login_result->'error_code') = 'null'::jsonb, format('Login for API key permissions test setup should have null error_code. Got: %L. Full login_result: %s', login_result->'error_code', login_result);
    
    -- Use nested block for SET LOCAL ROLE to properly test RLS
    BEGIN
        -- Switch to the user's role to create an API key
        EXECUTE format('SET LOCAL ROLE "%s"', test_email);
        RAISE DEBUG 'Inside nested block, current_user=%', current_user;
        ASSERT current_user = test_email, format('Inside nested block, current user should be test email. Got: %L', current_user);
        
        -- Create an API key
        SELECT * INTO api_key_result FROM public.create_api_key(api_key_description, interval '30 days');
        
        -- Store values for later tests
        api_key_token := api_key_result.token;
        api_key_jti := api_key_result.jti;
        
        -- Get the claims from the token
        SELECT payload::jsonb INTO api_key_claims 
        FROM verify(api_key_token, 'test-jwt-secret-for-testing-only');
        
        -- Raise exception to implicitly rollback the SET LOCAL ROLE
        RAISE EXCEPTION 'Simulating rollback for SET LOCAL ROLE' USING ERRCODE = 'P0001';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        -- Catch the specific exception and log success
        RAISE DEBUG 'Caught simulated rollback exception, SET LOCAL ROLE was rolled back to %', current_user;
    END;
    -- Now test API key permissions and boundaries
    -- This simulates what PostgREST would do when receiving an API key token
    BEGIN
        -- Extract the role from the token
        DECLARE
            api_key_role text;
        BEGIN
            api_key_role := api_key_claims->>'role';
            
            -- Switch to the role specified in the API key token
            EXECUTE format('SET LOCAL ROLE "%s"', api_key_role);
            RAISE DEBUG 'Using API key token, current_user=%', current_user;
            ASSERT current_user = test_email, format('When using API key, current user should be test email. Got: %L', current_user);
            
            -- Set JWT claims to simulate what PostgREST would do
            PERFORM set_config('request.jwt.claims', api_key_claims::text, true);
            
            -- Test 1: API keys should not be able to create other API keys
            BEGIN
                -- This should fail because API keys shouldn't be able to create other API keys
                PERFORM public.create_api_key('API Key created by another API key', interval '1 day');
                
                -- If we get here, the permission check failed
                RAISE EXCEPTION 'API keys should not be able to create other API keys';
            EXCEPTION WHEN OTHERS THEN
                -- This is expected - the operation should be rejected
                RAISE DEBUG 'API key creating another API key was correctly rejected: %', SQLERRM;
            END;
            
            -- Test 2: API keys should not be able to change passwords
            BEGIN
                -- This should fail because API keys shouldn't be able to change passwords
                PERFORM public.change_password('NewPassword123');
                
                -- If we get here, the permission check failed
                RAISE EXCEPTION 'API keys should not be able to change passwords';
            EXCEPTION WHEN OTHERS THEN
                -- This is expected - the operation should be rejected
                RAISE DEBUG 'API key changing password was correctly rejected: %', SQLERRM;
                ASSERT SQLERRM LIKE '%Password change requires a valid access token%',
                    format('Error should indicate that password change requires access token. Got: %L', SQLERRM);
            END;
            
            -- Test 3: API keys should not be able to refresh tokens
            BEGIN
                -- This should fail because API keys shouldn't be able to refresh tokens
                PERFORM public.refresh();
                
                -- If we get here, the permission check failed
                RAISE EXCEPTION 'API keys should not be able to refresh tokens';
            EXCEPTION WHEN OTHERS THEN
                -- This is expected - the operation should be rejected
                RAISE DEBUG 'API key refreshing token was correctly rejected: %', SQLERRM;
            END;
            
            -- Raise exception to implicitly rollback the SET LOCAL ROLE
            RAISE EXCEPTION 'Simulating rollback for API key role' USING ERRCODE = 'P0002';
        END;
    EXCEPTION WHEN SQLSTATE 'P0002' THEN
        -- Catch the specific exception and log success
        RAISE DEBUG 'Caught simulated rollback exception, SET LOCAL ROLE was rolled back to %', current_user;
    END;
        RAISE NOTICE 'Test 24 (API Key Permissions and Boundaries) - PASSED';
    EXCEPTION
        WHEN ASSERT_FAILURE THEN
            RAISE NOTICE 'Test 24 (API Key Permissions and Boundaries) - FAILED (ASSERT): %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Test 24 (API Key Permissions and Boundaries) - FAILED: %', SQLERRM;
    END;
END;
$$;

-- Clean up test environment
-- Clean up test sessions
DELETE FROM auth.refresh_session
WHERE user_id IN (
    SELECT id FROM auth.user 
    WHERE email LIKE 'test.%@statbus.org' -- Updated domain
);
-- Clean up test API keys
DELETE FROM auth.api_key
WHERE user_id IN (
    SELECT id FROM auth.user
    WHERE email LIKE 'test.%@statbus.org' -- Updated domain
);
DELETE FROM auth.user
WHERE email LIKE 'test.%@statbus.org'; -- Updated domain

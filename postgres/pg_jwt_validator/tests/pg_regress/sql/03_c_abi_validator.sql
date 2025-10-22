-- Test the full C-ABI validator function via the test_validator_wrapper.

-- Set the secret via the GUC. This is how the real validator will get it.
SET pg_jwt_validator.secret = 'c-abi-test-secret';

-- Create a temp table to hold the secret for the sign() function.
CREATE TEMP TABLE vars AS SELECT 'c-abi-test-secret' AS secret;

-- Test 1: Valid token, issuer, and scope
\echo 'Test 1: Should return true for a valid token with correct issuer and scope'
WITH
  payload AS (
    SELECT json_build_object(
      'sub', 'user1', 'email', 'user1@test.com', 'role', 'test_user',
      'exp', extract(epoch from now() + interval '1 day'),
      'iss', 'https://auth.statbus.org',
      'aud', 'db:connect'
    )::json AS data
  ),
  token AS (
    SELECT sign(payload.data, (SELECT secret FROM vars)) AS data FROM payload
  )
SELECT test_validator_wrapper(
  token.data,
  'https://auth.statbus.org',
  'db:connect'
) AS is_valid FROM token;

-- Test 2: Wrong issuer
\echo 'Test 2: Should return false for a token with the wrong issuer'
WITH
  payload AS (
    SELECT json_build_object(
      'sub', 'user1', 'email', 'user1@test.com', 'role', 'test_user',
      'exp', extract(epoch from now() + interval '1 day'),
      'iss', 'https://auth.statbus.org', -- Signed with correct issuer
      'aud', 'db:connect'
    )::json AS data
  ),
  token AS (
    SELECT sign(payload.data, (SELECT secret FROM vars)) AS data FROM payload
  )
SELECT test_validator_wrapper(
  token.data,
  'https://wrong-issuer.com', -- But validated against the wrong one
  'db:connect'
) AS is_valid FROM token;

-- Test 3: Wrong scope
\echo 'Test 3: Should return false for a token with the wrong scope'
WITH
  payload AS (
    SELECT json_build_object(
      'sub', 'user1', 'email', 'user1@test.com', 'role', 'test_user',
      'exp', extract(epoch from now() + interval '1 day'),
      'iss', 'https://auth.statbus.org',
      'aud', 'db:connect' -- Signed with correct scope
    )::json AS data
  ),
  token AS (
    SELECT sign(payload.data, (SELECT secret FROM vars)) AS data FROM payload
  )
SELECT test_validator_wrapper(
  token.data,
  'https://auth.statbus.org',
  'db:wrong-scope' -- But validated against the wrong one
) AS is_valid FROM token;

-- Test 4: Expired token
\echo 'Test 4: Should return false for an expired token'
WITH
  payload AS (
    SELECT json_build_object(
      'sub', 'user1', 'email', 'user1@test.com', 'role', 'test_user',
      'exp', extract(epoch from now() - interval '1 day'), -- Expired
      'iss', 'https://auth.statbus.org',
      'aud', 'db:connect'
    )::json AS data
  ),
  token AS (
    SELECT sign(payload.data, (SELECT secret FROM vars)) AS data FROM payload
  )
SELECT test_validator_wrapper(
  token.data,
  'https://auth.statbus.org',
  'db:connect'
) AS is_valid FROM token;

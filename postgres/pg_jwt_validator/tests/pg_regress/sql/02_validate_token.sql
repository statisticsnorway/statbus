-- Set a secret for our tests
CREATE TEMP TABLE vars AS SELECT 'super-secret-key-for-testing' AS secret;

-- Test 1: A valid token
\echo 'Test 1: Should return true for a valid token'
WITH
  payload AS (
    SELECT json_build_object(
      'sub', '1234567890',
      'email', 'test@example.com',
      'role', 'regular_user',
      'exp', extract(epoch from now() + interval '1 hour'),
      'iss', 'https://auth.statbus.org',
      'aud', 'db:connect'
    )::json AS data
  ),
  token AS (
    SELECT sign(payload.data, (SELECT secret FROM vars)) AS data FROM payload
  )
SELECT validate_token(token.data, (SELECT secret FROM vars)) AS is_valid FROM token;

-- Test 2: An expired token
\echo 'Test 2: Should return false for an expired token'
WITH
  payload AS (
    SELECT json_build_object(
      'sub', '1234567890',
      'email', 'test@example.com',
      'role', 'regular_user',
      'exp', extract(epoch from now() - interval '1 hour'),
      'iss', 'https://auth.statbus.org',
      'aud', 'db:connect'
    )::json AS data
  ),
  token AS (
    SELECT sign(payload.data, (SELECT secret FROM vars)) AS data FROM payload
  )
SELECT validate_token(token.data, (SELECT secret FROM vars)) AS is_valid FROM token;


-- Test 3: A token with a wrong secret
\echo 'Test 3: Should return false for a token with a wrong secret'
WITH
  payload AS (
    SELECT json_build_object(
      'sub', '1234567890',
      'email', 'test@example.com',
      'role', 'regular_user',
      'exp', extract(epoch from now() + interval '1 hour'),
      'iss', 'https://auth.statbus.org',
      'aud', 'db:connect'
    )::json AS data
  ),
  token AS (
    SELECT sign(payload.data, (SELECT secret FROM vars)) AS data FROM payload
  )
SELECT validate_token(token.data, 'wrong-secret') AS is_valid FROM token;

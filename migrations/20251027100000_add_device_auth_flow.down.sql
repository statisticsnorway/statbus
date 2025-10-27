BEGIN;

DROP FUNCTION IF EXISTS public.request_device_authorization(text, text);
DROP FUNCTION IF EXISTS auth.generate_random_string(integer, text);
DROP TABLE IF EXISTS auth.device_authorization_request;

COMMIT;

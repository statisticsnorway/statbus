BEGIN;

DROP FUNCTION IF EXISTS public.poll_device_authorization(text);
DROP TYPE IF EXISTS auth.device_flow_error;

COMMIT;

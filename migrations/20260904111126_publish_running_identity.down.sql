-- Down Migration 20260904111126: publish running identity
BEGIN;

DROP FUNCTION public.running_identity();

NOTIFY pgrst, 'reload schema';

END;

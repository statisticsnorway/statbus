-- Down Migration 20260130093218: add_auth_gate_function
BEGIN;

DROP FUNCTION IF EXISTS public.auth_gate();

END;

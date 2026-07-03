-- Down Migration 20260703210000: add recovery park-degraded columns to upgrade statbus_046
BEGIN;

ALTER TABLE public.upgrade
  DROP COLUMN recovery_attempts,
  DROP COLUMN recovery_parked_at,
  DROP COLUMN recovery_parked_reason;

END;

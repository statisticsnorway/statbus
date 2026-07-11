-- Down Migration 20260711201431: upgrade parked requires in progress constraint statbus 154
BEGIN;

ALTER TABLE public.upgrade
  DROP CONSTRAINT chk_upgrade_parked_requires_in_progress;

-- The one-time legacy-cleanup UPDATE in the up migration is not reversible: it
-- cleared STALE park markers off non-in_progress rows (garbage — state is
-- authoritative). There is nothing to restore.

END;

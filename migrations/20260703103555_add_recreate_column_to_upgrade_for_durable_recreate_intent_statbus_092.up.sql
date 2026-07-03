-- Migration 20260703103555: add recreate column to upgrade for durable recreate intent statbus_092
BEGIN;

-- STATBUS-092: the --recreate intent used to ride a volatile in-memory flag set
-- by a ':recreate' NOTIFY that the daemon processed AFTER the sha-NOTIFY had
-- already driven executeScheduled to claim + run the upgrade — so a --recreate
-- upgrade silently ran as a normal (data-preserving) one. Persist the intent
-- DURABLY on the row instead: whoever claims the scheduled row reads it here,
-- independent of NOTIFY timing. Default false = a normal (non-recreate) upgrade.
ALTER TABLE public.upgrade
  ADD COLUMN recreate boolean NOT NULL DEFAULT false;

END;

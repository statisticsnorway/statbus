-- Down Migration 20260703103555: add recreate column to upgrade for durable recreate intent statbus_092
BEGIN;

ALTER TABLE public.upgrade
  DROP COLUMN recreate;

END;

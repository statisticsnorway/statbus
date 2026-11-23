-- Down Migration 20261123114610: countries have a centre latitude and longitude
BEGIN;

ALTER TABLE public.country
  DROP COLUMN latitude,
  DROP COLUMN longitude;

END;

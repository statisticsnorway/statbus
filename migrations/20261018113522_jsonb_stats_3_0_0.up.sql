-- Migration 20261018113522: jsonb_stats 3.0.0
--
-- The db image carries jsonb_stats v3.0.0 (postgres/Dockerfile), whose library
-- the box loads when the upgrade restarts the db container before migrating.
-- 3.0.0 makes numeric aggregates exact and order-independent (STATBUS-512).
-- Its SQL interface is unchanged, so the update only records the new version.
-- Summaries stored by 2.0.0 lack sum_sq; 3.0.0 rebuilds it when it reads them,
-- and they become exact at their next recompute, as jsonb_stats's README
-- "Upgrading" prescribes. A fresh database already gets 3.0.0 from CREATE
-- EXTENSION and is left as it is.
BEGIN;

SET LOCAL lock_timeout = '30s';

DO $jsonb_stats_3_0_0$
BEGIN
    IF (SELECT extversion FROM pg_extension WHERE extname = 'jsonb_stats') = '2.0.0' THEN
        ALTER EXTENSION jsonb_stats UPDATE TO '3.0.0';
    END IF;
END;
$jsonb_stats_3_0_0$;

END;

-- Migration 20261015163419: sql_saga 1.1
--
-- The db image carries sql_saga v1.1 (postgres/Dockerfile), whose libraries
-- the box loads when the upgrade restarts the db container before migrating.
-- This brings the installed extension from 1.0 to 1.1 in place, as sql_saga's
-- doc/upgrade.md prescribes. The update is atomic and refuses, leaving 1.0
-- intact, on anything it cannot reconcile. A fresh database already gets 1.1
-- from CREATE EXTENSION and is left as it is.
BEGIN;

SET LOCAL lock_timeout = '30s';

DO $sql_saga_1_1$
BEGIN
    IF (SELECT extversion FROM pg_extension WHERE extname = 'sql_saga') = '1.0' THEN
        ALTER EXTENSION sql_saga UPDATE TO '1.1';
    END IF;
END;
$sql_saga_1_1$;

END;

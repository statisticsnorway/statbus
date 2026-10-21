-- Migration 20261021130641: sql_saga 1.3
--
-- The db image carries sql_saga v1.3 (postgres/Dockerfile), whose libraries
-- the box loads when the upgrade restarts the db container before migrating,
-- with the application stopped in maintenance. This brings the installed
-- extension from 1.1 or 1.2 to 1.3 in place, as sql_saga's doc/upgrade.md
-- prescribes (STATBUS-519): 1.3 ships the direct update scripts
-- sql_saga--1.1--1.3.sql and sql_saga--1.2--1.3.sql, and PostgreSQL selects
-- one of them. Never hop through 1.2 with the 1.3 libraries loaded: the
-- update scripts to 1.2 refuse against the 1.3 native library.
--
-- 1.3 closes the 1.1 history-policy/RLS bypass, keeps XOR unique key column
-- order, converts the child-side CHECK of each regular foreign key to a
-- constraint trigger (so a dump restores in any table order), and repairs
-- managed views that lag their base table. The update is atomic: its last
-- step runs sql_saga.check_integrity() and any refusal rolls back
-- everything, leaving the previous version intact. A fresh database already
-- gets 1.3 from CREATE EXTENSION and is left as it is.
BEGIN;

SET LOCAL lock_timeout = '30s';

DO $sql_saga_1_3$
BEGIN
    IF (SELECT extversion FROM pg_extension WHERE extname = 'sql_saga') IN ('1.1', '1.2') THEN
        ALTER EXTENSION sql_saga UPDATE TO '1.3';
    END IF;
END;
$sql_saga_1_3$;

END;

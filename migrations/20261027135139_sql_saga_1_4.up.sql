-- Migration 20261027135139: sql_saga 1.4
--
-- The db image carries sql_saga v1.4 (postgres/Dockerfile), whose libraries
-- the box loads when the upgrade restarts the db container before migrating,
-- with the application stopped in maintenance. This brings the installed
-- extension from 1.0-1.3 to 1.4 in place, as sql_saga's doc/upgrade.md
-- prescribes (STATBUS-531): 1.4 ships a direct update script per released
-- version, sql_saga--1.0--1.4.sql through sql_saga--1.3--1.4.sql, and
-- PostgreSQL selects one of them. Never run an older update script with the
-- 1.4 libraries loaded: its native-library guard requires the 1.4 build.
--
-- 1.4 makes the public management functions SECURITY INVOKER trampolines that
-- run user-object DDL as the immediate caller (migrations connect as the
-- superuser POSTGRES_ADMIN_USER, so they are unaffected), adds ON DELETE
-- CASCADE for regular-to-temporal foreign keys, refuses TRUNCATE of a
-- referenced parent, always defers the referenced-side regular foreign key
-- triggers in temporal_merge (a reshaped timeline no longer refuses or
-- cascades), and names relations schema-qualified in messages. The update is
-- atomic: its last step runs sql_saga.check_integrity() and any refusal rolls
-- back everything, leaving the previous version intact. A fresh database
-- already gets 1.4 from CREATE EXTENSION and is left as it is.
BEGIN;

SET LOCAL lock_timeout = '30s';

DO $sql_saga_1_4$
BEGIN
    IF (SELECT extversion FROM pg_extension WHERE extname = 'sql_saga') IN ('1.0', '1.1', '1.2', '1.3') THEN
        ALTER EXTENSION sql_saga UPDATE TO '1.4';
    END IF;
END;
$sql_saga_1_4$;

END;

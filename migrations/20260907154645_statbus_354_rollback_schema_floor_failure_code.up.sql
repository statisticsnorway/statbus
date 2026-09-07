-- Migration 20260907154645: statbus_354_rollback_schema_floor_failure_code
-- Keep ALTER TYPE ADD VALUE as the migration's only statement. PostgreSQL
-- versions before 12 cannot use a newly-added enum value in the same transaction.
ALTER TYPE public.upgrade_failure_code
ADD VALUE 'ROLLBACK_SCHEMA_FLOOR_FAILED';

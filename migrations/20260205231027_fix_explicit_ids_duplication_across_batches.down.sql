-- Down Migration: Restore explicit_*_ids in batch payloads
-- This restores the pre-fix behavior where explicit_*_ids were duplicated across batches.
-- WARNING: This reintroduces the concurrency bug (unique constraint violations with concurrency > 1).

BEGIN;

-- Restore previous versions from the preceding migration
-- The functions will be recreated by migrate down of 20260201145821

DROP FUNCTION IF EXISTS worker.derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date, bigint);
DROP PROCEDURE IF EXISTS worker.statistical_unit_refresh_batch(jsonb);

COMMIT;

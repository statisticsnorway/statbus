-- Down Migration 20261016134307: statistical_history hash_partition meaning
BEGIN;

COMMENT ON COLUMN public.statistical_history.hash_partition IS NULL;

END;

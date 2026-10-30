-- Down Migration 20261030135909: drop the one-slot constraint
BEGIN;
ALTER TABLE public.statistical_history DROP CONSTRAINT IF EXISTS statistical_history_hash_partition_is_one_slot;
END;

-- Migration 20261030135909: STATBUS-543 statistical_history per-slot rows hold one hash slot
--
-- worker.derive_statistical_history_period deletes a spawn's slot range by
-- comparing hash_partition with the singleton ranges of its first and
-- past-the-end slots. That selects exactly the rows of those slots because
-- every per-slot row holds one slot. The constraint states that invariant
-- where the data lives, so a writer storing wider ranges fails at insert.
BEGIN;

ALTER TABLE public.statistical_history
  ADD CONSTRAINT statistical_history_hash_partition_is_one_slot
  CHECK (hash_partition IS NULL OR upper(hash_partition) = lower(hash_partition) + 1);

COMMENT ON CONSTRAINT statistical_history_hash_partition_is_one_slot ON public.statistical_history IS
  'A per-slot row (hash_partition NOT NULL) holds exactly one hash slot [s,s+1); NULL marks the reduced summary row. derive_statistical_history_period relies on this to delete a slot range by range comparison on the partition unique keys.';

END;

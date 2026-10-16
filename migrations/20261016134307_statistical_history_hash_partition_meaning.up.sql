-- Migration 20261016134307: statistical_history hash_partition meaning
-- STATBUS-513: state what a row of statistical_history is, by its hash_partition.
BEGIN;

COMMENT ON COLUMN public.statistical_history.hash_partition IS
'NULL marks the period total: the row the application reads. A range marks a partition slot, the partial count for units whose hash_slot falls in that range; worker.statistical_history_reduce sums the slots into the total. The row level security policies show application roles only the totals, so a reader running as the caller (statistical_history_highcharts, PostgREST) gets one row per period. Worker code running as the table owner sees the slots as well.';

END;

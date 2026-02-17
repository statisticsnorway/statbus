-- Migration 20260215164911: fix_drilldown_partition_seq_filter
--
-- NO-OP: statistical_history_facet and statistical_unit_facet use separate UNLOGGED
-- partition tables. Their main tables contain only root entries, so the SECURITY DEFINER
-- drilldown functions (which bypass RLS) don't need partition_seq IS NULL filters.
--
-- Only statistical_history has inline partition_seq, but no drilldown function queries
-- it directly — statistical_history_drilldown queries statistical_history_facet.
BEGIN;
-- Nothing to do.
END;

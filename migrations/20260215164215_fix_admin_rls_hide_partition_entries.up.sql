-- Migration 20260215164215: fix_admin_rls_hide_partition_entries
--
-- Only statistical_history has inline partition_seq (small table, ~50 root rows).
-- statistical_history_facet and statistical_unit_facet use separate UNLOGGED partition
-- tables, so their main tables have no partition entries to hide.
--
-- Fix admin_user MANAGE policy for statistical_history:
-- Changed: USING(true) → USING(partition_seq IS NULL)
-- Kept: WITH CHECK(true) so worker procedures (SECURITY DEFINER) can still insert partition entries
BEGIN;

-- =====================================================================
-- statistical_history (inline partition_seq — needs RLS fix)
-- =====================================================================
DROP POLICY IF EXISTS statistical_history_admin_user_manage ON public.statistical_history;
CREATE POLICY statistical_history_admin_user_manage ON public.statistical_history
    FOR ALL TO admin_user
    USING (partition_seq IS NULL) WITH CHECK (true);

END;

-- Migration 20260215164215: fix_admin_rls_hide_partition_entries
--
-- The admin_user MANAGE policy had USING(true), making partition entries visible
-- to admin users in SELECT queries. Worker procedures are SECURITY DEFINER
-- (bypass RLS as postgres), so restricting the USING clause is safe.
--
-- Changed: USING(true) → USING(partition_seq IS NULL)
-- Kept: WITH CHECK(true) so direct INSERTs of partition entries still work
BEGIN;

-- =====================================================================
-- statistical_history
-- =====================================================================
DROP POLICY IF EXISTS statistical_history_admin_user_manage ON public.statistical_history;
CREATE POLICY statistical_history_admin_user_manage ON public.statistical_history
    FOR ALL TO admin_user
    USING (partition_seq IS NULL) WITH CHECK (true);

-- =====================================================================
-- statistical_history_facet
-- =====================================================================
DROP POLICY IF EXISTS statistical_history_facet_admin_user_manage ON public.statistical_history_facet;
CREATE POLICY statistical_history_facet_admin_user_manage ON public.statistical_history_facet
    FOR ALL TO admin_user
    USING (partition_seq IS NULL) WITH CHECK (true);

-- =====================================================================
-- statistical_unit_facet
-- =====================================================================
DROP POLICY IF EXISTS statistical_unit_facet_admin_user_manage ON public.statistical_unit_facet;
CREATE POLICY statistical_unit_facet_admin_user_manage ON public.statistical_unit_facet
    FOR ALL TO admin_user
    USING (partition_seq IS NULL) WITH CHECK (true);

END;

-- Down Migration 20260215164215: fix_admin_rls_hide_partition_entries
BEGIN;

-- Restore original admin_user MANAGE policy with USING(true)
DROP POLICY IF EXISTS statistical_history_admin_user_manage ON public.statistical_history;
CREATE POLICY statistical_history_admin_user_manage ON public.statistical_history
    FOR ALL TO admin_user
    USING (true) WITH CHECK (true);

END;

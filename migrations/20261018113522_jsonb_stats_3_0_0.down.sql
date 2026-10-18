-- Down Migration 20261018113522: jsonb_stats 3.0.0
--
-- jsonb_stats ships no 3.0.0 -> 2.0.0 script, and summaries written by 3.0.0
-- carry sum_sq and exact values that 2.0.0 does not produce. Returning to
-- 2.0.0 means restoring the pre-upgrade backup, which the upgrade's rollback
-- does.
BEGIN;

DO $jsonb_stats_3_0_0_down$
BEGIN
    RAISE EXCEPTION 'jsonb_stats 3.0.0 cannot be downgraded in place; restore the pre-upgrade backup';
END;
$jsonb_stats_3_0_0_down$;

END;

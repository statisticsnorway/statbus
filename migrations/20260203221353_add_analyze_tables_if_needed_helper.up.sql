-- Migration 20260203221353: add_analyze_tables_if_needed_helper
BEGIN;

-- Helper function to conditionally ANALYZE tables only when needed
-- This avoids expensive ANALYZE calls when statistics are still fresh,
-- while ensuring stats are updated when tables have been modified significantly.
--
-- The check is very cheap: just reads pg_stat_user_tables which is already in memory.
-- PostgreSQL tracks n_mod_since_analyze automatically.
--
-- Default thresholds match PostgreSQL's autovacuum_analyze defaults:
-- - threshold_pct = 0.1 (10% of rows modified)
-- - min_threshold = 50 (at least 50 modifications)
-- ANALYZE triggers when: n_mod_since_analyze >= max(min_threshold, n_live_tup * threshold_pct)

CREATE FUNCTION admin.analyze_tables_if_needed(
    tables_to_check regclass[],
    threshold_pct numeric DEFAULT 0.1,
    min_threshold integer DEFAULT 50
)
RETURNS TABLE(table_name regclass, was_analyzed boolean, mods_before bigint)
LANGUAGE plpgsql
AS $analyze_tables_if_needed$
DECLARE
    tbl regclass;
    _stats RECORD;
    _threshold_count bigint;
    _needs_analyze boolean;
BEGIN
    FOREACH tbl IN ARRAY tables_to_check LOOP
        -- Get current stats (very cheap - reads from stats collector memory)
        SELECT 
            s.n_live_tup,
            s.n_mod_since_analyze
        INTO _stats
        FROM pg_stat_user_tables s
        WHERE s.relid = tbl;
        
        IF NOT FOUND THEN
            -- Table not in user tables (might be temp or system)
            table_name := tbl;
            was_analyzed := false;
            mods_before := NULL;
            RETURN NEXT;
            CONTINUE;
        END IF;
        
        -- Calculate threshold: max of min_threshold or percentage of rows
        _threshold_count := GREATEST(min_threshold, (_stats.n_live_tup * threshold_pct)::bigint);
        _needs_analyze := _stats.n_mod_since_analyze >= _threshold_count;
        
        table_name := tbl;
        mods_before := _stats.n_mod_since_analyze;
        
        IF _needs_analyze THEN
            RAISE DEBUG 'ANALYZE needed for %: % mods >= % threshold (% rows)',
                tbl, _stats.n_mod_since_analyze, _threshold_count, _stats.n_live_tup;
            EXECUTE format('ANALYZE %s', tbl::text);
            was_analyzed := true;
        ELSE
            RAISE DEBUG 'ANALYZE skipped for %: % mods < % threshold',
                tbl, _stats.n_mod_since_analyze, _threshold_count;
            was_analyzed := false;
        END IF;
        
        RETURN NEXT;
    END LOOP;
END;
$analyze_tables_if_needed$;

COMMENT ON FUNCTION admin.analyze_tables_if_needed IS 
'Conditionally ANALYZE tables only when modifications exceed threshold.
Very cheap check (reads pg_stat_user_tables), avoids unnecessary ANALYZE calls.
Returns which tables were analyzed and their modification count before analysis.';

END;

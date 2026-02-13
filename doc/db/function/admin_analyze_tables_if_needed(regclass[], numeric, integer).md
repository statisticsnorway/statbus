```sql
CREATE OR REPLACE FUNCTION admin.analyze_tables_if_needed(tables_to_check regclass[], threshold_pct numeric DEFAULT 0.1, min_threshold integer DEFAULT 50)
 RETURNS TABLE(table_name regclass, was_analyzed boolean, mods_before bigint)
 LANGUAGE plpgsql
AS $function$
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
$function$
```

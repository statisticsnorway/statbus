```sql
CREATE OR REPLACE PROCEDURE admin.cleanup_statistical_unit_jsonb_indices()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    r RECORD;
BEGIN
    -- Use a query to find and drop all indices matching the patterns
    FOR r IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename = 'statistical_unit'
          AND indexname ILIKE 'su_ei_%_idx'
            OR indexname ILIKE 'su_s_%_idx'
            OR indexname ILIKE 'su_ss_%_sum_idx'
            OR indexname ILIKE 'su_ss_%_count_idx'
        ORDER BY indexname
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS %I', r.indexname);
        RAISE NOTICE 'Dropped index %', r.indexname;
    END LOOP;
END;
$procedure$
```

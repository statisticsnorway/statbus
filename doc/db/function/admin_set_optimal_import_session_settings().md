```sql
CREATE OR REPLACE FUNCTION admin.set_optimal_import_session_settings()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'admin', 'pg_temp'
AS $function$
BEGIN
    -- Memory boosts for import operations (session-level, reverts after transaction)
    -- These override the conservative server defaults during batch imports.
    -- Note: temp_buffers and wal_buffers cannot be changed at runtime.
    SET LOCAL work_mem = '1GB';                    -- Boost for large hash joins and sorts
    SET LOCAL maintenance_work_mem = '2GB';        -- Boost for index operations during temporal_merge
    
    -- Join strategy optimization (session-level, reverts after transaction)
    SET LOCAL enable_hashjoin = on;                -- Prefer hash joins for large lookups
    SET LOCAL enable_nestloop = off;               -- Avoid nested loops for large datasets  
    SET LOCAL enable_mergejoin = off;              -- Avoid expensive sort-based merge joins
    
    -- Query optimizer hints for import workloads (session-level)
    SET LOCAL random_page_cost = 1.1;              -- Optimize for modern storage (SSD)
    SET LOCAL cpu_tuple_cost = 0.01;               -- Slight preference for CPU over I/O
    SET LOCAL hash_mem_multiplier = 8.0;           -- Allow very large hash tables
    
    -- Enable more aggressive query optimization for complex import operations
    SET LOCAL from_collapse_limit = 20;            -- Allow more complex query flattening
    SET LOCAL join_collapse_limit = 20;            -- Allow more join reordering for optimization
    
    -- Log the optimization application for debugging
    RAISE DEBUG 'Import session optimization applied: work_mem=1GB, maintenance_work_mem=2GB, hash_mem_multiplier=8x';
END;
$function$
```

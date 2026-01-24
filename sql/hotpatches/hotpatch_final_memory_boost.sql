-- HOT-PATCH: Final memory boost for holistic external_idents processing
-- Addresses: Global identifier deduplication across 1M+ rows with complex CTEs and window functions
-- Expected improvement: Prevent spilling to disk, handle large aggregations in memory
-- Date: 2026-01-23

-- CRITICAL: Increase work_mem significantly for complex window functions and CTEs
-- The external_idents step processes 1M+ rows with multiple window functions
ALTER SYSTEM SET work_mem = '500MB';

-- CRITICAL: Large maintenance_work_mem for internal sorts and hash operations
ALTER SYSTEM SET maintenance_work_mem = '2GB';

-- Optimize for large sequential operations (common in analytical workloads)
ALTER SYSTEM SET random_page_cost = '1.1';

-- Allow larger hash tables for the complex joins
ALTER SYSTEM SET hash_mem_multiplier = '8.0';

-- Increase temp_buffers for temporary table operations
ALTER SYSTEM SET temp_buffers = '512MB';

-- Reload configuration
SELECT pg_reload_conf();

-- Verify settings
SELECT name, setting, unit, context, short_desc 
FROM pg_settings 
WHERE name IN ('work_mem', 'maintenance_work_mem', 'random_page_cost', 'hash_mem_multiplier', 'temp_buffers')
ORDER BY name;

SELECT 'HOT-PATCH APPLIED: Final memory boost for holistic external_idents processing' as status;
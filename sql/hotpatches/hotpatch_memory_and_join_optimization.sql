-- HOT-PATCH: Critical memory and join optimization for external_idents
-- Addresses: 87MB+ memory sorts, inefficient merge joins, temp table issues
-- Expected improvement: 2-3x faster processing for external_idents step
-- Date: 2026-01-23

-- 1. CRITICAL: Increase work_mem for import operations
-- Current queries are using 180MB+ memory for sorts, need more space
ALTER SYSTEM SET work_mem = '256MB';
SELECT pg_reload_conf();

-- 2. CRITICAL: Optimize join method selection for import operations  
-- Hash joins are more efficient for the external_ident lookup patterns
-- These will be applied per-session by import procedures
ALTER SYSTEM SET enable_mergejoin = off;
ALTER SYSTEM SET enable_hashjoin = on;
ALTER SYSTEM SET enable_nestloop = off; -- Force hash joins for lookups
SELECT pg_reload_conf();

-- 3. Increase other memory settings for bulk operations
ALTER SYSTEM SET hash_mem_multiplier = 4.0; -- Allow larger hash tables
ALTER SYSTEM SET maintenance_work_mem = '2GB'; -- For index operations
SELECT pg_reload_conf();

-- Verification
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name IN ('work_mem', 'enable_mergejoin', 'enable_hashjoin', 'enable_nestloop', 'hash_mem_multiplier');

SELECT 'HOT-PATCH APPLIED: Memory and join optimization for external_idents processing' as status;
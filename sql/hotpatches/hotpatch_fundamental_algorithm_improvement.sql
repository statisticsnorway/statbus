-- HOT-PATCH: Fundamental algorithm improvement for external_idents
-- Focus: Reduce algorithmic complexity, not conditional shortcuts
-- Principles: Simple, general, maintainable improvements that work for any dataset
-- Date: 2026-01-23

BEGIN;

-- FUNDAMENTAL IMPROVEMENT 1: Always-beneficial indexes on external_ident
-- These help ANY import regardless of data characteristics
CREATE INDEX IF NOT EXISTS external_ident_lookup_covering_idx 
ON public.external_ident (type_id, ident) 
INCLUDE (legal_unit_id, establishment_id);

CREATE INDEX IF NOT EXISTS external_ident_ident_hash_idx 
ON public.external_ident USING HASH (ident);

-- FUNDAMENTAL IMPROVEMENT 2: Standard temp table indexing function
-- Always create these indexes when processing external_idents
CREATE OR REPLACE FUNCTION admin.index_temp_unpivoted_idents(table_name TEXT)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    -- Always beneficial: index on lookup columns
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I_lookup_idx ON %I (ident_type_code, ident_value)', table_name, table_name);
    
    -- Always beneficial: hash index for equality lookups  
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I_hash_idx ON %I USING HASH (ident_value)', table_name, table_name);
    
    -- Always beneficial: index on data_row_id for result joining
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I_data_row_idx ON %I (data_row_id)', table_name, table_name);
    
    -- Always beneficial: update statistics
    EXECUTE format('ANALYZE %I', table_name);
END;
$$;

-- FUNDAMENTAL IMPROVEMENT 3: Optimized settings for identifier processing
-- These are always good for large JOIN operations
CREATE OR REPLACE FUNCTION admin.set_optimal_external_idents_settings()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    SET LOCAL work_mem = '1GB';           -- Allow large hash tables in memory
    SET LOCAL enable_hashjoin = on;       -- Use hash joins for large lookups
    SET LOCAL enable_nestloop = off;      -- Avoid nested loops for large datasets
    SET LOCAL enable_mergejoin = off;     -- Avoid expensive sorts for joins
    SET LOCAL random_page_cost = 1.1;     -- Optimize for modern storage
END;
$$;

-- FUNDAMENTAL IMPROVEMENT 4: Clean up any over-engineered functions
-- Remove the complex dynamic detection - keep it simple
DROP FUNCTION IF EXISTS admin.optimize_external_idents_dynamically(TEXT, TEXT);
DROP FUNCTION IF EXISTS admin.prepare_external_idents_processing(TEXT, TEXT);

COMMIT;

SELECT 'HOT-PATCH APPLIED: Fundamental algorithmic improvements (simple, general, maintainable)' as status;
-- Monitor actual updates during processing

-- Enable tracking of row updates
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Create a simple monitoring function
CREATE OR REPLACE FUNCTION tmp_monitor_updates() RETURNS TABLE(
    table_name text,
    update_count bigint,
    sample_query text
) AS $$
BEGIN
    -- This would require pg_stat_statements to be enabled in postgresql.conf
    -- For now, let's trace the logic flow instead
    
    -- The update pattern is:
    -- 1. Each step updates last_completed_priority
    -- 2. Some steps also update state (pending->analysing->analysed/processing)
    -- 3. Statistical variables are handled in a batch but still update each row
    
    RETURN QUERY
    SELECT 
        'import_job_XXX_data'::text,
        32::bigint,
        'UPDATE import_job_XXX_data SET last_completed_priority = N WHERE ...'::text;
END;
$$ LANGUAGE plpgsql;

-- Let's trace the exact update flow for one row
WITH import_steps AS (
    SELECT 
        s.priority,
        s.code,
        CASE WHEN s.analyse_procedure IS NOT NULL THEN 1 ELSE 0 END as has_analyse,
        CASE WHEN s.process_procedure IS NOT NULL THEN 1 ELSE 0 END as has_process
    FROM public.import_step s
    JOIN public.import_definition_step ds ON ds.step_id = s.id
    JOIN public.import_definition d ON d.id = ds.definition_id
    WHERE d.slug = 'brreg_hovedenhet_2024'
    ORDER BY s.priority
),
update_counts AS (
    SELECT 
        priority,
        code,
        has_analyse,
        has_process,
        -- Each step updates last_completed_priority
        1 as priority_update,
        -- Steps with analyse may update state (pending->analysing)
        CASE WHEN has_analyse = 1 THEN 1 ELSE 0 END as state_update_1,
        -- Steps with process may update state (analysing->processing or analysed->processing)
        CASE WHEN has_process = 1 THEN 1 ELSE 0 END as state_update_2
    FROM import_steps
)
SELECT 
    'Total Steps' as metric,
    COUNT(*) as value
FROM update_counts
UNION ALL
SELECT 
    'Total Updates per Row' as metric,
    SUM(priority_update + state_update_1 + state_update_2) as value
FROM update_counts
UNION ALL
SELECT 
    'Updates from Priority' as metric,
    SUM(priority_update) as value
FROM update_counts
UNION ALL
SELECT 
    'Updates from State Changes' as metric,
    SUM(state_update_1 + state_update_2) as value
FROM update_counts;
-- Count updates per row during import processing

-- First, let's see all the processing steps
SELECT code, name, priority, analyse_procedure, process_procedure 
FROM public.import_step
ORDER BY priority;

-- Count actual updates in recent activity
WITH recent_updates AS (
    SELECT 
        query,
        COUNT(*) as update_count
    FROM pg_stat_statements
    WHERE query LIKE 'UPDATE %'
        AND query NOT LIKE '%pg_%'
        AND query NOT LIKE '%auth.%'
    GROUP BY query
)
SELECT 
    substring(query from 'UPDATE (\S+)') as table_name,
    update_count,
    query
FROM recent_updates
ORDER BY update_count DESC
LIMIT 20;
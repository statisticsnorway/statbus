-- Count how many updates happen per row

-- First, let's see what steps are enabled for the import definitions
SELECT 
    d.slug as definition_slug,
    s.code as step_code,
    s.priority,
    CASE WHEN s.analyse_procedure IS NOT NULL THEN 'A' ELSE '' END ||
    CASE WHEN s.process_procedure IS NOT NULL THEN 'P' ELSE '' END as operations
FROM public.import_definition d
JOIN public.import_definition_step ds ON ds.definition_id = d.id
JOIN public.import_step s ON s.id = ds.step_id
WHERE d.slug LIKE 'brreg_%_2024'
ORDER BY d.slug, s.priority;

-- Count the theoretical maximum updates per row
WITH step_counts AS (
    SELECT 
        d.slug,
        COUNT(DISTINCT s.id) as total_steps,
        COUNT(DISTINCT CASE WHEN s.analyse_procedure IS NOT NULL THEN s.id END) as analyse_steps,
        COUNT(DISTINCT CASE WHEN s.process_procedure IS NOT NULL THEN s.id END) as process_steps
    FROM public.import_definition d
    JOIN public.import_definition_step ds ON ds.definition_id = d.id
    JOIN public.import_step s ON s.id = ds.step_id
    WHERE d.slug LIKE 'brreg_%_2024'
    GROUP BY d.slug
)
SELECT 
    slug,
    total_steps,
    analyse_steps,
    process_steps,
    -- Each step updates last_completed_priority at least once
    -- Some steps update state multiple times (pending->analysing->analysed/processing)
    total_steps as min_updates,
    -- Worst case: state updates + priority updates
    total_steps * 2 as max_updates
FROM step_counts;
-- Performance monitoring queries for processing phase optimization

-- 1. Current job states and progress  
SELECT 
    slug,
    state,
    total_rows,
    imported_rows,
    analysis_batch_size,
    processing_batch_size,
    analysis_rows_per_sec,
    import_rows_per_sec,
    analysis_completed_pct,
    import_completed_pct,
    EXTRACT(epoch FROM (COALESCE(processing_stop_at, NOW()) - COALESCE(processing_start_at, NOW()))) as processing_seconds,
    EXTRACT(epoch FROM (COALESCE(analysis_stop_at, NOW()) - COALESCE(analysis_start_at, NOW()))) as analysis_seconds,
    analysis_start_at,
    analysis_stop_at,
    processing_start_at,
    processing_stop_at,
    current_step_code,
    error
FROM public.import_job 
ORDER BY created_at DESC;

-- 2. Monitor processing step performance (using import_definition_step table)
SELECT 
    ij.slug,
    ids.step_name,
    ij.batch_size,
    ij.processed_rows,
    ij.total_rows,
    CASE 
        WHEN ij.processed_rows > 0 AND EXTRACT(epoch FROM (COALESCE(ij.finished_at, NOW()) - ij.started_at)) > 0
        THEN ROUND((ij.processed_rows::numeric / EXTRACT(epoch FROM (COALESCE(ij.finished_at, NOW()) - ij.started_at)))::numeric, 2)
        ELSE 0 
    END as rows_per_second_for_job
FROM public.import_job ij
LEFT JOIN public.import_definition_step ids ON ij.import_definition_slug = ids.import_definition_slug
WHERE ij.slug LIKE '%_2026_selection'
ORDER BY ij.started_at DESC NULLS LAST;

-- 3. Database activity monitoring (updates, inserts, deletes)
SELECT 
    schemaname,
    relname as tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_tup_hot_upd as hot_updates,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples
FROM pg_stat_user_tables 
WHERE schemaname IN ('public', 'worker')
ORDER BY (n_tup_ins + n_tup_upd + n_tup_del) DESC;

-- 4. Track external_ident operations specifically
SELECT 
    COUNT(*) as external_ident_count,
    COUNT(DISTINCT legal_unit_id) as unique_legal_units,
    COUNT(DISTINCT establishment_id) as unique_establishments,
    COUNT(DISTINCT type_id) as unique_ident_types
FROM public.external_ident;

-- 5. Statistical_history_facet operations
SELECT COUNT(*) as statistical_history_facet_count
FROM public.statistical_history_facet;
\echo public.sector_hierarchy
CREATE OR REPLACE FUNCTION public.sector_hierarchy(sector_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('sector', to_jsonb(s.*)) AS data
          FROM public.sector AS s
         WHERE sector_id IS NOT NULL AND s.id = sector_id
         ORDER BY s.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;
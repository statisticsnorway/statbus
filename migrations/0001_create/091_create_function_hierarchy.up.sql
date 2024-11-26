BEGIN;

\echo public.region_hierarchy
CREATE OR REPLACE FUNCTION public.region_hierarchy(region_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('region', to_jsonb(s.*)) AS data
          FROM public.region AS s
         WHERE region_id IS NOT NULL AND s.id = region_id
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;

\echo public.country_hierarchy
CREATE OR REPLACE FUNCTION public.country_hierarchy(country_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('country', to_jsonb(s.*)) AS data
          FROM public.country AS s
         WHERE country_id IS NOT NULL AND s.id = country_id
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;

END;
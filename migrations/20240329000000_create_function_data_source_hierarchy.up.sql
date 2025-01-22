BEGIN;

CREATE OR REPLACE FUNCTION public.data_source_hierarchy(data_source_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('data_source', to_jsonb(s.*)) AS data
          FROM public.data_source AS s
         WHERE data_source_id IS NOT NULL AND s.id = data_source_id
         ORDER BY s.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;

END;
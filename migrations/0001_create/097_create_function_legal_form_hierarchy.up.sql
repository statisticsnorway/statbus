\echo public.legal_form_hierarchy
CREATE OR REPLACE FUNCTION public.legal_form_hierarchy(legal_form_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('legal_form', to_jsonb(lf.*)) AS data
          FROM public.legal_form AS lf
         WHERE legal_form_id IS NOT NULL AND lf.id = legal_form_id
         ORDER BY lf.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;
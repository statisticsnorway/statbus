\echo public.enterprise_hierarchy
CREATE OR REPLACE FUNCTION public.enterprise_hierarchy(enterprise_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object(
                'enterprise',
                 to_jsonb(en.*)
                 || (SELECT public.external_idents_hierarchy(NULL,NULL,en.id,NULL))
                 || (SELECT public.legal_unit_hierarchy(en.id, valid_on))
                 || (SELECT public.establishment_hierarchy(NULL, en.id, valid_on))
                 || (SELECT public.tag_for_unit_hierarchy(NULL,NULL,en.id,NULL))
                ) AS data
          FROM public.enterprise AS en
         WHERE enterprise_id IS NOT NULL AND en.id = enterprise_id
         ORDER BY en.short_name
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;
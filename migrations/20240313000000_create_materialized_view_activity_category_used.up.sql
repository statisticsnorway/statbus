BEGIN;

CREATE MATERIALIZED VIEW public.activity_category_used AS
SELECT acs.code AS standard_code
     , ac.id
     , ac.path
     , acp.path AS parent_path
     , ac.code
     , ac.label
     , ac.name
     , ac.description
FROM public.activity_category AS ac
JOIN public.activity_category_standard AS acs ON ac.standard_id = acs.id
LEFT JOIN public.activity_category AS acp ON ac.parent_id = acp.id
WHERE acs.id = (SELECT activity_category_standard_id FROM public.settings)
  AND ac.active
  AND ac.path OPERATOR(public.@>) (SELECT array_agg(DISTINCT primary_activity_category_path) FROM public.statistical_unit WHERE primary_activity_category_path IS NOT NULL)
ORDER BY path;

CREATE UNIQUE INDEX "activity_category_used_key"
    ON public.activity_category_used (path);

END;
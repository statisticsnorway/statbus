BEGIN;

\echo public.region_used
CREATE MATERIALIZED VIEW public.region_used AS
SELECT r.id
     , r.path
     , r.level
     , r.label
     , r.code
     , r.name
FROM public.region AS r
WHERE r.path OPERATOR(public.@>) (SELECT array_agg(DISTINCT physical_region_path) FROM public.statistical_unit WHERE physical_region_path IS NOT NULL)
ORDER BY public.nlevel(path), path;

CREATE UNIQUE INDEX "region_used_key"
    ON public.region_used (path);

END;
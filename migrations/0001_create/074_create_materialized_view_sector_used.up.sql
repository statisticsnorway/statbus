\echo public.sector_used
CREATE MATERIALIZED VIEW public.sector_used AS
SELECT s.id
     , s.path
     , s.label
     , s.code
     , s.name
FROM public.sector AS s
WHERE s.path OPERATOR(public.@>) (SELECT array_agg(DISTINCT sector_path) FROM public.statistical_unit WHERE sector_path IS NOT NULL)
  AND s.active
ORDER BY s.path;

CREATE UNIQUE INDEX "sector_used_key"
    ON public.sector_used (path);
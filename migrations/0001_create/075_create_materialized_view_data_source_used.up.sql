\echo public.data_source_used
CREATE MATERIALIZED VIEW public.data_source_used AS
SELECT s.id
     , s.code
     , s.name
FROM public.data_source AS s
WHERE s.id IN (
    SELECT unnest(public.array_distinct_concat(data_source_ids))
      FROM public.statistical_unit
     WHERE data_source_ids IS NOT NULL
  )
  AND s.active
ORDER BY s.code;

CREATE UNIQUE INDEX "data_source_used_key"
    ON public.data_source_used (code);
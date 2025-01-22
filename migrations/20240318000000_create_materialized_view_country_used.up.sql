BEGIN;

CREATE MATERIALIZED VIEW public.country_used AS
SELECT c.id
     , c.iso_2
     , c.name
FROM public.country AS c
WHERE c.id IN (SELECT physical_country_id FROM public.statistical_unit WHERE physical_country_id IS NOT NULL)
  AND c.active
ORDER BY c.id;

CREATE UNIQUE INDEX "country_used_key"
    ON public.country_used (iso_2);

END;
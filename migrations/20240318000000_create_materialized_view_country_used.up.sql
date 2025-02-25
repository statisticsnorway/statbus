BEGIN;

CREATE VIEW public.country_used_def AS
SELECT c.id
     , c.iso_2
     , c.name
FROM public.country AS c
WHERE c.id IN (SELECT physical_country_id FROM public.statistical_unit WHERE physical_country_id IS NOT NULL)
  AND c.active
ORDER BY c.id;

CREATE UNLOGGED TABLE public.country_used AS
SELECT * FROM public.country_used_def;

CREATE UNIQUE INDEX "country_used_key" ON public.country_used (iso_2);

CREATE FUNCTION public.country_used_derive()
RETURNS void
LANGUAGE plpgsql
AS $country_used_derive$
BEGIN
    RAISE DEBUG 'Running country_used_derive()';
    DELETE FROM public.country_used;
    INSERT INTO public.country_used
    SELECT * FROM public.country_used_def;
END;
$country_used_derive$;

END;

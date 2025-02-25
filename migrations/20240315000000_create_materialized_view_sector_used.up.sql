BEGIN;

-- Create view that defines the sectors in use
CREATE VIEW public.sector_used_def AS
SELECT s.id
     , s.path
     , s.label
     , s.code
     , s.name
FROM public.sector AS s
WHERE s.path OPERATOR(public.@>) (SELECT array_agg(DISTINCT sector_path) FROM public.statistical_unit WHERE sector_path IS NOT NULL)
  AND s.active
ORDER BY s.path;

-- Create unlogged table from the view definition
CREATE UNLOGGED TABLE public.sector_used AS
SELECT * FROM public.sector_used_def;

CREATE UNIQUE INDEX "sector_used_key"
    ON public.sector_used (path);

-- Create function to populate the unlogged table
CREATE FUNCTION public.sector_used_derive() 
    RETURNS void 
    LANGUAGE plpgsql 
    SECURITY DEFINER AS $sector_used_derive$
BEGIN
    RAISE DEBUG 'Running sector_used_derive()';
    TRUNCATE TABLE public.sector_used;
    INSERT INTO public.sector_used 
    SELECT * FROM public.sector_used_def;
END;
$sector_used_derive$;

-- Initial population
SELECT public.sector_used_derive();

END;

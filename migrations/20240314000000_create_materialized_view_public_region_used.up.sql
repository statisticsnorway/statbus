BEGIN;

-- Create view that defines the regions in use
CREATE VIEW public.region_used_def AS
SELECT r.id
     , r.path
     , r.level
     , r.label
     , r.code
     , r.name
FROM public.region AS r
WHERE r.path OPERATOR(public.@>) (SELECT array_agg(DISTINCT physical_region_path) FROM public.statistical_unit WHERE physical_region_path IS NOT NULL)
ORDER BY public.nlevel(path), path;

-- Create table from the view definition
CREATE TABLE public.region_used AS
SELECT * FROM public.region_used_def;

CREATE UNIQUE INDEX "region_used_key"
    ON public.region_used (path);

-- Create function to populate the unlogged table
CREATE FUNCTION public.region_used_derive() 
    RETURNS void 
    LANGUAGE plpgsql 
    SECURITY DEFINER AS $region_used_derive$
BEGIN
    RAISE DEBUG 'Running region_used_derive()';
    TRUNCATE TABLE public.region_used;
    INSERT INTO public.region_used 
    SELECT * FROM public.region_used_def;
END;
$region_used_derive$;

-- Initial population
SELECT public.region_used_derive();

END;

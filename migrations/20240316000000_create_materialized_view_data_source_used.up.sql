BEGIN;

-- Create view that defines the data sources in use
CREATE VIEW public.data_source_used_def AS
SELECT s.id
     , s.code
     , s.name
FROM public.data_source AS s
WHERE s.id IN (
    SELECT unnest(public.array_distinct_concat(data_source_ids))
      FROM public.statistical_unit
     WHERE data_source_ids IS NOT NULL
  )
  AND s.enabled
ORDER BY s.code;

-- Create table from the view definition
CREATE TABLE public.data_source_used AS
SELECT * FROM public.data_source_used_def;

CREATE UNIQUE INDEX "data_source_used_key"
    ON public.data_source_used (code);

-- Create function to populate the table
CREATE FUNCTION public.data_source_used_derive()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER AS $data_source_used_derive$
BEGIN
    RAISE DEBUG 'Running data_source_used_derive()';
    DELETE FROM public.data_source_used;
    INSERT INTO public.data_source_used
    SELECT * FROM public.data_source_used_def;
END;
$data_source_used_derive$;

-- Initial population
SELECT public.data_source_used_derive();

END;

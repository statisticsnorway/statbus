BEGIN;

-- Create view that defines the activity categories in use
CREATE VIEW public.activity_category_used_def AS
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
  AND (
         ac.path OPERATOR(public.@>)
         (
         SELECT array_agg(DISTINCT primary_activity_category_path)
         FROM public.statistical_unit
         WHERE primary_activity_category_path IS NOT NULL
         )
         OR
         ac.path OPERATOR(public.@>)
         (
         SELECT array_agg(DISTINCT secondary_activity_category_path)
         FROM public.statistical_unit
         WHERE secondary_activity_category_path IS NOT NULL
         )
      )
ORDER BY path;

-- Create table from the view definition
CREATE TABLE public.activity_category_used AS
SELECT * FROM public.activity_category_used_def;

CREATE UNIQUE INDEX "activity_category_used_key"
    ON public.activity_category_used (path);

-- Create function to populate the table
CREATE FUNCTION public.activity_category_used_derive()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER AS $activity_category_used_derive$
BEGIN
    RAISE DEBUG 'Running activity_category_used_derive()';
    TRUNCATE TABLE public.activity_category_used;
    INSERT INTO public.activity_category_used
    SELECT * FROM public.activity_category_used_def;
END;
$activity_category_used_derive$;

-- Initial population
SELECT public.activity_category_used_derive();

END;

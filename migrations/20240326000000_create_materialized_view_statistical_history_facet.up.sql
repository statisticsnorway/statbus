BEGIN;

CREATE TABLE public.statistical_history_facet AS
SELECT * FROM public.statistical_history_facet_def
ORDER BY year, month;

CREATE FUNCTION public.statistical_history_facet_derive(
  valid_after date DEFAULT '-infinity'::date,
  valid_to date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_facet_derive$
DECLARE
    v_year int;
    v_month int;
BEGIN
    RAISE DEBUG 'Running statistical_history_facet_derive(valid_after=%, valid_to=%)', valid_after, valid_to;

    -- Get relevant periods using the get_statistical_history_periods function
    -- and store them in a temporary table
    CREATE TEMPORARY TABLE temp_periods ON COMMIT DROP AS
    SELECT year, month
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution, -- Get both year and year-month in the same table
        p_valid_after := statistical_history_facet_derive.valid_after,
        p_valid_to := statistical_history_facet_derive.valid_to
    );

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history_facet shf
    USING temp_periods tp
    WHERE shf.year = tp.year
    AND shf.month IS NOT DISTINCT FROM tp.month;

    -- Insert new records for the affected periods
    INSERT INTO public.statistical_history_facet
    SELECT shfd.*
    FROM public.statistical_history_facet_def shfd
    JOIN temp_periods p ON
        shfd.year = p.year AND
        shfd.month IS NOT DISTINCT FROM p.month
    ORDER BY shfd.year, shfd.month;

    -- Clean up
    DROP TABLE IF EXISTS temp_periods;
END;
$statistical_history_facet_derive$;

END;

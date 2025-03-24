BEGIN;

SET client_min_messages TO debug1;

CREATE TABLE public.statistical_history AS
SELECT * FROM public.statistical_history_def
ORDER BY year, month;

CREATE UNIQUE INDEX "statistical_history_month_key"
    ON public.statistical_history
    ( resolution
    , year
    , month
    , unit_type
    ) WHERE resolution = 'year-month'::public.history_resolution;
CREATE UNIQUE INDEX "statistical_history_year_key"
    ON public.statistical_history
    ( resolution
    , year
    , unit_type
    ) WHERE resolution = 'year'::public.history_resolution;

CREATE INDEX idx_history_resolution ON public.statistical_history (resolution);
CREATE INDEX idx_statistical_history_year ON public.statistical_history (year);
CREATE INDEX idx_statistical_history_month ON public.statistical_history (month);
CREATE INDEX idx_statistical_history_births ON public.statistical_history (births);
CREATE INDEX idx_statistical_history_deaths ON public.statistical_history (deaths);
CREATE INDEX idx_statistical_history_count ON public.statistical_history (count);
CREATE INDEX idx_statistical_history_stats_summary ON public.statistical_history USING GIN (stats_summary jsonb_path_ops);

CREATE FUNCTION public.statistical_history_derive(
  valid_after date DEFAULT '-infinity'::date,
  valid_to date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_derive$
DECLARE
    v_year int;
    v_month int;
BEGIN
    RAISE DEBUG 'Running statistical_history_derive(valid_after=%, valid_to=%)', valid_after, valid_to;

    -- Get relevant periods using the get_statistical_history_periods function
    -- and store them in a temporary table
    CREATE TEMPORARY TABLE temp_periods ON COMMIT DROP AS
    SELECT year, month
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution, -- Get both year and year-month in the same table
        p_valid_after := statistical_history_derive.valid_after,
        p_valid_to := statistical_history_derive.valid_to
    );

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history sh
    USING temp_periods tp
    WHERE sh.year = tp.year
    AND sh.month IS NOT DISTINCT FROM tp.month;

    -- Insert new records for the affected periods
    INSERT INTO public.statistical_history
    SELECT shd.*
    FROM public.statistical_history_def shd
    JOIN temp_periods p ON
        shd.year = p.year AND
        shd.month IS NOT DISTINCT FROM p.month
    ORDER BY shd.year, shd.month;

    -- Clean up
    DROP TABLE IF EXISTS temp_periods;
END;
$statistical_history_derive$;

END;
